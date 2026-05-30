import ActomatonCore
import ActomatonEffect
import ActomatonTesting
import TestFixtures
import XCTest

final class TestActomatonTests: MainTestCase
{
    func test_sendTask_finish_success() async throws
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction, Never>> { action, state, _ in
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

        let task = await testActomaton.send(.increment) { state in
            state.count = 1
        }

        // `finish()` waits for task completion, but does not drive `effectContext.clock`.
        // When `TEST_CLOCK=1`, advance the injected `TestClock` so the effect can complete.
        await clock.advance(by: .ticks(1))

        try await task.finish()
    }

    func test_sendTask_finish_timeout() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction, Never>> { action, state, _ in
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

        let task = await testActomaton.send(.increment) { state in
            state.count = 1
        }

        let clock = ContinuousClock()
        let start = clock.now

        do {
            try await task.finish(timeout: .milliseconds(50))
            XCTFail("Expected timeout.")
        }
        catch is TestTimeoutError {}
        catch {
            XCTFail("Unexpected error: \(error)")
        }

        let elapsed = start.duration(to: clock.now)
        XCTAssertLessThan(elapsed, .seconds(0.5))
    }

    func test_sendTask_finish_throwsEffectFailure() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction, Never>> { action, state, _ in
                switch action {
                case .increment:
                    state.count = 1
                    return Effect.fireAndForget { _ in
                        throw TestError()
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

        let task = await testActomaton.send(.increment) { state in
            state.count = 1
        }

        do {
            try await task.finish()
            XCTFail("Expected effect failure.")
        }
        catch let error as TestError {
            XCTAssertEqual(error, TestError())
        }
        catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Basic send + assertion

    func test_singleSend() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: counterReducer,
            environment: ()
        )

        await testActomaton.send(.increment) { state in
            state.count = 1
        }
    }

    // MARK: - Chained sends with accumulating expectedState

    func test_chainedSends() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: counterReducer,
            environment: ()
        )

        await testActomaton.send(.increment) { state in
            state.count = 1
        }

        await testActomaton.send(.increment) { state in
            state.count = 2
        }

        await testActomaton.send(.decrement) { state in
            state.count = 1
        }
    }

    func test_sendFailsFastWhenReceivedActionIsUnhandled() async throws
    {
#if os(Linux) || os(WASI)
        throw XCTSkip("`XCTExpectFailure` is unavailable on Linux and Wasm.")
#else
        let recorder = ResultsCollector<CounterAction>()

        typealias Reducer = MealyReducer<
            CounterAction,
            CounterState,
            ResultsCollector<CounterAction>,
            Effect<CounterAction, Never>
        >

        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: Reducer {
                action, state, recorder in
                let recordEffect = Effect<CounterAction, Never>.fireAndForget { _ in
                    await recorder.append(action)
                }

                switch action {
                case .increment:
                    state.count += 1
                    return recordEffect + .next(action: .reset)
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

        let task = await testActomaton.send(.increment) { state in
            state.count = 1
        }
        try await task.finish()

        XCTExpectFailure("`send` should fail before dispatching a new action when feedback remains unhandled.")
        _ = await testActomaton.send(.decrement)

        let recordedActions = await recorder.results
        XCTAssertEqual(recordedActions, [.increment, .reset])
#endif
    }

    // MARK: - No-assertion send (state unchanged)

    func test_noAssertionSend_stateUnchanged() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: counterReducer,
            environment: ()
        )

        // Reset when count is already 0 — state doesn't change, so no assertion needed.
        await testActomaton.send(.reset)
    }

    // MARK: - Action feedback chain

    func test_actionFeedbackChain() async
    {
        let testActomaton = TestActomaton(
            state: ChainState(steps: []),
            reducer: chainReducer,
            environment: ()
        )

        await testActomaton.send(.step1) { state in
            state.steps = ["step1"]
        }

        await testActomaton.receive(.step2) { state in
            state.steps = ["step1", "step2"]
        }

        await testActomaton.receive(.step3) { state in
            state.steps = ["step1", "step2", "step3"]
        }
    }

    // MARK: - Effect-based reducer convenience init

    func test_effectBasedReducer_asyncNextAction() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction, Never>> { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return Effect { _ in
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

        await testActomaton.send(.increment) { state in
            state.count = 1
        }

        await testActomaton.receive(.reset) { state in
            state.count = 0
        }
    }

    func test_effectBasedReducer_syncNextAction() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction, Never>> { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return .next(action: .reset)
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

        await testActomaton.send(.increment) { state in
            state.count = 1
        }

        await testActomaton.receive(.reset) { state in
            state.count = 0
        }
    }

    func test_acceptsNonNeverEmissionReducer() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<
                CounterAction, CounterState, Void, Effect<CounterAction, String>
            > { action, state, _ in
                switch action {
                case .increment:
                    state.count += 1
                    return .emit("incremented") + .next(action: .reset)
                case .decrement:
                    state.count -= 1
                    return .emit("decremented")
                case .reset:
                    state.count = 0
                    return .emit("reset")
                }
            },
            environment: ()
        )

        await testActomaton.send(.increment) { state in
            state.count = 1
        }

        await testActomaton.receive(.reset) { state in
            state.count = 0
        }
    }

    func test_asyncEffectReceive() async
    {
        let testActomaton = TestActomaton(
            state: CounterState(count: 0),
            reducer: MealyReducer<CounterAction, CounterState, Void, Effect<CounterAction, Never>> { action, state, _ in
                switch action {
                case .increment:
                    state.count = 1
                    return Effect { _ in
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

        await testActomaton.send(.increment) { state in
            state.count = 1
        }

        await testActomaton.receive(.reset) { state in
            state.count = 0
        }
    }

    // MARK: - Multiple field changes

    func test_multipleFieldChanges() async
    {
        let testActomaton = TestActomaton(
            state: UserState(name: "", loggedIn: false),
            reducer: userReducer,
            environment: ()
        )

        await testActomaton.send(.login(name: "alice")) { state in
            state.name = "alice"
            state.loggedIn = true
        }

        await testActomaton.send(.logout) { state in
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

private struct TestError: Error, Equatable {}

private let counterReducer = MealyReducer<
    CounterAction, CounterState, Void, Effect<CounterAction, Never>
> { action, state, _ in
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

private let chainReducer = MealyReducer<ChainAction, ChainState, Void, Effect<ChainAction, Never>> { action, state, _ in
    switch action {
    case .step1:
        state.steps.append("step1")
        return .next(action: .step2)
    case .step2:
        state.steps.append("step2")
        return .next(action: .step3)
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

private let userReducer = MealyReducer<UserAction, UserState, Void, Effect<UserAction, Never>> { action, state, _ in
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
