import ActomatonCore
import XCTest

/// Tests for `MealyReducer` composition: contramap (action, state, environment) and map (output).
final class MealyReducerTests: XCTestCase
{
    func test_contramap_state() async
    {
        let innerReducer = MealyReducer<CounterAction, Int, (), [CounterAction]> { action, state, _ in
            switch action {
            case .increment:
                state += 1
            case .decrement:
                state -= 1
            }
            return []
        }

        let outerReducer = innerReducer.contramap(state: \OuterCounterState.count)

        let machine = MealyMachine<CounterAction, OuterCounterState, [CounterAction]>(
            state: OuterCounterState(name: "test", count: 10),
            reducer: outerReducer
        )

        machine.send(.increment)
        let s = machine.state
        XCTAssertEqual(s.count, 11)
        XCTAssertEqual(s.name, "test")
    }

    func test_contramap_action() async
    {
        let innerReducer = MealyReducer<CounterAction, Int, (), [WrapperAction]> { action, state, _ in
            switch action {
            case .increment:
                state += 1
            case .decrement:
                state -= 1
            }
            return []
        }

        let outerReducer = innerReducer.contramap(action: { (wrapper: WrapperAction) in
            wrapper.inner
        })

        let machine = MealyMachine<WrapperAction, Int, [WrapperAction]>(
            state: 0,
            reducer: outerReducer
        )

        machine.send(WrapperAction(inner: .increment))
        var s = machine.state
        XCTAssertEqual(s, 1)

        machine.send(WrapperAction(inner: .decrement))
        s = machine.state
        XCTAssertEqual(s, 0)
    }

    func test_contramap_environment() async
    {
        let reducer = MealyReducer<CounterAction, Int, Int, [CounterAction]> { action, state, step in
            switch action {
            case .increment:
                state += step
            case .decrement:
                state -= step
            }
            return []
        }

        let adapted = reducer.contramap(environment: { (env: String) in
            Int(env) ?? 1
        })

        let machine = MealyMachine<CounterAction, Int, [CounterAction]>(
            state: 0,
            reducer: MealyReducer { action, state, _ in
                adapted.run(action, &state, "5")
            }
        )

        machine.send(.increment)
        var s = machine.state
        XCTAssertEqual(s, 5)

        machine.send(.decrement)
        s = machine.state
        XCTAssertEqual(s, 0)
    }

    func test_map_output() async
    {
        let reducer = MealyReducer<CounterAction, Int, (), Int> { action, state, _ in
            switch action {
            case .increment:
                state += 1
                return state
            case .decrement:
                state -= 1
                return state
            }
        }

        let mapped: MealyReducer<CounterAction, Int, (), [CounterAction]> =
            reducer.map(output: { _ in [] })

        let machine = MealyMachine<CounterAction, Int, [CounterAction]>(
            state: 0,
            reducer: mapped
        )

        machine.send(.increment)
        let s = machine.state
        XCTAssertEqual(s, 1)
    }
}

// MARK: - Private

private enum CounterAction: Sendable
{
    case increment
    case decrement
}

private struct OuterCounterState: Equatable, Sendable
{
    var name: String
    var count: Int
}

private struct WrapperAction: Sendable
{
    var inner: CounterAction
}
