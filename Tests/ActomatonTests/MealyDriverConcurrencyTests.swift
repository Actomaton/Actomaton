import Actomaton
import Foundation
import Synchronization
import XCTest

/// Concurrency test for ``MealyDriver``: synchronous `send` calls from many threads must not
/// race with each other or with the effect manager's unstructured cleanup tasks.
///
/// - Note:
///   This test case does NOT inherit `MainTestCase`, because `withMainSerialExecutor` would
///   serialize every task and hide the race. Run with `swift test --sanitize=thread` to catch
///   unsynchronized effect-manager bookkeeping (e.g. `runningTasks`).
final class MealyDriverConcurrencyTests: XCTestCase
{
    func test_concurrentSends_doNotRaceWithEffectCleanUp() async throws
    {
        let driver = MealyDriver<Action, State, Never>(
            state: State(),
            reducer: Reducer { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return Effect.fireAndForget { _ in }
                }
            }
        )

        let sendCount = 2000
        let sendResults = Mutex<[SendResults<Never>]>([])

        DispatchQueue.concurrentPerform(iterations: sendCount) { _ in
            let results = driver.send(.increment)
            sendResults.withLock { $0.append(results) }
        }

        for results in sendResults.withLock({ $0 }) {
            await results.completion
        }

        XCTAssertEqual(driver.state.count, sendCount)
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case increment
}

private struct State: Sendable
{
    var count: Int = 0
}
