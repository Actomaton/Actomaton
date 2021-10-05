import XCTest
@testable import Actomaton

import Combine

/// Tests for `Actomaton.deinit` to run successfully with cancelling running tasks.
final class DeinitTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    fileprivate var resultsCollector: ResultsCollector<Int> = .init()

    override func setUp() async throws
    {
        self.resultsCollector = ResultsCollector<Int>()

        let actomaton = Actomaton<Action, State>(
            state: State(),
            reducer: Reducer { [resultsCollector] action, state, _ in
                Debug.print("===> \(action)")
                state.count += 1

                return Effect { [state, resultsCollector] in
                    await tick(1)
                    if Task.isCancelled {
                        Debug.print("Effect cancelled")
                        await resultsCollector.append(state.count)
                        return nil
                    }
                    return .next
                }
            }
        )
        self.actomaton = actomaton
    }

    func test_deinit() async throws
    {
        weak var weakActomaton = self.actomaton

        let task = await actomaton.send(.next)
        await tick(2.5)

        self.actomaton = nil
        XCTAssertNil(weakActomaton, "`weakActomaton` should also become `nil`.")

        await task?.value

        let results = await resultsCollector.results
        XCTAssertEqual(
            results, [],
            """
            Will be empty because task cancellation won't normally take place.
            Instead, next task won't even get started because of `send` not working
            due to missing Actomaton.
            """
        )
    }
}

// MARK: - Private

private enum Action
{
    case next
}

private struct State
{
    var count: Int = 0

    init() {}
}
