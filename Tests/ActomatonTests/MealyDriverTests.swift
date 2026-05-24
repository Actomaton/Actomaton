import Actomaton
import XCTest

/// Smoke test for ``MealyDriver`` — the non-actor counterpart of ``Actomaton``.
final class MealyDriverTests: MainTestCase
{
    fileprivate var driver: MealyDriver<Action, State>!

    override func setUp() async throws
    {
        let driver = MealyDriver<Action, State>(
            state: State(),
            reducer: Reducer { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return Effect.fireAndForget {
                        print("increment")
                    }
                case .decrement:
                    state.count -= 1
                    return Effect.fireAndForget {
                        print("decrement")
                    }
                }
            },
            effectContext: effectContext
        )
        self.driver = driver
    }

    func test_synchronous_send_and_state() throws
    {
        XCTAssertEqual(driver.state.count, 0)

        driver.send(.increment)
        XCTAssertEqual(driver.state.count, 1)

        driver.send(.increment)
        XCTAssertEqual(driver.state.count, 2)

        driver.send(.decrement)
        XCTAssertEqual(driver.state.count, 1)

        driver.send(.decrement)
        XCTAssertEqual(driver.state.count, 0)

        driver.send(.decrement)
        XCTAssertEqual(driver.state.count, -1)
    }

    func test_withState_reads_under_lock() throws
    {
        driver.send(.increment)
        driver.send(.increment)
        driver.send(.increment)

        let count = driver.withState { $0.count }
        XCTAssertEqual(count, 3)
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case increment
    case decrement
}

private struct State: Sendable
{
    var count: Int = 0
}
