import ActomatonCore
import ActomatonEffect
import ActomatonTesting
import TestFixtures
import XCTest

final class TestMachineTests: MainTestCase
{
    func test_sendTask_finish_success() async throws
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction>> { action, state, _ in
                switch action {
                case .increment:
                    state.count = 1
                    return Effect.fireAndForget { context in
                        try await context.clock.sleep(for: .ticks(1))
                    }
                case .decrement:
                    state.count -= 1
                    return .empty
                case .reset:
                    state.count = 0
                    return .empty
                }
            },
            environment: (),
            effectContext: effectContext
        )

        let task = await tm.send(.increment) { state in
            state.count = 1
        }

        try await task.finish()
    }

    func test_sendTask_finish_timeout() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction>> { action, state, _ in
                switch action {
                case .increment:
                    state.count = 1
                    return Effect.fireAndForget { context in
                        try await context.clock.sleep(for: .ticks(20))
                    }
                case .decrement:
                    state.count -= 1
                    return .empty
                case .reset:
                    state.count = 0
                    return .empty
                }
            },
            environment: (),
            effectContext: effectContext
        )

        let task = await tm.send(.increment) { state in
            state.count = 1
        }

        let clock = ContinuousClock()
        let start = clock.now

        do {
            try await task.finish(timeout: .milliseconds(50))
            XCTFail("Expected timeout.")
        }
        catch is TestTimeoutError {
        }
        catch {
            XCTFail("Unexpected error: \(error)")
        }

        let elapsed = start.duration(to: clock.now)
        XCTAssertLessThan(elapsed, .seconds(0.5))
    }

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

    func test_sendFailsFastWhenReceivedActionIsUnhandled() async throws
    {
        let recorder = ResultsCollector<CounterAction>()

        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, ResultsCollector<CounterAction>, Effect<CounterAction>> {
                action, state, recorder in
                let recordEffect = Effect<CounterAction>.fireAndForget {
                    await recorder.append(action)
                }

                switch action {
                case .increment:
                    state.count += 1
                    return recordEffect + .nextAction(.reset)
                case .decrement:
                    state.count -= 1
                    return recordEffect
                case .reset:
                    state.count = 0
                    return recordEffect
                }
            },
            environment: recorder
        )

        let task = await tm.send(.increment) { state in
            state.count = 1
        }
        try await task.finish()

        XCTExpectFailure("`send` should fail before dispatching a new action when feedback remains unhandled.")
        _ = await tm.send(.decrement)

        let recordedActions = await recorder.results
        XCTAssertEqual(recordedActions, [.increment, .reset])
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
            reducer: chainReducer,
            environment: ()
        )

        await tm.send(.step1) { state in
            state.steps = ["step1"]
        }

        await tm.receive(.step2) { state in
            state.steps = ["step1", "step2"]
        }

        await tm.receive(.step3) { state in
            state.steps = ["step1", "step2", "step3"]
        }
    }

    // MARK: - Effect-based reducer convenience init

    func test_effectBasedReducer_asyncNextAction() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction>> { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return Effect {
                        .reset
                    }
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

        await tm.send(.increment) { state in
            state.count = 1
        }

        await tm.receive(.reset) { state in
            state.count = 0
        }
    }

    func test_effectBasedReducer_syncNextAction() async
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

        await tm.send(.increment) { state in
            state.count = 1
        }

        await tm.receive(.reset) { state in
            state.count = 0
        }
    }

    func test_asyncEffectReceive() async
    {
        let tm = TestMachine(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction>> { action, state, _ in
                switch action {
                case .increment:
                    state.count = 1
                    return Effect {
                        await Task.yield()
                        return .reset
                    }
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

        await tm.send(.increment) { state in
            state.count = 1
        }

        await tm.receive(.reset) { state in
            state.count = 0
        }
    }

    // MARK: - Multiple field changes

    func test_multipleFieldChanges() async
    {
        let tm = TestMachine(
            state: UserState(name: "", loggedIn: false),
            reducer: userReducer,
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

private enum CounterAction: Equatable, Sendable
{
    case increment
    case decrement
    case reset
}

private let counterReducer = MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction>> { action, state, _ in
    switch action {
    case .increment:
        state.count += 1
        return .empty
    case .decrement:
        state.count -= 1
        return .empty
    case .reset:
        state.count = 0
        return .empty
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

private let chainReducer = MealyReducer<ChainAction, ChainState, Void, Effect<ChainAction>> { action, state, _ in
    switch action {
    case .step1:
        state.steps.append("step1")
        return .nextAction(.step2)
    case .step2:
        state.steps.append("step2")
        return .nextAction(.step3)
    case .step3:
        state.steps.append("step3")
        return .empty
    }
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

private let userReducer = MealyReducer<UserAction, UserState, Void, Effect<UserAction>> { action, state, _ in
    switch action {
    case let .login(name):
        state.name = name
        state.loggedIn = true
        return .empty
    case .logout:
        state.name = ""
        state.loggedIn = false
        return .empty
    }
}
