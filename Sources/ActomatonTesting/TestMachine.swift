import ActomatonCore
import ActomatonEffect
import CustomDump
import XCTest

/// A testing utility that wraps `MealyMachine` + `EffectQueueManager` to provide
/// TCA-like `send` / `receive` assertions with readable diff output.
///
/// ```swift
/// let tm = TestMachine(
///     state: MyState(),
///     reducer: myReducer,
///     environment: ()
/// )
///
/// await tm.send(.increment) { state in
///     state.count = 1
/// }
///
/// await tm.receive(.didLoad) { state in
///     state.isLoading = false
/// }
/// ```
public actor TestMachine<Action, State, Environment>
    where Action: Sendable, State: Sendable & Equatable, Environment: Sendable
{
    private typealias InternalAction = TestMachineAction<Action>
    private typealias RuntimeState = TestMachineRuntimeState<Action, State>

    private let machine: MealyMachine<InternalAction, RuntimeState, Effect<InternalAction>>
    private let receivedActionSignal: AsyncStream<Void>
    private var consumedReceivedActionCount: Int = 0

    /// Creates a `TestMachine` from an `Effect`-based reducer.
    ///
    /// Unlike the original implementation, async effects are preserved and can be asserted with
    /// ``receive(_:timeout:assert:fileID:file:line:)``.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, Environment, Effect<Action>>,
        environment: Environment,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    )
    {
        let receivedActionSignal = AsyncStream.makeStream(of: Void.self)
        self.receivedActionSignal = receivedActionSignal.stream

        let reducer = MealyReducer<InternalAction, RuntimeState, (), Effect<InternalAction>> { action, state, _ in
            let stateBeforeAction = state.current
            let effect = reducer.run(action.action, &state.current, environment)
            let mappedEffect = effect.map(InternalAction.receive)

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

                return Effect.fireAndForget {
                    receivedActionSignal.continuation.yield()
                } + mappedEffect
            }
        }

        self.machine = MealyMachine(
            state: .init(current: state),
            reducer: reducer,
            effectManager: EffectQueueManager(effectContext: effectContext)
        )
    }

    /// Sends an action and asserts how state changes before any feedback action is received.
    ///
    /// Feedback actions emitted from `.next`, `async`, or `AsyncSequence` effects must be asserted
    /// separately via ``receive(_:timeout:assert:fileID:file:line:)``.
    /// If previously received feedback actions remain unhandled, this method fails immediately and
    /// does not dispatch `action`.
    ///
    /// Returns a ``TestMachineTask`` that can be used to await completion of the triggered effect
    /// chain or cancel it explicitly.
    @discardableResult
    public func send(
        _ action: Action,
        assert: ((_ state: inout State) -> Void)? = nil,
        timeout: Duration = .seconds(1),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        line: UInt = #line
    ) async -> TestMachineTask
    {
        let runtimeState = await self.machine.state

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

            return TestMachineTask(task: nil, timeout: timeout)
        }

        let expected = runtimeState.current

        let task = await self.machine.send(.send(action), tracksFeedbacks: true)

        guard let actual = (await self.machine.state).latestSentState else {
            XCTFail(
                """
                Internal error: failed to capture state after sending \(action).

                  \(fileID):\(line)
                """,
                file: filePath,
                line: line
            )
            return .init(task: task, timeout: timeout)
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

        await Self.drainImmediateFeedbacks()

        return .init(task: task, timeout: timeout)
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

extension TestMachine where Action: Equatable
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

extension TestMachine
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

        await Self.drainImmediateFeedbacks()
    }

    private func waitForReceivedAction(
        timeout: Duration,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt
    ) async -> Bool
    {
        await Self.drainImmediateFeedbacks()

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
            let runtimeState = await self.machine.state
            return runtimeState.receivedActions.count - self.consumedReceivedActionCount
        }
    }

    private func nextReceivedAction() async
        -> (action: Action, stateBefore: State, stateAfter: State)?
    {
        let runtimeState = await self.machine.state

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
        let runtimeState = await self.machine.state

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

    /// Gives the concurrency runtime a few turns to surface already-triggered feedback actions.
    ///
    /// This is intentionally a small race-avoidance shim for tests, not a way to wait for full
    /// effect completion. Time-based effects should still be driven explicitly by a test clock or
    /// by awaiting the task returned from `send`.
    private static func drainImmediateFeedbacks(count: Int = 20) async
    {
        for _ in 0 ..< count {
            await Task.yield()
        }
    }
}

private enum TestMachineAction<Action>: Sendable
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

private struct TestMachineRuntimeState<Action, State>: Sendable
    where Action: Sendable, State: Sendable
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
