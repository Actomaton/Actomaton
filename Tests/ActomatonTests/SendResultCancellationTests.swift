import Actomaton
import XCTest

/// Tests for `SendResult.cancel()` cascading into the actual effect tasks.
final class SendResultCancellationTests: MainTestCase
{
    private var flags = Flags()

    private actor Flags
    {
        var isTopLevelCancelled = false
        var isFeedbackRootCancelled = false
        var isFeedbackChildCancelled = false
        var isQueuedFirstCancelled = false
        var isQueuedSecondCancelled = false

        func mark(
            isTopLevelCancelled: Bool? = nil,
            isFeedbackRootCancelled: Bool? = nil,
            isFeedbackChildCancelled: Bool? = nil,
            isQueuedFirstCancelled: Bool? = nil,
            isQueuedSecondCancelled: Bool? = nil
        )
        {
            if let isTopLevelCancelled {
                self.isTopLevelCancelled = isTopLevelCancelled
            }
            if let isFeedbackRootCancelled {
                self.isFeedbackRootCancelled = isFeedbackRootCancelled
            }
            if let isFeedbackChildCancelled {
                self.isFeedbackChildCancelled = isFeedbackChildCancelled
            }
            if let isQueuedFirstCancelled {
                self.isQueuedFirstCancelled = isQueuedFirstCancelled
            }
            if let isQueuedSecondCancelled {
                self.isQueuedSecondCancelled = isQueuedSecondCancelled
            }
        }
    }

    override func setUp() async throws
    {
        flags = Flags()
    }

    func test_cancelStopsTopLevelEffect() async throws
    {
        let actomaton = makeActomaton()

        let result = await actomaton.send(.topLevel)

        await clock.advance(by: .ticks(0.1))
        result.cancel()
        await result.completion()

        await clock.advance(by: .ticks(2))

        let isTopLevelCancelled = await flags.isTopLevelCancelled
        XCTAssertTrue(isTopLevelCancelled)
        assertEqual(await actomaton.state.isTopLevelFinished, false)
    }

    func test_cancelStopsTrackedFeedbackEffect() async throws
    {
        let actomaton = makeActomaton()

        let result = await actomaton.send(.feedbackRoot, tracksFeedbacks: true)

        await clock.advance(by: .ticks(1.5))
        assertEqual(await actomaton.state.isFeedbackChildStarted, true)

        result.cancel()
        await result.completion()

        await clock.advance(by: .ticks(2))

        let isFeedbackRootCancelled = await flags.isFeedbackRootCancelled
        let isFeedbackChildCancelled = await flags.isFeedbackChildCancelled
        XCTAssertFalse(isFeedbackRootCancelled)
        XCTAssertTrue(isFeedbackChildCancelled)
        assertEqual(await actomaton.state.isFeedbackFinished, false)
    }

    func test_cancelDropsPendingEffect() async throws
    {
        let actomaton = makeActomaton()

        let firstResult = await actomaton.send(.queuedFirst)
        let secondResult = await actomaton.send(.queuedSecond)

        secondResult.cancel()
        await secondResult.completion()
        await settle()

        let isQueuedSecondCancelled = await flags.isQueuedSecondCancelled
        XCTAssertFalse(
            isQueuedSecondCancelled,
            "Second effect was still suspended (never started), so dropping it does not run `ifCancelled`."
        )

        await clock.advance(by: .ticks(2.5))
        await firstResult.completion()

        await clock.advance(by: .ticks(2))

        let isQueuedFirstCancelled = await flags.isQueuedFirstCancelled
        XCTAssertFalse(isQueuedFirstCancelled)
        assertEqual(await actomaton.state.isQueuedFirstFinished, true)
        assertEqual(await actomaton.state.isQueuedSecondFinished, false)
    }

    private func makeActomaton() -> Actomaton<Action, State, Never>
    {
        Actomaton<Action, State, Never>(
            state: State(),
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case .topLevel:
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .topLevelFinished
                        } ifCancelled: {
                            await flags.mark(isTopLevelCancelled: true)
                            return nil
                        }
                    }

                case .topLevelFinished:
                    state.isTopLevelFinished = true
                    return .empty

                case .feedbackRoot:
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .feedbackChild
                        } ifCancelled: {
                            await flags.mark(isFeedbackRootCancelled: true)
                            return nil
                        }
                    }

                case .feedbackChild:
                    state.isFeedbackChildStarted = true
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .feedbackFinished
                        } ifCancelled: {
                            await flags.mark(isFeedbackChildCancelled: true)
                            return nil
                        }
                    }

                case .feedbackFinished:
                    state.isFeedbackFinished = true
                    return .empty

                case .queuedFirst:
                    return Effect(queue: SuspendQueue()) { context in
                        try await context.clock.sleep(for: .ticks(2)) {
                            .queuedFirstFinished
                        } ifCancelled: {
                            await flags.mark(isQueuedFirstCancelled: true)
                            return nil
                        }
                    }

                case .queuedSecond:
                    return Effect(queue: SuspendQueue()) { context in
                        try await context.clock.sleep(for: .ticks(1)) {
                            .queuedSecondFinished
                        } ifCancelled: {
                            await flags.mark(isQueuedSecondCancelled: true)
                            return nil
                        }
                    }

                case .queuedFirstFinished:
                    state.isQueuedFirstFinished = true
                    return .empty

                case .queuedSecondFinished:
                    state.isQueuedSecondFinished = true
                    return .empty
                }
            },
            effectContext: effectContext
        )
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case topLevel
    case topLevelFinished
    case feedbackRoot
    case feedbackChild
    case feedbackFinished
    case queuedFirst
    case queuedSecond
    case queuedFirstFinished
    case queuedSecondFinished
}

private struct State: Equatable, Sendable
{
    var isTopLevelFinished = false
    var isFeedbackChildStarted = false
    var isFeedbackFinished = false
    var isQueuedFirstFinished = false
    var isQueuedSecondFinished = false
}

private struct SuspendQueue: EffectQueue, Hashable
{
    var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: 1, .suspendNew)
    }
}
