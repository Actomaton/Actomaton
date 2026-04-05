import ActomatonCore
import ActomatonEffect
import ActomatonTesting
import XCTest

final class TestMachineTests: XCTestCase
{
    // MARK: - Basic send + assertion

    func test_singleSend() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: counterReducer,
            environment: ()
        )

        await tm.send(.increment) { state in
            state.count = 1
        }
    }

    // MARK: - Chained sends with accumulating expectedState

    func test_chainedSends() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: counterReducer,
            environment: ()
        )

        await tm.send(.increment) { state in
            state.count = 1
        }

        await tm.send(.increment) { state in
            state.count = 2
        }

        await tm.send(.decrement) { state in
            state.count = 1
        }
    }

    // MARK: - No-assertion send (state unchanged)

    func test_noAssertionSend_stateUnchanged() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: counterReducer,
            environment: ()
        )

        // Reset when count is already 0 — state doesn't change, so no assertion needed.
        await tm.send(.reset)
    }

    // MARK: - Action feedback chain

    func test_actionFeedbackChain() async
    {
        let tm = TestMachine(
            state: ChainState(steps: []),
            reducer: MealyReducer<ChainAction, ChainState, Void, [ChainAction]> { action, state, _ in
                switch action {
                case .step1:
                    state.steps.append("step1")
                    return [.step2]
                case .step2:
                    state.steps.append("step2")
                    return [.step3]
                case .step3:
                    state.steps.append("step3")
                    return []
                }
            },
            environment: ()
        )

        // Single send triggers entire chain via ActionEffectManager.
        await tm.send(.step1) { state in
            state.steps = ["step1", "step2", "step3"]
        }
    }

    // MARK: - Effect-based reducer convenience init

    func test_effectBasedReducer() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction>> { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return .nextAction(.reset)
                case .decrement:
                    state.count -= 1
                    return .empty
                case .reset:
                    state.count = 0
                    return .empty
                }
            },
            environment: ()
        )

        // .increment triggers feedback .reset via .next extraction.
        await tm.send(.increment) { state in
            state.count = 0
        }
    }

    // MARK: - Multiple field changes

    func test_multipleFieldChanges() async
    {
        let tm = TestMachine(
            state: UserState(name: "", loggedIn: false),
            reducer: MealyReducer<UserAction, UserState, Void, [UserAction]> { action, state, _ in
                switch action {
                case let .login(name):
                    state.name = name
                    state.loggedIn = true
                    return []
                case .logout:
                    state.name = ""
                    state.loggedIn = false
                    return []
                }
            },
            environment: ()
        )

        await tm.send(.login(name: "alice")) { state in
            state.name = "alice"
            state.loggedIn = true
        }

        await tm.send(.logout) { state in
            state.name = ""
            state.loggedIn = false
        }
    }
}

// MARK: - Test Types

private struct CounterState: Equatable, Sendable
{
    var count: Int
}

private enum CounterAction: Sendable
{
    case increment
    case decrement
    case reset
}

private let counterReducer = MealyReducer<CounterAction, CounterState, Void, [CounterAction]> { action, state, _ in
    switch action {
    case .increment:
        state.count += 1
        return []
    case .decrement:
        state.count -= 1
        return []
    case .reset:
        state.count = 0
        return []
    }
}

private struct ChainState: Equatable, Sendable
{
    var steps: [String]
}

private enum ChainAction: Sendable
{
    case step1
    case step2
    case step3
}

private struct UserState: Equatable, Sendable
{
    var name: String
    var loggedIn: Bool
}

private enum UserAction: Sendable
{
    case login(name: String)
    case logout
}
