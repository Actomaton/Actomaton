# Example 3: Timer 

`AsyncStream`-based timer example.

## Overview

In this example, ``Effect``.``Effect/init(id:sequence:)`` is used for timer effect, which yields `Action.tick` multiple times.

```swift
enum Action: Sendable {
    case start, tick, stop
}

typealias State = Int

struct TimerID: EffectIDProtocol {}

struct Environment: Sendable {
    let timerEffect: Effect<Action>
}

let environment = Environment(
    timerEffect: { userId in
        Effect(id: TimerID(), sequence: {
            AsyncStream<()> { continuation in
                let task = Task {
                    while true {
                        try await Task.sleep(/* 1 sec */)
                        continuation.yield(())
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        })
    }
)

let reducer = Reducer { action, state, environment in
    switch action {
    case .start:
        return environment.timerEffect
    case .tick:
        state += 1
        return .empty
    case .stop:
        return Effect.cancel(id: TimerID())
    }
}

let actomaton = Actomaton<Action, State>(
    state: 0,
    reducer: reducer,
    environment: environment
)

@main
enum Main {
    static func test_timer() async {
        assertEqual(await actomaton.state, 0)

        await actomaton.send(.start)

        assertEqual(await actomaton.state, 0)

        try await Task.sleep(/* 1 sec */)
        assertEqual(await actomaton.state, 1)

        try await Task.sleep(/* 1 sec */)
        assertEqual(await actomaton.state, 2)

        try await Task.sleep(/* 1 sec */)
        assertEqual(await actomaton.state, 3)

        await actomaton.send(.stop)

        try await Task.sleep(/* long enough */)
        assertEqual(await actomaton.state, 3,
                    "Should not increment because timer is stopped.")
    }
}
```

## Next Step

<doc:04-EffectQueue>
