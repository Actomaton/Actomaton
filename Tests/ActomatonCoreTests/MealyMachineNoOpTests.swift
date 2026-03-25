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
            },
            effectManager: NoOpEffectManager()
        )

        var s = await machine.state
        XCTAssertEqual(s, 0)

        await machine.send(.increment)
        s = await machine.state
        XCTAssertEqual(s, 1)

        await machine.send(.increment)
        s = await machine.state
        XCTAssertEqual(s, 2)

        await machine.send(.decrement)
        s = await machine.state
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
            },
            effectManager: NoOpEffectManager()
        )

        // send returns nil since NoOpEffectManager never produces tasks.
        let task = await machine.send(.increment)
        XCTAssertNil(task)
    }
}

// MARK: - Private

private enum CounterAction: Sendable
{
    case increment
    case decrement
}
