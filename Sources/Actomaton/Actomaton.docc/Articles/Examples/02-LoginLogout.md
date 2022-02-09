# Example 2: Auth state

Auth screen (login, logout, and force-logout) example.

## Overview

This example illustrates Auth state management where `login`, `logout`, and `forceLogout` 
will trigger side-effects (such as API requests) then sends `loginOK` or `logoutOK` on completion.

![login-diagram](login-logout.png)

```swift
enum Action: Sendable {
    case login, loginOK, logout, logoutOK
    case forceLogout
}

enum State: Sendable {
    case loggedOut, loggingIn, loggedIn, loggingOut
}

// NOTE:
// By attaching this EffectQueue to multiple `Effect`s,
// they will incorporate with each other under the same `EffectQueuePolicy`,
// in this case: `Newest1EffectQueueProtocol`.
// 
// This policy will only allow at most newest 1 effect to survive,
// and rest of the queued running effects will be automatically cancelled.
struct LoginFlowEffectQueue: Newest1EffectQueueProtocol {}

struct Environment: Sendable {
    let loginEffect: @Sendable (userId: String) -> Effect<Action>
    let logoutEffect: Effect<Action>
}

let environment = Environment(
    loginEffect: { userId in
        Effect(queue: LoginFlowEffectQueue()) {
            let loginRequest = ...
            let data = try? await URLSession.shared.data(for: loginRequest)
            if Task.isCancelled { return nil }
            ...
            return Action.loginOK // next action
        }
    },
    logoutEffect: {
        Effect(queue: LoginFlowEffectQueue()) {
            let logoutRequest = ...
            let data = try? await URLSession.shared.data(for: logoutRequest)
            if Task.isCancelled { return nil }
            ...
            return Action.logoutOK // next action
        }
    }
)

let reducer = Reducer { action, state, environment in
    switch (action, state) {
    case (.login, .loggedOut):
        state = .loggingIn
        return environment.login(state.userId)

    case (.loginOK, .loggingIn):
        state = .loggedIn
        return .empty

    case (.logout, .loggedIn),
        (.forceLogout, .loggingIn),
        (.forceLogout, .loggedIn):
        state = .loggingOut
        return environment.logout()

    case (.logoutOK, .loggingOut):
        state = .loggedOut
        return .empty

    default:
        return Effect.fireAndForget {
            print("State transition failed...")
        }
    }
}

let actomaton = Actomaton<Action, State>(
    state: .loggedOut,
    reducer: reducer,
    environment: environment
)

@main
enum Main {
    static func test_login_logout() async {
        var t: Task<(), Error>?

        assertEqual(await actomaton.state, .loggedOut)

        t = await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedIn)

        t = await actomaton.send(.logout)
        assertEqual(await actomaton.state, .loggingOut)

        await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)

        XCTAssertFalse(isLoginCancelled)
    }

    static func test_login_forceLogout() async throws {
        var t: Task<(), Error>?

        assertEqual(await actomaton.state, .loggedOut)

        await actomaton.send(.login)
        assertEqual(await actomaton.state, .loggingIn)

        // Wait for a while and interrupt by `forceLogout`.
        // Login's effect will be automatically cancelled because of same `EffectQueue`.
        try await Task.sleep(/* 1 ms */)
        t = await actomaton.send(.forceLogout)

        assertEqual(await actomaton.state, .loggingOut)

        await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)
    }
}
```

Here we see the notions of `EffectQueue`, `Environment`, and `let task: Task<(), Error> = actomaton.send(...)`

- `EffectQueue` is for automatic cancellation or suspension of effects. 
  In this example, `Newest1EffectQueueProtocol` is used so that only the newest 1 effect (`forceLogout`) will survive,
  and rest of old queued effects (e.g. previous `login`) will be automatically cancelled.
- `Environment` is useful for injecting effects to be called inside `Reducer` so that they become replaceable. 
  **`Environment` is known as Dependency Injection Container** (using Reader monad).
- (Optional) `Task<(), Error>` returned from ``Actomaton/Actomaton/send(_:priority:tracksFeedbacks:)`` 
  is another fancy way of dealing with "all the effects triggered by `action`". 
  We can call `await task.value` to wait for all of them to be completed, 
  or `task.cancel()` to cancel all. Note that `Actomaton` already manages such `task`s for us internally, 
  so we normally don't need to handle them by ourselves (use this as a last resort!).

## Next Step

<doc:03-Timer>
