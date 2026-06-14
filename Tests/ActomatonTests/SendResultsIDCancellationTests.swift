import Actomaton
import XCTest

/// Tests for cancelling a whole `send` (its ``SendResults``) via a reducer-side `Effect.cancel(id:)`,
/// enabled by registering the `SendResults` through `send(id:)`.
///
/// The triggered effect itself carries **no** `id` here, so cancellation flows purely through the
/// `SendResults` registered under the `send`-level `id` → its supervisor → the underlying effect.
final class SendResultsIDCancellationTests: MainTestCase
{
    private var flags = Flags()

    private actor Flags
    {
        var isCancelled = false

        func markCancelled()
        {
            isCancelled = true
        }
    }

    override func setUp() async throws
    {
        flags = Flags()
    }

    /// `Effect.cancel(id:)` matching the `send`-id cancels the `SendResults` (like `SendResults.cancel()`).
    func test_effectCancel_cancelsSendResults() async throws
    {
        let actomaton = makeActomaton()

        let results = await actomaton.send(.start, id: TimerID())

        await clock.advance(by: .ticks(0.1))

        await actomaton.send(.stop) // -> Effect.cancel(id: TimerID())
        await results.completion()

        XCTAssertTrue(
            results.isCancelled,
            "`Effect.cancel(id:)` matching the registered send-id cancels the `SendResults`."
        )

        await clock.advance(by: .ticks(2))

        let isCancelled = await flags.isCancelled
        XCTAssertTrue(
            isCancelled,
            "Supervisor teardown cancels the underlying effect, so `ifCancelled` runs."
        )
        assertEqual(await actomaton.state.isFinished, false)
    }

    /// A non-matching `Effect.cancel(id:)` leaves the `SendResults` running to natural completion.
    func test_effectCancel_differentID_doesNotCancelSendResults() async throws
    {
        let actomaton = makeActomaton()

        let results = await actomaton.send(.start, id: TimerID())

        await clock.advance(by: .ticks(0.1))

        await actomaton.send(.stopOther) // -> Effect.cancel(id: OtherID())
        await settle()

        XCTAssertFalse(results.isCancelled, "A different id must not cancel this SendResults.")

        await clock.advance(by: .ticks(1))
        await results.completion()

        XCTAssertFalse(results.isCancelled)
        let isCancelled = await flags.isCancelled
        XCTAssertFalse(isCancelled)
        assertEqual(await actomaton.state.isFinished, true)
    }

    /// Multiple `send(id:)` sharing the same id are all cancelled together by one `Effect.cancel(id:)`.
    func test_effectCancel_cancelsAllSendResultsSharingID() async throws
    {
        let actomaton = makeActomaton()

        let first = await actomaton.send(.start, id: TimerID())
        let second = await actomaton.send(.start, id: TimerID())

        await clock.advance(by: .ticks(0.1))

        await actomaton.send(.stop)
        await first.completion()
        await second.completion()

        XCTAssertTrue(first.isCancelled)
        XCTAssertTrue(second.isCancelled)
    }

    /// With `tracksFeedbacks: true`, cancelling the registered send-id tears down the whole feedback
    /// chain — the same whole-chain semantics as `SendResults.cancel()`.
    func test_effectCancel_tracksFeedbacks_tearsDownWholeChain() async throws
    {
        let actomaton = makeActomaton()

        let results = await actomaton.send(.feedbackRoot, id: ChainID(), tracksFeedbacks: true)

        await clock.advance(by: .ticks(1.5))
        assertEqual(await actomaton.state.isChildStarted, true)

        await actomaton.send(.stopChain) // -> Effect.cancel(id: ChainID())
        await results.completion()

        XCTAssertTrue(results.isCancelled)

        await clock.advance(by: .ticks(2))
        assertEqual(await actomaton.state.isChainFinished, false)
    }

    private func makeActomaton() -> Actomaton<Action, State, Never>
    {
        Actomaton<Action, State, Never>(
            state: State(),
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case .start:
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .finished
                        } ifCancelled: {
                            await flags.markCancelled()
                            return nil
                        }
                    }

                case .finished:
                    state.isFinished = true
                    return .empty

                case .stop:
                    return Effect.cancel(id: TimerID())

                case .stopOther:
                    return Effect.cancel(id: OtherID())

                case .feedbackRoot:
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .feedbackChild
                        } ifCancelled: {
                            return nil
                        }
                    }

                case .feedbackChild:
                    state.isChildStarted = true
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .feedbackFinished
                        } ifCancelled: {
                            return nil
                        }
                    }

                case .feedbackFinished:
                    state.isChainFinished = true
                    return .empty

                case .stopChain:
                    return Effect.cancel(id: ChainID())
                }
            },
            effectContext: effectContext
        )
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case start
    case finished
    case stop
    case stopOther
    case feedbackRoot
    case feedbackChild
    case feedbackFinished
    case stopChain
}

private struct State: Equatable, Sendable
{
    var isFinished = false
    var isChildStarted = false
    var isChainFinished = false
}

private struct TimerID: EffectID {}
private struct OtherID: EffectID {}
private struct ChainID: EffectID {}
