import XCTest
@testable import Actomaton

#if USE_COMBINE && canImport(Combine)
import Combine
#endif

@MainActor
@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
final class MainActomatonCounterTests: MainTestCase
{
    fileprivate var actomaton: MainActomaton2<Action, State>!

    override func setUp() async throws
    {
        let actomaton = MainActomaton2<Action, State>(
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
        assertEqual(actomaton.state.count, 0)

        actomaton.send(.increment)
        assertEqual(actomaton.state.count, 1)

        actomaton.send(.increment)
        assertEqual(actomaton.state.count, 2)

        actomaton.send(.decrement)
        assertEqual(actomaton.state.count, 1)

        actomaton.send(.decrement)
        assertEqual(actomaton.state.count, 0)

        actomaton.send(.decrement)
        assertEqual(actomaton.state.count, -1)
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
