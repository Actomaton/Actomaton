import Actomaton
import TestFixtures
import XCTest

/// Regression tests for the interaction between `EffectQueue` bookkeeping and
/// `tracksFeedbacks` feedback chains.
///
/// Queue bookkeeping (slot release, `runNewest` eviction, `cancel(id:)`) must track an
/// effect's **own work** only, while `SendResult` keeps tracking the whole feedback
/// chain. When the two were conflated (one task = own work + descendant chain):
///
/// 1. `runNewest(maxCount: 1)`: dispatching the *next* effect of a recursive feedback
///    chain evicted the still-unwinding *ancestor* task, whose teardown cancelled the
///    live descendant — the chain killed itself.
/// 2. `runOldest(maxCount: n, .suspendNew)`: the ancestor held its queue slot while
///    awaiting descendants, so each feedback round leaked one slot and a recursive
///    chain deadlocked at capacity.
final class EffectQueueChainLifetimeTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<ChainAction, [ChainAction], Never>!

    // MARK: - runNewest(1): recursive feedback chain must not self-cancel

    func test_runNewest1_feedbackChain_doesNotSelfCancel() async throws
    {
        let firstEvicted = ResultsCollector<Bool>()

        let actomaton = Actomaton<ChainAction, [ChainAction], Never>(
            state: [],
            reducer: Reducer { action, state, _ in
                state.append(action)
                switch action {
                case .first:
                    // Stream effect that emits `.second` and then keeps its own work
                    // open, so the `.second` effect's dispatch genuinely evicts it
                    // from the `runNewest(1)` queue.
                    return .stream(queue: Newest1Queue()) { send, _ in
                        send(.second)
                        let (stream, _) = AsyncStream<Never>.makeStream()
                        for await _ in stream {} // ends on cancellation (eviction)
                        await firstEvicted.append(Task.isCancelled)
                    }

                case .second:
                    return Effect(queue: Newest1Queue()) { _ in
                        // Suspension window: with broken bookkeeping, the evicted
                        // ancestor's teardown cancels this descendant somewhere in
                        // these yields. Plain yields (not `context.clock.sleep`) keep
                        // the test independent of `TEST_CLOCK`'s `TestClock`, which
                        // nobody advances here — a clock sleep would hang CI.
                        for _ in 0 ..< 200 {
                            try Task.checkCancellation()
                            await Task.yield()
                        }
                        return .third
                    }

                case .third:
                    return .empty
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton

        let result = await actomaton.send(.first, tracksFeedbacks: true)
        await result.completion()

        assertEqual(
            await actomaton.state,
            [.first, .second, .third],
            "The recursive feedback chain must run to completion even though `.second`'s dispatch evicts `.first`'s own work from the runNewest(1) queue."
        )
        assertEqual(
            await firstEvicted.results,
            [true],
            "`.first`'s own work must have been evicted (cancelled) by `.second` entering the runNewest(1) queue — otherwise this test isn't exercising eviction."
        )
    }

    // MARK: - runOldest(1, suspendNew): recursive feedback chain must not leak the slot

    func test_runOldest1SuspendNew_feedbackChain_doesNotLeakQueueSlot() async throws
    {
        let actomaton = Actomaton<ChainAction, [ChainAction], Never>(
            state: [],
            reducer: Reducer { action, state, _ in
                state.append(action)
                switch action {
                case .first:
                    return Effect(queue: Oldest1Queue()) { _ in .second }
                case .second:
                    return Effect(queue: Oldest1Queue()) { _ in .third }
                case .third:
                    return .empty
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton

        let result = await actomaton.send(.first, tracksFeedbacks: true)

        let completed = await awaitWithTimeout(.seconds(3)) {
            await result.completion()
        }
        if !completed {
            result.cancel() // unwind the deadlocked chain so the test suite can proceed
        }

        XCTAssertTrue(
            completed,
            "`.first`'s queue slot must be released when its own work completes; holding it while awaiting the feedback chain deadlocks `.second` (suspended) against `.first` (awaiting `.second`)."
        )
        assertEqual(await actomaton.state, [.first, .second, .third])
    }

    // MARK: - SendResult.cancel(): whole-chain teardown must keep working

    func test_sendResultCancel_stillTearsDownDescendants() async throws
    {
        let descendantCancelled = ResultsCollector<Bool>()

        let actomaton = Actomaton<ChainAction, [ChainAction], String>(
            state: [],
            reducer: Reducer { action, state, _ in
                state.append(action)
                switch action {
                case .first:
                    return Effect { _ in .action(.second) }

                case .second:
                    return Effect.emit("descendant-started")
                        + Effect { _ in
                            let (stream, _) = AsyncStream<Never>.makeStream()
                            for await _ in stream {} // ends on cancellation
                            await descendantCancelled.append(Task.isCancelled)
                            return nil
                        }

                case .third:
                    return .empty
                }
            },
            effectContext: effectContext
        )

        let result = await actomaton.send(.first, tracksFeedbacks: true)

        for await element in result {
            if case .success("descendant-started") = element {
                // The descendant effect is in flight — cancel the whole chain.
                result.cancel()
            }
        }

        XCTAssertTrue(result.isCancelled)
        assertEqual(
            await descendantCancelled.results,
            [true],
            "`SendResult.cancel()` must still tear down feedback descendants (chain-task semantics are unchanged by the own-work split)."
        )
        assertEqual(await actomaton.state, [.first, .second])
    }
}

// MARK: - Private

private enum ChainAction: Sendable, Equatable
{
    case first
    case second
    case third
}

private struct Newest1Queue: Newest1EffectQueue {}
private struct Oldest1Queue: Oldest1SuspendNewEffectQueue {}

/// Awaits `operation`, returning `false` when `timeout` elapses first.
/// The passing path is event-driven; only the failing path waits out the timeout.
private func awaitWithTimeout(
    _ timeout: Duration,
    operation: @escaping @Sendable () async -> Void
) async -> Bool
{
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await operation()
            return true
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let finishedFirst = await group.next() ?? false
        group.cancelAll()
        return finishedFirst
    }
}
