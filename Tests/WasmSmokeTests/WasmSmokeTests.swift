import Actomaton
import ActomatonCore
import ActomatonDebugging
import ActomatonTesting
import Testing

@Test
func `mealy machine transitions on wasm`() async
{
    let reducer = MealyReducer<CounterAction, CounterState, Void, Void> { action, state, _ in
        switch action {
        case .increment:
            state.count += 1
        case .reset:
            state.count = 0
        }
    }

    let machine = MealyMachine(
        state: CounterState(),
        reducer: reducer,
        effectManager: NoOpEffectManager<CounterAction, CounterState>()
    )

    _ = await machine.send(.increment)

    #expect(await machine.state == CounterState(count: 1))
}

@Test
func `actomaton runs synchronous effects on wasm`() async
{
    let reducer = Reducer<CounterAction, CounterState, Void> { action, state, _ in
        switch action {
        case .increment:
            state.count += 1
            return .nextAction(.reset)
        case .reset:
            state.count = 0
            return .empty
        }
    }

    let actomaton = Actomaton(
        state: CounterState(),
        reducer: reducer
    )

    _ = await actomaton.send(.increment)

    #expect(await actomaton.state == CounterState())
}

@Test
func `auxiliary modules initialize on wasm`() async
{
    let format = LogFormat(name: "wasm", action: .simple, state: .simple)
    let timeout = TestTimeoutError(duration: .seconds(1))

    #expect(format == LogFormat(name: "wasm", action: .simple, state: .simple))
    #expect(timeout.duration == .seconds(1))
}

// MARK: - Private

private enum CounterAction: Sendable
{
    case increment
    case reset
}

private struct CounterState: Sendable, Equatable
{
    var count: Int = 0
}
