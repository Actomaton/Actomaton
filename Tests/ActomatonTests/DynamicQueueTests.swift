@testable import Actomaton
import XCTest

#if !DISABLE_COMBINE && canImport(Combine)
import Combine
#endif

/// Tests for dynamic `EffectQueue` where `maxCount` changes at runtime.
final class DynamicQueueTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    fileprivate var resultsCollector: ResultsCollector<String> = .init()

    override func setUp() async throws
    {
        self.resultsCollector = ResultsCollector<String>()

        let actomaton = Actomaton<Action, State>(
            state: State(),
            reducer: Reducer { [resultsCollector] action, state, _ in
                switch action {
                case let .fetch(id):
                    state.fetchCount += 1

                    let queue = DynamicSuspendQueue(maxCount: state.maxConcurrent)
                    return Effect(queue: queue) { context in
                        return try await context.clock.sleep(for: .ticks(3)) {
                            Debug.print("Effect \(id) success")
                            await resultsCollector.append("completed:\(id)")
                            return .effectCompleted
                        } ifCancelled: {
                            Debug.print("Effect \(id) cancelled")
                            await resultsCollector.append("cancelled:\(id)")
                            return nil
                        }
                    }

                case let .updateMaxConcurrent(n):
                    state.maxConcurrent = n
                    return .empty

                case let .updateMaxConcurrentWithQueue(n):
                    state.maxConcurrent = n
                    return .updateQueue(DynamicSuspendQueue(maxCount: n))

                case .effectCompleted:
                    state.effectCompletedCount += 1
                    return .empty
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton
    }

    // MARK: - Tests for latestQueue fix (dequeue uses latest maxCount)

    /// When maxCount increases and a running task completes, pending effects should
    /// be dequeued up to the new capacity (not just one-at-a-time).
    func test_dynamicMaxCount_increaseViaNewEffect() async throws
    {
        assertEqual(await actomaton.state, State())

        // Start with maxConcurrent = 1.
        // Send 4 fetches: 1 runs, 3 are pending.
        await actomaton.send(.fetch(id: "A"))
        await actomaton.send(.fetch(id: "B"))
        await actomaton.send(.fetch(id: "C"))
        await actomaton.send(.fetch(id: "D"))

        assertEqual(await actomaton.state.fetchCount, 4)
        assertEqual(await actomaton.state.effectCompletedCount, 0)

        // Increase maxConcurrent to 4.
        // Then send a new fetch so that `checkQueuePolicy` updates `latestQueue`.
        await actomaton.send(.updateMaxConcurrent(4))
        await actomaton.send(.fetch(id: "E"))
        assertEqual(await actomaton.state.fetchCount, 5)

        // Let effect A complete. With maxCount now 4, pending B, C, D should all dequeue.
        await clock.advance(by: .ticks(3.5))

        // A completed + B, C, D dequeued and started.
        // E also started (was under capacity when sent).
        let completedCount1 = await actomaton.state.effectCompletedCount
        XCTAssertGreaterThanOrEqual(
            completedCount1, 1,
            "At least A should have completed."
        )

        // Let all remaining effects complete.
        await clock.advance(by: .ticks(7))

        assertEqual(
            await actomaton.state.effectCompletedCount, 5,
            "All 5 effects should have completed."
        )

        let results = await resultsCollector.results
        let completedResults = results.filter { $0.hasPrefix("completed:") }.sorted()
        XCTAssertEqual(
            completedResults,
            ["completed:A", "completed:B", "completed:C", "completed:D", "completed:E"]
        )
    }

    // MARK: - Tests for .updateQueue (no new effect needed)

    /// `.updateQueue` should re-evaluate pending effects and dequeue them immediately
    /// without requiring a new effect to be sent.
    func test_updateQueue_dequeuePendingImmediately() async throws
    {
        // Start with maxConcurrent = 1.
        // Send 3 fetches: 1 runs, 2 are pending.
        await actomaton.send(.fetch(id: "A"))
        await actomaton.send(.fetch(id: "B"))
        await actomaton.send(.fetch(id: "C"))

        assertEqual(await actomaton.state.fetchCount, 3)
        assertEqual(await actomaton.state.effectCompletedCount, 0)

        // Increase maxConcurrent to 3 via `.updateQueue`.
        // This should immediately dequeue B and C (no need to wait for A to complete).
        await actomaton.send(.updateMaxConcurrentWithQueue(3))

        // Now A, B, C should all be running. Let them complete.
        await clock.advance(by: .ticks(3.5))

        assertEqual(
            await actomaton.state.effectCompletedCount, 3,
            "All 3 effects should have completed because `.updateQueue` dequeued pending effects."
        )

        let results = await resultsCollector.results
        let completedResults = results.filter { $0.hasPrefix("completed:") }.sorted()
        XCTAssertEqual(
            completedResults,
            ["completed:A", "completed:B", "completed:C"]
        )
    }

    /// `.updateQueue` with no capacity change should not dequeue extra effects.
    func test_updateQueue_sameMaxCount_noChange() async throws
    {
        // maxConcurrent = 1 (default).
        await actomaton.send(.fetch(id: "A"))
        await actomaton.send(.fetch(id: "B"))

        // Send updateQueue with same maxCount.
        await actomaton.send(.updateMaxConcurrentWithQueue(1))

        // Only A should be running. B is still pending.
        assertEqual(await actomaton.state.effectCompletedCount, 0)

        // Let A complete → B dequeues.
        await clock.advance(by: .ticks(3.5))

        assertEqual(await actomaton.state.effectCompletedCount, 1, "Only A should have completed.")

        // Let B complete.
        await clock.advance(by: .ticks(3.5))

        assertEqual(await actomaton.state.effectCompletedCount, 2, "Both A and B should have completed.")
    }

    /// Without `.updateQueue`, increasing maxConcurrent via state alone should NOT
    /// dequeue pending effects until a new effect or task completion triggers it.
    func test_withoutUpdateQueue_pendingEffectsStayPending() async throws
    {
        // maxConcurrent = 1 (default).
        await actomaton.send(.fetch(id: "A"))
        await actomaton.send(.fetch(id: "B"))
        await actomaton.send(.fetch(id: "C"))

        // Increase maxConcurrent but do NOT send `.updateQueue`.
        await actomaton.send(.updateMaxConcurrent(3))

        // B, C are still pending because no re-evaluation was triggered.
        assertEqual(await actomaton.state.effectCompletedCount, 0)

        // Let A complete → dequeue uses latestQueue from last `checkQueuePolicy`.
        // Since no new effect updated latestQueue after maxConcurrent changed,
        // only 1 pending effect dequeues (old maxCount=1 in latestQueue).
        await clock.advance(by: .ticks(3.5))

        assertEqual(
            await actomaton.state.effectCompletedCount, 1,
            "Only A completed. Without `.updateQueue`, latestQueue still has old maxCount."
        )

        // Let B complete → C dequeues.
        await clock.advance(by: .ticks(3.5))

        assertEqual(await actomaton.state.effectCompletedCount, 2)

        // Let C complete.
        await clock.advance(by: .ticks(3.5))

        assertEqual(await actomaton.state.effectCompletedCount, 3)
    }

    /// Decrease maxConcurrent via `.updateQueue` should not affect already-running tasks,
    /// but should prevent excess pending effects from being dequeued.
    func test_updateQueue_decreaseMaxCount() async throws
    {
        // Start with maxConcurrent = 3.
        await actomaton.send(.updateMaxConcurrentWithQueue(3))

        // Send 5 fetches: 3 run, 2 are pending.
        await actomaton.send(.fetch(id: "A"))
        await actomaton.send(.fetch(id: "B"))
        await actomaton.send(.fetch(id: "C"))
        await actomaton.send(.fetch(id: "D"))
        await actomaton.send(.fetch(id: "E"))

        assertEqual(await actomaton.state.fetchCount, 5)

        // Decrease maxConcurrent to 1. Already running A, B, C are not cancelled.
        await actomaton.send(.updateMaxConcurrentWithQueue(1))

        // Let A, B, C complete.
        await clock.advance(by: .ticks(3.5))

        assertEqual(
            await actomaton.state.effectCompletedCount, 3,
            "A, B, C should have completed."
        )

        // After 3 completions with maxCount=1, only 1 pending should dequeue at a time.
        // D should now be running.

        // Let D complete → E dequeues.
        await clock.advance(by: .ticks(3.5))

        assertEqual(await actomaton.state.effectCompletedCount, 4)

        // Let E complete.
        await clock.advance(by: .ticks(3.5))

        assertEqual(await actomaton.state.effectCompletedCount, 5)
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case fetch(id: String)
    case updateMaxConcurrent(Int)
    case updateMaxConcurrentWithQueue(Int)
    case effectCompleted
}

private struct State: Equatable, Sendable
{
    var fetchCount: Int = 0
    var maxConcurrent: Int = 1
    var effectCompletedCount: Int = 0
}

/// Dynamic queue where `maxCount` can change at runtime.
/// Hash and equality ignore `maxCount` so all instances map to the same queue in EffectManager.
private struct DynamicSuspendQueue: EffectQueue
{
    var maxCount: Int

    var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: maxCount, .suspendNew)
    }

    func hash(into hasher: inout Hasher)
    {
        hasher.combine("DynamicSuspendQueue")
    }

    static func == (lhs: Self, rhs: Self) -> Bool
    {
        true
    }
}
