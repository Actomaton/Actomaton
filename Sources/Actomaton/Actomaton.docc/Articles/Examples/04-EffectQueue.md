# Example 4: EffectQueue

``EffectQueue`` example.

## Overview

``EffectQueue`` provides an easy-to-use effect queueing management system in Actomaton which allows:

- Suspending newly arrived effects
- Discard old / new effects
- Delays next executing effect

For example:

```swift
enum Action: Sendable {
    case fetch(id: String)
    case _didFetch(Data)
}

struct State: Sendable {} // no state

struct Environment: Sendable {
    let fetch: @Sendable (_ id: String) async throws -> Data
}

struct DelayedEffectQueue: EffectQueueProtocol {
    // First 3 effects will run concurrently, and other sent effects will be suspended.
    var effectQueuePolicy: EffectQueuePolicy {
        .runOldest(maxCount: 3, .suspendNew)
    }

    // Adds delay between effect start. (This is useful for throttling / deboucing)
    var effectQueueDelay: EffectQueueDelay {
        .random(0.1 ... 0.3)
    }
}

let reducer = Reducer<Action, State, Environment> { action, state, environment in
    switch action {
    case let .fetch(id):
        return Effect(queue: DelayedEffectQueue()) {
            let data = try await environment.fetch(id)
            return ._didFetch(data)
        }
    case let ._didFetch(data):
        // Do something with `data`.
        return .empty
    }
}

let actomaton = Actomaton<Action, State>(
    state: State(),
    reducer: reducer,
        environment: Environment(fetch: { /* ... */ })
)

await actomaton.send(.fetch(id: "item1"))
await actomaton.send(.fetch(id: "item2")) // min delay of 0.1
await actomaton.send(.fetch(id: "item3")) // min delay of 0.1 (after item2 actually starts)
await actomaton.send(.fetch(id: "item4")) // starts when item1 or 2 or 3 finishes
```

Above code uses a custom `DelayedEffectQueue` that conforms to ``EffectQueueProtocol`` with suspendable ``EffectQueuePolicy`` and delays between each effect by ``EffectQueueDelay``.

See [EffectQueuePolicy](https://github.com/Actomaton/Actomaton/blob/main/Sources/Actomaton/EffectQueuePolicy.swift) for how each policy takes different queueing strategy for effects.

```swift
/// `EffectQueueProtocol`'s buffering policy.
public enum EffectQueuePolicy: Hashable, Sendable
{
    /// Runs `maxCount` newest effects, cancelling old running effects.
    case runNewest(maxCount: Int)

    /// Runs `maxCount` old effects with either suspending or discarding new effects.
    case runOldest(maxCount: Int, OverflowPolicy)

    public enum OverflowPolicy: Sendable
    {
        /// Suspends new effects when `.runOldest` `maxCount` of old effects is reached until one of them is completed.
        case suspendNew

        /// Discards new effects when `.runOldest` `maxCount` of old effects is reached until one of them is completed.
        case discardNew
    }
}
```

For convenient ``EffectQueueProtocol`` protocol conformance, there are built-in sub-protocols:

```swift
/// A helper protocol where `effectQueuePolicy` is set to `.runNewest(maxCount: 1)`.
public protocol Newest1EffectQueueProtocol: EffectQueueProtocol {}

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .discardNew)`.
public protocol Oldest1DiscardNewEffectQueueProtocol: EffectQueueProtocol {}

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .suspendNew)`.
public protocol Oldest1SuspendNewEffectQueueProtocol: EffectQueueProtocol {}
```

so that we can write in one-liner: `struct MyEffectQueue: Newest1EffectQueueProtocol {}`

## Next Step

<doc:05-ReducerComposition>
