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

struct DelayedEffectQueue: EffectQueue {
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

Above code uses a custom `DelayedEffectQueue` that conforms to ``EffectQueue`` with suspendable ``EffectQueuePolicy`` and delays between each effect by ``EffectQueueDelay``.

See [EffectQueuePolicy](https://github.com/Actomaton/Actomaton/blob/main/Sources/ActomatonEffect/EffectQueuePolicy.swift) for how each policy takes different queueing strategy for effects.

```swift
/// `EffectQueue`'s buffering policy.
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

For convenient ``EffectQueue`` protocol conformance, there are built-in sub-protocols:

```swift
/// A helper protocol where `effectQueuePolicy` is set to `.runNewest(maxCount: 1)`.
public protocol Newest1EffectQueue: EffectQueue {}

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .discardNew)`.
public protocol Oldest1DiscardNewEffectQueue: EffectQueue {}

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .suspendNew)`.
public protocol Oldest1SuspendNewEffectQueue: EffectQueue {}
```

so that we can write in one-liner: `struct MyEffectQueue: Newest1EffectQueue {}`

## Dynamic maxCount

Since ``EffectQueue`` conforms to `Hashable`, you can make `maxCount` dynamic at runtime by separating the queue's identity (hash/equality) from its policy values. The key insight is that `EffectQueueManager` looks up queued tasks by the queue's hash, but reads `maxCount` from the queue instance passed with each effect.

```swift
struct DynamicQueue: EffectQueue {
    var maxCount: Int

    var effectQueuePolicy: EffectQueuePolicy {
        .runNewest(maxCount: maxCount)
    }

    // Hash and equality ignore maxCount, so all instances
    // map to the same queue in EffectQueueManager.
    func hash(into hasher: inout Hasher) {
        hasher.combine("DynamicQueue")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}
```

Then use the current state to decide `maxCount` each time an effect is created:

```swift
enum Action: Sendable {
    case fetch(id: String)
    case updateMaxConcurrent(Int)
    case _didFetch(Data)
}

struct State: Sendable {
    var maxConcurrent: Int = 2
}

let reducer = Reducer<Action, State, Environment> { action, state, environment in
    switch action {
    case let .fetch(id):
        // maxCount is determined by the current state at send time.
        let queue = DynamicQueue(maxCount: state.maxConcurrent)
        return Effect(queue: queue) {
            let data = try await environment.fetch(id)
            return ._didFetch(data)
        }

    case let .updateMaxConcurrent(n):
        state.maxConcurrent = n
        return .empty

    case let ._didFetch(data):
        return .empty
    }
}
```

By sending `.updateMaxConcurrent(5)`, subsequent `.fetch` effects will use `maxCount: 5` while sharing the same underlying queue.

## Next Step

<doc:05-ReducerComposition>
