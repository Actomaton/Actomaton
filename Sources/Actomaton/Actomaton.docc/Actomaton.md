# ``Actomaton``

Swift `async`/`await` & `Actor`-powered effectful state-management framework.
Linux ready.

## Overview

**Actomaton** is `Actor`-based **state-machine framework** inspired by [Elm](http://elm-lang.org/) and [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture).

- Repository: [https://github.com/Actomaton/Actomaton](https://github.com/Actomaton/Actomaton)

This module is the heart of all the other modules, which is not only for building UI architecture 
but for building "any" stateful and effectful computations in any platforms (including Linux).

All the business logic and its essential types will be defined by the developers under the following categories:

1. **Action**: `enum` message to be sent to ``Actomaton`` which triggers business logic (``Reducer``) to run
2. **State**: Representing data that is mutated by incoming `Action`s (e.g. for UI presentation) 
3. **``Reducer``**: Core business logic that receives `Action` as input, mutates `State`, and emits `Effect` as output using `Environment`
4. **Environment**: Collection of side-effectful entities that own external data sources and can be replaced 
with its mock for testing (This is the same as dependency injection (DI) container)
5. **``Effect``**: Side-effect that runs after state mutation
    1. Single-shot `async` function
    2. Multi-shot `AsyncStream`
    3. ``EffectID`` cancellation and ``EffectQueue`` Management

After these "blueprints" are created, ``Actomaton`` can be instantiated and run as follows:

```swift
let actomaton = Actomaton<Action, State>(
  state: State(),    // initial state
  reducer: reducer,  // business logic
  environment: environment  // dependency container 
)

await actomaton.send(Action.doSomething(parameters)) // message dispatch
```

To create more App-level complex structure and business logic, Actomaton provides an elegant **functional composition APIs**
such as **`map`** and **`contramap`** for all of the above categories to transform from small structure 
into a large one to combine them all.

To quickly jump into the example code, see Example Code page.

- <doc:Examples>

To play with real-world app using Actomaton, see SwiftUI / UIKit Gallery app below.

- [Actomaton-Gallery](https://github.com/Actomaton/Actomaton-Gallery)


## Topics

### Getting Started

- <doc:Examples>

### Esssentials

- ``Actomaton/Actomaton``
- ``Reducer``

### Effects

- ``Effect``
- ``EffectIDProtocol``
- ``EffectQueueProtocol``

### EffectQueuePolicy and built-ins

- ``EffectQueuePolicy``
- ``Newest1EffectQueueProtocol``
- ``Oldest1DiscardNewEffectQueueProtocol``
- ``Oldest1SuspendNewEffectQueueProtocol``

### EffectID/Queue Wrapper

- ``EffectID``
- ``EffectQueue``
