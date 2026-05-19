import ActomatonCore
import XCTest

/// Tests for `MealyMachine` with no feedback actions (`Output == [Action]` always empty).
final class MealyMachineNoOpTests: XCTestCase
{
    func test_counter() async
    {
        let machine = MealyMachine<CounterAction, Int, [CounterAction]>(
            state: 0,
            reducer: MealyReducer { action, state, _ in
                switch action {
                case .increment:
                    state += 1
                case .decrement:
                    state -= 1
                }
                return []
            }
        )

        var s = machine.state
        XCTAssertEqual(s, 0)

        machine.send(.increment)
        s = machine.state
        XCTAssertEqual(s, 1)

        machine.send(.increment)
        s = machine.state
        XCTAssertEqual(s, 2)

        machine.send(.decrement)
        s = machine.state
        XCTAssertEqual(s, 1)
    }

    func test_emptyOutput() async
    {
        let machine = MealyMachine<CounterAction, Int, [CounterAction]>(
            state: 0,
            reducer: MealyReducer { action, state, _ in
                switch action {
                case .increment:
                    state += 1
                case .decrement:
                    state -= 1
                }
                return []
            }
        )

        // `send(_:)` returns the asynchronous-remainder output, which here is always `[]`
        // because the reducer never produces synchronous feedback.
        let output = machine.send(.increment)
        XCTAssertEqual(output, [])
    }
}

// MARK: - Private

private enum CounterAction: Sendable
{
    case increment
    case decrement
}
