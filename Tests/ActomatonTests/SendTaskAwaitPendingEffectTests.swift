import Actomaton
import XCTest

/// Tests that `send`'s returned result tracks effects that were initially suspended
/// by a queue's `suspendNew` policy and later dequeued.
final class SendTaskAwaitPendingEffectTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State, Never>!

    override func setUp() async throws
    {
        let actomaton = Actomaton<Action, State, Never>(
            state: State(),
            reducer: Reducer { action, state, _ in
                switch action {
                case let .fetch(id):
                    state.fetchCount += 1

                    return Effect(queue: SuspendQueue()) { context in
                        try await context.clock.sleep(for: .ticks(3))
                        return .fetchCompleted(id: id)
                    }

                case .fetchCompleted:
                    state.completedCount += 1
                    return .empty
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton
    }

    /// `send`'s returned result should be non-nil for a suspended effect and should
    /// complete only after the effect is eventually dequeued and finishes.
    func test_sendTask_tracksPendingEffectCompletion() async throws
    {
        // maxConcurrent = 1.
        // A runs immediately, B gets suspended.
        let resultA = await actomaton.send(.fetch(id: "A"))
        let resultB = await actomaton.send(.fetch(id: "B"))

        XCTAssertNotNil(resultA, "Result for an immediately-running effect should be non-nil.")
        XCTAssertNotNil(resultB, "Result for a suspended effect should be non-nil.")

        assertEqual(
            await actomaton.state.completedCount, 0,
            "No effects should have completed yet."
        )

        // A completes at tick 3, B dequeues and starts running.
        await clock.advance(by: .ticks(3.5))

        assertEqual(
            await actomaton.state.completedCount, 1,
            "Only A should have completed. B just started."
        )

        // Run clock advance and resultB await in parallel.
        // resultB is still waiting (B is running), and clock.advance triggers B's completion.
        // If the AsyncStream bridge is broken, resultB would never complete and this would hang.
        try await withThrowingTaskGroup(of: Void.self) { [clock] group in
            group.addTask {
                await resultB.completion()
            }
            group.addTask {
                // B completes at tick 6.
                await clock.advance(by: .ticks(3.5))
            }
            try await group.waitForAll()
        }

        assertEqual(
            await actomaton.state.completedCount, 2,
            "Both A and B should have completed."
        )
    }

    func test_deinitFinishesDequeuedPendingEffectCompletion() async throws
    {
        var actomaton: Actomaton<Action, State, Never>? = self.actomaton
        self.actomaton = nil
        weak var weakActomaton = actomaton

        guard let resultA = await actomaton?.send(.fetch(id: "A")) else {
            return XCTFail("Result for an immediately-running effect should be non-nil.")
        }
        guard let resultB = await actomaton?.send(.fetch(id: "B")) else {
            return XCTFail("Result for a suspended effect should be non-nil.")
        }

        // A completes at tick 3, then B is dequeued and starts running.
        await clock.advance(by: .ticks(3.5))
        await resultA.completion()

        guard let completedCount = await actomaton?.state.completedCount else {
            return XCTFail("Actomaton should still be alive before explicit release.")
        }
        assertEqual(completedCount, 1)

        actomaton = nil
        XCTAssertNil(weakActomaton, "`weakActomaton` should also become `nil`.")
        weakActomaton = nil // For suppressing `WeakMutability` warning.

        try await awaitCompletionWithTimeout(resultB)
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case fetch(id: String)
    case fetchCompleted(id: String)
}

private struct State: Equatable, Sendable
{
    var fetchCount: Int = 0
    var completedCount: Int = 0
}

/// Queue with maxCount=1 and suspendNew policy.
private struct SuspendQueue: EffectQueue, Hashable
{
    var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: 1, .suspendNew)
    }
}

private struct CompletionTimeoutError: Error {}

private func awaitCompletionWithTimeout(
    _ results: SendResults<Never>,
    timeout: Duration = .milliseconds(500)
) async throws
{
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            await results.completion()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw CompletionTimeoutError()
        }

        defer { group.cancelAll() }
        _ = try await group.next()
    }
}
