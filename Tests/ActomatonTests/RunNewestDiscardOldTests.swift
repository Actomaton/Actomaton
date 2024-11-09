import XCTest
@testable import Actomaton

#if canImport(Combine)
import Combine
#endif

/// Tests for `EffectQueueProtocol` with `EffectQueuePolicy.runNewest(maxCount: n)`.
final class RunNewestDiscardOldTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    fileprivate var resultsCollector: ResultsCollector<Int> = .init()

    private func setupActomaton(maxCount: Int)
    {
        self.resultsCollector = ResultsCollector<Int>()

        struct NewestEffectQueue: EffectQueueProtocol
        {
            var maxCount: Int

            var effectQueuePolicy: EffectQueuePolicy
            {
                .runNewest(maxCount: maxCount)
            }
        }

        let actomaton = Actomaton<Action, State>(
            state: State(),
            reducer: Reducer { [resultsCollector] action, state, _ in
                switch action {
                case .increment:
                    state.count += 1

                    return Effect(queue: NewestEffectQueue(maxCount: maxCount)) { [state] in
                        try await tick(1) {
                            Debug.print("Effect success")
                            return .effectCompleted
                        } ifCancelled: { [resultsCollector] in
                            await resultsCollector.append(state.count)
                            Debug.print("Effect cancelled: \(state.count)")
                            return nil
                        }
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

        // 1st `increment` (effect will be auto-cancelled because of 2nd increment & `NewestEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 1, effectCompletedCount: 0))

        // 2nd `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 0))

        try await tick(3)

        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 1),
                    "`effectCompletedCount` should increment by 1 (not 2) because of `NewestEffectQueue`")

        // 3rd `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 1))

        try await tick(3)

        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 2))

        let results = await resultsCollector.results.sorted()
        XCTAssertEqual(results, [1], "1st increment should be cancelled.")
    }

    func test_maxCount2() async throws
    {
        setupActomaton(maxCount: 2)

        assertEqual(await actomaton.state, State(count: 0, effectCompletedCount: 0))

        // 1st `increment` (effect will be auto-cancelled because of 3rd increment & `NewestEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 1, effectCompletedCount: 0))

        // 2nd `increment` (effect will be auto-cancelled because of 4th increment & `NewestEffectQueue`).
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 2, effectCompletedCount: 0))

        // 3rd `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 3, effectCompletedCount: 0))

        // 4th `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 4, effectCompletedCount: 0))

        try await tick(5)

        assertEqual(await actomaton.state, State(count: 4, effectCompletedCount: 2),
                    "`effectCompletedCount` will increment by 2 because of `NewestEffectQueue`")

        // 4th `increment`.
        await actomaton.send(.increment)
        assertEqual(await actomaton.state, State(count: 5, effectCompletedCount: 2))

        try await tick(3)

        assertEqual(await actomaton.state, State(count: 5, effectCompletedCount: 3))

        let results = await resultsCollector.results.sorted()
        XCTAssertEqual(results, [1, 2], "1st & 2nd increment should be cancelled.")
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
