import XCTest
@testable import Actomaton

import Combine

/// Tests for `EffectQueueProtocol` with `EffectQueuePolicy.runOldest(maxCount: n, .discardNew)`.
@MainActor
final class RunOldestDiscardNewTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    fileprivate var resultsCollector: ResultsCollector<Int> = .init()

    private func setupActomaton(maxCount: Int)
    {
        self.resultsCollector = ResultsCollector<Int>()

        struct OldestDiscardNewEffectQueue: EffectQueueProtocol
        {
            var maxCount: Int

            var effectQueuePolicy: EffectQueuePolicy
            {
                .runOldest(maxCount: maxCount, .discardNew)
            }
        }

        let actomaton = Actomaton<Action, State>(
            state: State(),
            reducer: Reducer { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1

                    return Effect(queue: OldestDiscardNewEffectQueue(maxCount: maxCount)) { [state] in
                        await tick(1)
                        if Task.isCancelled {
                            await self.resultsCollector.append(state.count)
                            Debug.print("Effect cancelled")
                            return nil
                        }
                        Debug.print("Effect success")
                        return .effectCompleted
                    }

                case .effectCompleted:
                    state.effectCompletedCount += 1
                    return .empty
                }
            }
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

        // 2nd `increment` (effect won't be executed because of `OldestDiscardNewEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 0))

        await tick(3)

        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 1),
                    "`effectCompletedCount` should increment by 1 (not 2) because of `OldestDiscardNewEffectQueue`")

        // 3rd `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 1))

        await tick(3)

        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 2))

        let results = await resultsCollector.results.sorted()
        XCTAssertEqual(results, [],
                       "Should be empty, because 2nd increment's effect is discarded without start nor cancellation.")
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

        // 3rd `increment` (effect won't be executed because of `OldestDiscardNewEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 0))

        await tick(4)

        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 2),
                    "`effectCompletedCount` will increment by 2 (not 3) because of `OldestDiscardNewEffectQueue`")

        // 4th `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 4, effectCompletedCount: 2))

        await tick(3)

        assertEqual(await actomaton.state, State(count: 4, effectCompletedCount: 3))

        let results = await resultsCollector.results.sorted()
        XCTAssertEqual(results, [],
                       "Should be empty, because 3nd increment's effect is discarded without start nor cancellation.")
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
