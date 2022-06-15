import XCTest
@testable import Actomaton

import Combine

/// Tests for `Actomaton.deinit` to run successfully with cancelling running tasks.
final class DeinitTests: XCTestCase
{
    func test_deinit() async throws
    {
        let resultsCollector = ResultsCollector<String>()

        var actomaton: Actomaton? = Actomaton<Action, State>(
            state: State(),
            reducer: Reducer { [resultsCollector] action, state, _ in
                switch action {
                case .run:
                    return Effect { [resultsCollector] in
                        return try await tick(5) {
                            await resultsCollector.append("Effect succeeded")
                            return nil
                        } ifCancelled: {
                            Debug.print("Effect cancelled")
                            await resultsCollector.append("Effect cancelled")
                            return nil
                        }
                    }
                }
            },
            environment: Environment(resultsCollector: resultsCollector)
        )

        weak var weakActomaton = actomaton

        let task = await actomaton?.send(.run)
        try await tick(1)

        // Deinit `actomaton`.
        actomaton = nil
        XCTAssertNil(weakActomaton, "`weakActomaton` should also become `nil`.")

        // Wait until deinit fully completes.
        try? await task?.value

        // Check results.
        //
        // NOTE:
        // Arrival timing of 2 results are almost simultaneous thus isn't guaranteed in order,
        // so will use `Set` here.
        let results = await resultsCollector.results
        XCTAssertEqual(
            Set(results), ["Effect cancelled", "DeinitChecker deinit"],
            "Running effect should be cancelled, and `DeinitChecker` should deinit."
        )
    }
}

// MARK: - Private

private enum Action
{
    case run
}

private struct State
{
    init() {}
}

private struct Environment: Sendable
{
    let deinitChecker: DeinitChecker

    init(resultsCollector: ResultsCollector<String>)
    {
        self.deinitChecker = DeinitChecker(resultsCollector: resultsCollector)
    }
}

private actor DeinitChecker
{
    let resultsCollector: ResultsCollector<String>

    init(resultsCollector: ResultsCollector<String>)
    {
        self.resultsCollector = resultsCollector
    }

    deinit
    {
        Task { [resultsCollector] in
            await resultsCollector.append("DeinitChecker deinit")
        }
    }
}
