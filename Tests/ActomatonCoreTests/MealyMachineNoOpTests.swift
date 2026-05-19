import ActomatonCore
import XCTest

/// Tests for `MealyMachine` with `NoOpEffectManager` (pure state transitions, no feedback).
final class MealyMachineNoOpTests: XCTestCase
{
    func test_counter() async
    {
        let machine = MealyMachine<CounterAction, Int, Void>(
            state: 0,
            reducer: MealyReducer { action, state, _ in
                switch action {
                case .increment:
                    state += 1
                case .decrement:
                    state -= 1
                }
            }
        )
        machine.setUp(effectManager: NoOpEffectManager())

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

    func test_noTask() async
    {
        let machine = MealyMachine<CounterAction, Int, Void>(
            state: 0,
            reducer: MealyReducer { action, state, _ in
                switch action {
                case .increment:
                    state += 1
                case .decrement:
                    state -= 1
                }
            }
        )
        machine.setUp(effectManager: NoOpEffectManager())

        // send returns nil since NoOpEffectManager never produces tasks.
        let task = machine.send(.increment)
        XCTAssertNil(task)
    }
}

// MARK: - Private

private enum CounterAction: Sendable
{
    case increment
    case decrement
}
