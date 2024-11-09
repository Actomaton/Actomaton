import XCTest
@testable import Actomaton

final class CounterTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    override func setUp() async throws
    {
        let actomaton = Actomaton<Action, State>(
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
            }
        )
        self.actomaton = actomaton
    }

    func test_increment_decrement() async throws
    {
        assertEqual(await actomaton.state.count, 0)

        await actomaton.send(.increment)
        assertEqual(await actomaton.state.count, 1)

        await actomaton.send(.increment)
        assertEqual(await actomaton.state.count, 2)

        await actomaton.send(.decrement)
        assertEqual(await actomaton.state.count, 1)

        await actomaton.send(.decrement)
        assertEqual(await actomaton.state.count, 0)

        await actomaton.send(.decrement)
        assertEqual(await actomaton.state.count, -1)
    }
}

// MARK: - Private

private enum Action
{
    case increment
    case decrement
}

private struct State
{
    var count: Int = 0
}
