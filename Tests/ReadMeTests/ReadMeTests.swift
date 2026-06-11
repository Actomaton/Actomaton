import Actomaton
import Foundation
import XCTest

/// Compile-only test for README.
private func readMe1_1_effectContext() async throws
{
    enum Action: Sendable {
        case start
        case finished
    }

    struct State: Sendable {
        var isRunning = false
    }

    let reducer = Reducer<Action, State, Void, Never> { action, state, _ in
        switch action {
        case .start:
            state.isRunning = true
            return Effect { context in
                try await context.clock.sleep(for: .seconds(1))
                return .finished
            }

        case .finished:
            state.isRunning = false
            return .empty
        }
    }

    let actomaton = Actomaton<Action, State, Never>(
        state: State(),
        reducer: reducer
    )

    _ = await actomaton.send(.start)
}

/// Compile-only test for README.
private func readMe1_4() async throws
{
    enum Action: Sendable {
        case fetch(id: String)
        case _didFetch(Data)
    }

    struct State: Sendable {} // no state

    struct Environment: Sendable {
        let fetch: @Sendable (_ id: String) async throws -> Data
    }

    struct DelayedEffectQueue: EffectQueue {
        // First 3 effects will run concurrently, and other sent effects will be suspended.
        var effectQueuePolicy: EffectQueuePolicy {
            .runOldest(maxCount: 3, .suspendNew)
        }

        // Adds delay between effect start. (This is useful for throttling / debouncing)
        var effectQueueDelay: EffectQueueDelay {
            .random(0.1 ... 0.3)
        }
    }

    let reducer = Reducer<Action, State, Environment, Never> { action, _, environment in
        switch action {
        case let .fetch(id):
            return Effect(queue: DelayedEffectQueue()) { _ in
                let data = try await environment.fetch(id)
                return ._didFetch(data)
            }
        case let ._didFetch(data):
            // Do something with `data`.
            print(data)
            return .empty
        }
    }

    let actomaton = Actomaton<Action, State, Never>(
        state: State(),
        reducer: reducer,
        environment: Environment(fetch: { _ in Data() /* ... */ })
    )

    await actomaton.send(.fetch(id: "item1"))
    await actomaton.send(.fetch(id: "item2")) // min delay of 0.1
    await actomaton.send(.fetch(id: "item3")) // min delay of 0.1 (after item2 actually starts)
    await actomaton.send(.fetch(id: "item4")) // starts when item1 or 2 or 3 finishes
}

/// Compile-only test for README. (Example 1-1. Simple Counter)
private func readMe1_1_counter() async
{
    struct State: Sendable {
        var count: Int = 0
    }

    enum Action: Sendable {
        case increment
        case decrement
    }

    typealias Environment = Void

    let reducer: Reducer<Action, State, Environment, Never>
    reducer = Reducer { action, state, _ in
        switch action {
        case .increment:
            state.count += 1
            return Effect.empty
        case .decrement:
            state.count -= 1
            return Effect.empty
        }
    }

    let actomaton = Actomaton<Action, State, Never>(
        state: State(),
        reducer: reducer
    )

    await actomaton.send(.increment)
    await actomaton.send(.decrement)
}

/// Compile-only test for README. (Example 1-2. Timer using `AsyncSequence`)
private func readMe1_2_timer() async
{
    typealias State = Int

    enum Action: Sendable {
        case start, tick, stop
    }

    struct TimerID: EffectID {}

    struct Environment: Sendable {
        let timer: @Sendable () -> AsyncStream<Void>
    }

    let environment = Environment(
        timer: {
            AsyncStream<Void> { continuation in
                let task = Task {
                    while true {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // README: /* 1 sec */
                        continuation.yield(())
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        }
    )

    let reducer = Reducer<Action, State, Environment, Never> { action, state, environment in
        switch action {
        case .start:
            return Effect.sequence(id: TimerID()) { _ in
                environment.timer()
                    .map { _ in Action.tick }
            }
        case .tick:
            state += 1
            return .empty
        case .stop:
            return Effect.cancel(id: TimerID())
        }
    }

    let actomaton = Actomaton<Action, State, Never>(
        state: 0,
        reducer: reducer,
        environment: environment
    )

    await actomaton.send(.start)
}

/// Compile-only test for README. (Example 1-3. Login-Logout — `EffectQueue`)
private func readMe1_3_loginLogout() async
{
    enum State: Sendable {
        case loggedOut, loggingIn, loggedIn, loggingOut
    }

    enum Action: Sendable {
        case login, loginOK, logout, logoutOK
        case forceLogout
    }

    struct LoginFlowEffectQueue: Newest1EffectQueue {}

    struct Environment: Sendable {
        let login: @Sendable (_ userId: String) async throws -> Void
        let logout: @Sendable () async throws -> Void
    }

    let environment = Environment(
        login: { _ in /* ... */ },
        logout: { /* ... */ }
    )

    let reducer = Reducer<Action, State, Environment, Never> { action, state, environment in
        switch (action, state) {
        case (.login, .loggedOut):
            state = .loggingIn
            return Effect(queue: LoginFlowEffectQueue()) { _ in
                try await environment.login("user-123")
                return Action.loginOK
            }

        case (.loginOK, .loggingIn):
            state = .loggedIn
            return .empty

        case (.logout, .loggedIn),
             (.forceLogout, .loggingIn),
             (.forceLogout, .loggedIn):
            state = .loggingOut
            return Effect(queue: LoginFlowEffectQueue()) { _ in
                try await environment.logout()
                return Action.logoutOK
            }

        case (.logoutOK, .loggingOut):
            state = .loggedOut
            return .empty

        default:
            return Effect.fireAndForget { _ in
                print("State transition failed...")
            }
        }
    }

    let actomaton = Actomaton<Action, State, Never>(
        state: .loggedOut,
        reducer: reducer,
        environment: environment
    )

    await actomaton.send(.login)
}
