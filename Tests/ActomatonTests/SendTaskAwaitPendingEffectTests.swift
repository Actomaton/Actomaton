@testable import Actomaton
import XCTest

/// Tests that `send`'s returned Task tracks effects that were initially suspended
/// by a queue's `suspendNew` policy and later dequeued.
final class SendTaskAwaitPendingEffectTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    override func setUp() async throws
    {
        let actomaton = Actomaton<Action, State>(
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

    /// `send`'s returned Task should be non-nil for a suspended effect and should
    /// complete only after the effect is eventually dequeued and finishes.
    func test_sendTask_tracksPendingEffectCompletion() async throws
    {
        // maxConcurrent = 1.
        // A runs immediately, B gets suspended.
        let taskA = await actomaton.send(.fetch(id: "A"))
        let taskB = await actomaton.send(.fetch(id: "B"))

        XCTAssertNotNil(taskA, "Task for an immediately-running effect should be non-nil.")
        XCTAssertNotNil(taskB, "Task for a suspended effect should be non-nil (waitTask).")

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

        // Run clock advance and taskB await in parallel.
        // taskB is still waiting (B is running), and clock.advance triggers B's completion.
        // If the AsyncStream bridge is broken, taskB would never complete and this would hang.
        try await withThrowingTaskGroup(of: Void.self) { [clock] group in
            group.addTask {
                try await taskB?.value
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
