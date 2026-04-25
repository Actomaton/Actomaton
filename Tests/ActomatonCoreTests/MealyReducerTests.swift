import ActomatonCore
import XCTest

/// Tests for `MealyReducer` composition: contramap (action, state, environment) and map (output).
final class MealyReducerTests: XCTestCase
{
    func test_contramap_state() async
    {
        let innerReducer = MealyReducer<CounterAction, Int, (), Void> { action, state, _ in
            switch action {
            case .increment:
                state += 1
            case .decrement:
                state -= 1
            }
        }

        let outerReducer = innerReducer.contramap(state: \OuterCounterState.count)

        let machine = MealyMachine<CounterAction, OuterCounterState, Void>(
            state: OuterCounterState(name: "test", count: 10),
            reducer: outerReducer,
            effectManager: NoOpEffectManager()
        )

        await machine.send(.increment)
        let s = await machine.state
        XCTAssertEqual(s.count, 11)
        XCTAssertEqual(s.name, "test")
    }

    func test_contramap_action() async
    {
        let innerReducer = MealyReducer<CounterAction, Int, (), Void> { action, state, _ in
            switch action {
            case .increment:
                state += 1
            case .decrement:
                state -= 1
            }
        }

        let outerReducer = innerReducer.contramap(action: { (wrapper: WrapperAction) in
            wrapper.inner
        })

        let machine = MealyMachine<WrapperAction, Int, Void>(
            state: 0,
            reducer: outerReducer,
            effectManager: NoOpEffectManager()
        )

        await machine.send(WrapperAction(inner: .increment))
        var s = await machine.state
        XCTAssertEqual(s, 1)

        await machine.send(WrapperAction(inner: .decrement))
        s = await machine.state
        XCTAssertEqual(s, 0)
    }

    func test_contramap_environment() async
    {
        let reducer = MealyReducer<CounterAction, Int, Int, Void> { action, state, step in
            switch action {
            case .increment:
                state += step
            case .decrement:
                state -= step
            }
        }

        let adapted = reducer.contramap(environment: { (env: String) in
            Int(env) ?? 1
        })

        let machine = MealyMachine<CounterAction, Int, Void>(
            state: 0,
            reducer: MealyReducer { action, state, _ in
                adapted.run(action, &state, "5")
            },
            effectManager: NoOpEffectManager()
        )

        await machine.send(.increment)
        var s = await machine.state
        XCTAssertEqual(s, 5)

        await machine.send(.decrement)
        s = await machine.state
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

        let mapped = reducer.map(output: { "count=\($0)" })

        let machine = MealyMachine<CounterAction, Int, String>(
            state: 0,
            reducer: mapped,
            effectManager: StringEffectManager()
        )

        await machine.send(.increment)
        let s = await machine.state
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

/// Minimal effect manager for `String` output, used only in `test_map_output`.
private final class StringEffectManager<Action: Sendable, State>: EffectManager
{
    typealias Output = String

    init() {}

    func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, StringEffectManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {}

    func preprocessOutput(
        _ output: String,
        runReducer: (Action) -> String
    ) -> String
    {
        output
    }

    func processOutput(
        _ output: String,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?
    {
        nil
    }

    func shutDown() {}
}
