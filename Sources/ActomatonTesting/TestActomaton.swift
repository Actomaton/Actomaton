import ActomatonCore
import ActomatonEffect
import CustomDump
import XCTest

/// A testing utility that wraps `MealyMachine` + `EffectQueueManager` to provide
/// TCA-like `send` / `receive` assertions with readable diff output.
///
/// `Emission` matches the reducer's side-channel output type, so tests can use
/// the same `Effect<Action, Emission>` reducer shape as production code. `TestActomaton`
/// does not expose emitted values; it only asserts state changes and feedback actions.
///
/// ```swift
/// let testActomaton = TestActomaton(
///     state: MyState(),
///     reducer: myReducer,
///     environment: ()
/// )
///
/// await testActomaton.send(.increment) { state in
///     state.count = 1
/// }
///
/// await testActomaton.receive(.didLoad) { state in
///     state.isLoading = false
/// }
/// ```
///
/// - Note:
///   `State: SendableMetatype` is required (in addition to `Equatable`) so that the
///   `State: Equatable` conformance witness can be sent across isolation when `self` is captured
///   in `@Sendable` closures (e.g. `effectManager.setUp` callbacks, `TaskGroup.addTask`).
///   `State` values themselves do NOT need to be `Sendable`.
public actor TestActomaton<Action, State, Emission>
    where Action: Sendable, State: Equatable & SendableMetatype, Emission: Sendable
{
    private typealias InternalAction = TestActomatonAction<Action>
    private typealias RuntimeState = TestActomatonRuntimeState<Action, State>

    private let machine: MealyMachine<InternalAction, RuntimeState, Effect<InternalAction, Emission>>
    private let effectManager: EffectQueueManager<InternalAction, RuntimeState, Emission>
    private let receivedActionSignal: AsyncStream<Void>
    private var consumedReceivedActionCount: Int = 0

    /// Creates a `TestActomaton` from an `Effect`-based reducer.
    ///
    /// Unlike the original implementation, async effects are preserved and can be asserted with
    /// ``receive(_:timeout:assert:fileID:file:line:)``.
    public init<Environment>(
        state: State,
        reducer: MealyReducer<Action, State, Environment, Effect<Action, Emission>>,
        environment: Environment,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    ) where Environment: Sendable
    {
        let receivedActionSignal = AsyncStream.makeStream(of: Void.self)
        self.receivedActionSignal = receivedActionSignal.stream

        typealias Reducer = MealyReducer<InternalAction, RuntimeState, (), Effect<InternalAction, Emission>>

        let reducer = Reducer { action, state, _ in
            let stateBeforeAction = state.current
            let effect = reducer.run(action.action, &state.current, environment)
            let mappedEffect = effect.map(action: InternalAction.receive)

            switch action {
            case .send:
                state.latestSentState = state.current
                return mappedEffect

            case let .receive(innerAction):
                state.receivedActions.append(
                    (
                        action: innerAction,
                        stateBefore: stateBeforeAction,
                        stateAfter: state.current
                    )
                )

                return Effect<InternalAction, Emission>.fireAndForget { _ in
                    receivedActionSignal.continuation.yield()
                } + mappedEffect
            }
        }

        self.machine = MealyMachine<InternalAction, RuntimeState, Effect<InternalAction, Emission>>(
            state: .init(current: state),
            reducer: reducer
        )

        let effectManager = EffectQueueManager<InternalAction, RuntimeState, Emission>(
            effectContext: effectContext
        )
        self.effectManager = effectManager

        effectManager.setUp(
            withSendability: { [weak self] runEffM in
                await self?.runIsolatedEffectManager(runEffM)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks, emit in
                await self?.sendFromEffect(
                    action,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks,
                    emit: emit
                )
            }
        )
    }

    /// Runs `runEffM` within this actor's isolation, supplying the underlying ``EffectManager``
    /// so that conformers can mutate their own bookkeeping safely from unstructured tasks without
    /// capturing `self` themselves.
    private func runIsolatedEffectManager<EffM>(
        _ runEffM: (EffM) -> Void
    ) where EffM: EffectManager<InternalAction, RuntimeState, Effect<InternalAction, Emission>>
    {
        runEffM(effectManager as! EffM)
    }

    /// Re-enters this actor's isolation to dispatch an effect-originated feedback action.
    /// Bridges the `sendAction` callback handed to ``EffectQueueManager``.
    private func sendFromEffect(
        _ action: InternalAction,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> Task<(), Never>?
    {
        let output = machine.send(action)
        return effectManager.processOutput(
            output,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks,
            emit: emit
        )
    }

    /// Sends an action and asserts how state changes before any feedback action is received.
    ///
    /// Feedback actions emitted from `.next`, `async`, or `AsyncSequence` effects must be asserted
    /// separately via ``receive(_:timeout:assert:fileID:file:line:)``.
    /// If previously received feedback actions remain unhandled, this method fails immediately and
    /// does not dispatch `action`.
    ///
    /// Returns a ``TestActomatonTask`` that can be used to await completion of the triggered effect
    /// chain or cancel it explicitly.
    @discardableResult
    public func send(
        _ action: Action,
        assert: ((_ state: inout State) -> Void)? = nil,
        timeout: Duration = .seconds(1),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line
    ) async -> TestActomatonTask<Emission>
    {
        let runtimeState = self.machine.state

        let unhandledActions = runtimeState.receivedActions
            .dropFirst(self.consumedReceivedActionCount)
            .map(\.action)

        if !unhandledActions.isEmpty {
            var actions = ""
            customDump(unhandledActions, to: &actions)
            let s = unhandledActions.count == 1 ? "" : "s"

            XCTFail(
                """
                Must handle \(unhandledActions.count) received \
                action\(s) before sending an action.

                  \(fileID):\(line)

                Unhandled actions:
                \(actions)
                """,
                file: filePath,
                line: line
            )

            return TestActomatonTask(sendResult: nil, timeout: timeout)
        }

        let expected = runtimeState.current

        let output = self.machine.send(.send(action))
        let sendResult = self.effectManager.processOutput(
            output,
            priority: nil,
            tracksFeedbacks: true
        )

        guard let actual = (self.machine.state).latestSentState else {
            XCTFail(
                """
                Internal error: failed to capture state after sending \(action).

                  \(fileID):\(line)
                """,
                file: filePath,
                line: line
            )
            return .init(sendResult: sendResult, timeout: timeout)
        }

        self.assertStateChange(
            label: "sent \(action)",
            expected: expected,
            actual: actual,
            fileID: fileID,
            filePath: filePath,
            line: line,
            assert: assert
        )

        // No barrier is needed here: synchronous feedback (`.next`) is already surfaced into
        // `receivedActions` by `machine.send`'s recursive resolution, so the fail-fast check on the
        // next `send` sees it. Asynchronous feedback is awaited deterministically by `receive` via
        // `receivedActionSignal`, not eagerly drained here.
        return .init(sendResult: sendResult, timeout: timeout)
    }

    /// Asserts an action was received from an effect and verifies the resulting state change.
    public func receive(
        _ isMatching: @escaping (_ action: Action) -> Bool,
        assert updateStateToExpectedResult: ((_ state: inout State) -> Void)? = nil,
        timeout: Duration = .seconds(1),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line
    ) async
    {
        await self._receive(
            matching: isMatching,
            assert: updateStateToExpectedResult,
            noQueuedMessage: "Expected to receive an action, but none was queued.",
            unexpectedActionDescription: { receivedAction in
                var actionDump = ""
                customDump(receivedAction, to: &actionDump, indent: 2)
                return actionDump
            },
            timeout: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line
        )
    }
}

extension TestActomaton where Action: Equatable
{
    /// Asserts the next received action matches `expectedAction`, then verifies the resulting state
    /// change.
    public func receive(
        _ expectedAction: Action,
        assert updateStateToExpectedResult: ((_ state: inout State) -> Void)? = nil,
        timeout: Duration = .seconds(1),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line
    ) async
    {
        await self._receive(
            matching: { $0 == expectedAction },
            assert: updateStateToExpectedResult,
            noQueuedMessage: "Expected to receive \(expectedAction), but no action was queued.",
            unexpectedActionDescription: { receivedAction in
                CustomDump.diff(expectedAction, receivedAction, format: .proportional)
                    ?? """
                    Expected:
                      \(expectedAction)

                    Received:
                      \(receivedAction)
                    """
            },
            timeout: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line
        )
    }
}

extension TestActomaton
{
    private func _receive(
        matching isMatching: @escaping (Action) -> Bool,
        assert updateStateToExpectedResult: ((_ state: inout State) -> Void)?,
        noQueuedMessage: @autoclosure () -> String,
        unexpectedActionDescription: (Action) -> String,
        timeout: Duration,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt
    ) async
    {
        guard await self.waitForReceivedAction(
            timeout: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line
        )
        else { return }

        guard
            let (receivedAction, stateBefore, stateAfter) = await self.nextReceivedAction()
        else {
            XCTFail(
                """
                \(noQueuedMessage())

                  \(fileID):\(line)
                """,
                file: filePath,
                line: line
            )
            return
        }

        let receivedActionLater = await self.hasLaterReceivedAction(matching: isMatching)

        if !isMatching(receivedAction) {
            XCTFail(
                """
                Received unexpected action\(receivedActionLater ? " before this one" : ""):

                  \(fileID):\(line)

                \(unexpectedActionDescription(receivedAction))
                """,
                file: filePath,
                line: line
            )
        }
        else {
            self.assertStateChange(
                label: "received \(receivedAction)",
                expected: stateBefore,
                actual: stateAfter,
                fileID: fileID,
                filePath: filePath,
                line: line,
                assert: updateStateToExpectedResult
            )
        }
    }

    /// Waits until at least one unconsumed received action is available, or `timeout` elapses.
    ///
    /// Feedback arrival is awaited deterministically rather than by spinning the scheduler:
    /// - Synchronous feedback (`.next`) is already appended to `receivedActions` by
    ///   `machine.send`'s recursive resolution, so the count check below returns immediately.
    /// - Asynchronous feedback wakes this method through `receivedActionSignal`, which fires
    ///   exactly when an effect-originated action is appended (see the `.receive` reducer branch).
    ///
    /// The `timeout` is a real-time failsafe for the "no feedback ever arrives" assertion failure,
    /// not part of the happy path; a delivered feedback returns as soon as its signal fires.
    private func waitForReceivedAction(
        timeout: Duration,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt
    ) async -> Bool
    {
        if await self.unconsumedReceivedActionsCount > 0 {
            return true
        }

        let didReceive = await self.waitForReceivedActionSignal(timeout: timeout)

        if !didReceive, await self.unconsumedReceivedActionsCount == 0 {
            XCTFail(
                """
                Expected to receive an action, but received none\(timeout > .zero ? " after \(timeout)" : "").

                  \(fileID):\(line)
                """,
                file: filePath,
                line: line
            )
            return false
        }

        return true
    }

    private func waitForReceivedActionSignal(
        timeout: Duration
    ) async -> Bool
    {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { [self] in
                while !Task.isCancelled {
                    guard await self.awaitReceivedActionSignal() else { return false }

                    if await self.unconsumedReceivedActionsCount > 0 {
                        return true
                    }
                }

                return false
            }

            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func awaitReceivedActionSignal() async -> Bool
    {
        var iterator = self.receivedActionSignal.makeAsyncIterator()
        let next: Void? = await iterator.next()
        return next != nil
    }

    private var unconsumedReceivedActionsCount: Int
    {
        get async {
            let runtimeState = self.machine.state
            return runtimeState.receivedActions.count - self.consumedReceivedActionCount
        }
    }

    private func nextReceivedAction() async
        -> (action: Action, stateBefore: State, stateAfter: State)?
    {
        let runtimeState = self.machine.state

        guard runtimeState.receivedActions.indices.contains(self.consumedReceivedActionCount) else { return nil }

        let receivedAction = runtimeState.receivedActions[self.consumedReceivedActionCount]
        self.consumedReceivedActionCount += 1
        return (
            action: receivedAction.action,
            stateBefore: receivedAction.stateBefore,
            stateAfter: receivedAction.stateAfter
        )
    }

    private func hasLaterReceivedAction(
        matching predicate: (Action) -> Bool
    ) async -> Bool
    {
        let runtimeState = self.machine.state

        return runtimeState.receivedActions
            .dropFirst(self.consumedReceivedActionCount)
            .contains(where: { predicate($0.action) })
    }

    private func assertStateChange(
        label: String,
        expected: State,
        actual: State,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        assert: ((_ state: inout State) -> Void)?
    )
    {
        var expected = expected
        assert?(&expected)

        if expected != actual {
            let diff = CustomDump.diff(expected, actual) ?? "(diff unavailable)"

            XCTFail(
                """
                State mismatch after \(label):

                  \(fileID):\(line)

                \(diff)
                """,
                file: filePath,
                line: line
            )
        }
    }
}

private enum TestActomatonAction<Action>: Sendable
    where Action: Sendable
{
    case send(Action)
    case receive(Action)

    var action: Action
    {
        switch self {
        case let .send(action), let .receive(action):
            return action
        }
    }
}

private struct TestActomatonRuntimeState<Action, State>
    where Action: Sendable
{
    var current: State
    var latestSentState: State?
    var receivedActions: [(action: Action, stateBefore: State, stateAfter: State)] = []

    init(
        current: State,
        latestSentState: State? = nil,
        receivedActions: [(action: Action, stateBefore: State, stateAfter: State)] = []
    )
    {
        self.current = current
        self.latestSentState = latestSentState
        self.receivedActions = receivedActions
    }
}
