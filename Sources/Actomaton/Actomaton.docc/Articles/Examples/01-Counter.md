# Example 1: Simple Counter 

Simple `increment` and `decrement` counter example.

## Overview

```swift
enum Action: Sendable {
    case increment
    case decrement
}

enum State: Sendable {
    var count: Int = 0
}

typealias Environment = Void

let reducer: Reducer<Action, State, Environment>
reducer = Reducer { action, state, environment in
    switch action {
    case .increment:
        state.count += 1
        return Effect.empty
    case .decrement:
        state.count -= 1
        return Effect.empty
    }
}

let actomaton = Actomaton<Action, State>(
    state: State(),
    reducer: reducer
)

@main
enum Main {
    static func main() async {
        assertEqual(await actomaton.state.count, 0)

        await actomaton.send(.increment)
        assertEqual(await actomaton.state.count, 1)

        await actomaton.send(.increment)
        assertEqual(await actomaton.state.count, 2)

        await actomaton.send(.decrement)
        assertEqual(await actomaton.state.count, 1)

        await actomaton.send(.decrement)
        assertEqual(await actomaton.state.count, 0)
    }
}
```

If you want to add some side-effects (e.g. console logging), add ``Effect`` in ``Reducer`` as follows:

```swift
reducer = Reducer { action, state, environment in
    switch action {
    case .increment:
        state.count += 1
        return Effect.fireAndForget {
            print("increment")
        }
    case .decrement:
        state.count -= 1
        return Effect.fireAndForget {
            print("decrement and sleep...")
            try await Task.sleep(...) // NOTE: We can use `await`!
            print("I'm awake!")
        }
    }
}
```

NOTE: There are 5 ways of creating ``Effect`` in Actomaton:

1. No side-effects, but forwards next action only
    - ``Effect/nextAction(_:)``
2. Single `async` without next action
    - ``Effect/fireAndForget(id:queue:run:)``
3. Single `async` with next action
    - ``Effect/init(id:queue:run:)``
4. Multiple `async`s (i.e. `AsyncSequence`) with next actions
    - ``Effect/init(id:queue:sequence:)``
5. Manual cancellation
    - ``Effect/cancel(id:)`` / ``Effect/cancel(ids:)``

## Next Step

<doc:02-LoginLogout>
