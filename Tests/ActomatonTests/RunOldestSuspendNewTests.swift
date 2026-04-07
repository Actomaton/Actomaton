@testable import Actomaton
import XCTest

#if !DISABLE_COMBINE && canImport(Combine)
import Combine
#endif

/// Tests for `EffectQueue` with `EffectQueuePolicy.runOldest(maxCount: n, .suspendNew)`.
final class RunOldestSuspendNewTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    fileprivate var resultsCollector: ResultsCollector<Int> = .init()

    private func setupActomaton(maxCount: Int)
    {
        self.resultsCollector = ResultsCollector<Int>()

        struct OldestSuspendNewEffectQueue: EffectQueue
        {
            var maxCount: Int

            var effectQueuePolicy: EffectQueuePolicy
            {
                .runOldest(maxCount: maxCount, .suspendNew)
            }
        }

        let actomaton = Actomaton<Action, State>(
            state: State(),
            reducer: Reducer { [resultsCollector] action, state, _ in
                switch action {
                case .increment:
                    state.count += 1

                    return Effect(queue: OldestSuspendNewEffectQueue(maxCount: maxCount)) { [state] context in
                        return try await context.clock.sleep(for: .ticks(1)) {
                            Debug.print("Effect success")
                            return .effectCompleted
                        } ifCancelled: {
                            await resultsCollector.append(state.count)
                            Debug.print("Effect cancelled")
                            return nil
                        }
                    }

                case .effectCompleted:
                    state.effectCompletedCount += 1
                    return .empty
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton
    }

    func test_maxCount1() async throws
    {
        setupActomaton(maxCount: 1)

        assertEqual(await actomaton.state, State(count: 0, effectCompletedCount: 0))

        // 1st `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 1, effectCompletedCount: 0))

        // 2nd `increment` (effect will start delayed because of `OldestSuspendNewEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 0))

        // Wait until 1st effect is finished.
        await clock.advance(by: .ticks(1.5))

        assertEqual(
            await actomaton.state,
            State(count: 2, effectCompletedCount: 1),
            "`effectCompletedCount` should increment by 1 because of `OldestSuspendNewEffectQueue`."
        )

        // Wait until 2nd effect is finished.
        await clock.advance(by: .ticks(1.5))

        assertEqual(
            await actomaton.state,
            State(count: 2, effectCompletedCount: 2),
            "`effectCompletedCount` should increment by 2 because of `OldestSuspendNewEffectQueue`."
        )

        // 3rd `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 2))

        await clock.advance(by: .ticks(1.5))

        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 3))

        let results = await resultsCollector.results.sorted()
        XCTAssertEqual(results, [], "Should be empty because no cancellation won't happen in this policy.")
    }

    func test_maxCount2() async throws
    {
        setupActomaton(maxCount: 2)

        assertEqual(await actomaton.state, State(count: 0, effectCompletedCount: 0))

        // 1st `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 1, effectCompletedCount: 0))

        // 2nd `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 0))

        // 3rd `increment` (effect will start delayed because of `OldestSuspendNewEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 0))

        // Wait until 1st & 2nd effect is finished.
        await clock.advance(by: .ticks(1.5))

        assertEqual(
            await actomaton.state,
            State(count: 3, effectCompletedCount: 2),
            "`effectCompletedCount` should increment by 2 because of `OldestSuspendNewEffectQueue`."
        )

        // Wait until 3rd effect is finished.
        await clock.advance(by: .ticks(1.5))

        assertEqual(
            await actomaton.state,
            State(count: 3, effectCompletedCount: 3),
            "`effectCompletedCount` should increment by 3 because of `OldestSuspendNewEffectQueue`."
        )

        // 4th `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 4, effectCompletedCount: 3))

        await clock.advance(by: .ticks(1.5))

        assertEqual(await actomaton.state, State(count: 4, effectCompletedCount: 4))

        let results = await resultsCollector.results.sorted()
        XCTAssertEqual(results, [], "Should be empty because no cancellation won't happen in this policy.")
    }
}

// MARK: - Private

private enum Action
{
    case increment
    case effectCompleted
}

private struct State: Equatable
{
    var count: Int = 0
    var effectCompletedCount: Int = 0
}
