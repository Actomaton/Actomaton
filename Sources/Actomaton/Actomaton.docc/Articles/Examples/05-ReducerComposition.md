# Example 5: Making a large app (Reducer Composition)

Reducer composition example.

## Overview

 [Actomaton-Gallery](https://github.com/Actomaton/Actomaton-Gallery) provides a good example of how `Reducer`s can be combined together into one big Reducer using `Reducer.combine`.

In this example, [swift-case-paths](https://github.com/pointfreeco/swift-case-paths) is used as a counterpart of `WritableKeyPath`, so if we use both, we can easily construct Mega-Reducer without a hussle.

(NOTE: `CasePath` is useful when dealing with enums, e.g. `enum Action` and `enum Current` in this example)

```swift
enum Root {} // just a namespace

extension Root {
    enum Action {
        case changeCurrent(State.Current?)

        case counter(Counter.Action)
        case stopwatch(Stopwatch.Action)
        case stateDiagram(StateDiagram.Action)
        case todo(Todo.Action)
        case github(GitHub.Action)
    }

    struct State: Equatable {
        var current: Current?

        // Current screen (NOTE: enum, so only 1 screen will appear)
        enum Current: Equatable {
            case counter(Counter.State)
            case stopwatch(Stopwatch.State)
            case stateDiagram(StateDiagram.State)
            case todo(Todo.State)
            case github(GitHub.State)
        }
    }

    // NOTE: `contramap` is also called `pullback` in swift-composable-architecture.
    static var reducer: Reducer<Action, State, Environment> {
        Reducer.combine(
            Counter.reducer
                .contramap(action: /Action.counter)
                .contramap(state: /State.Current.counter)
                .contramap(state: \State.current)
                .contramap(environment: { _ in () }),

            Todo.reducer
                .contramap(action: /Action.todo)
                .contramap(state: /State.Current.todo)
                .contramap(state: \State.current)
                .contramap(environment: { _ in () }),

            StateDiagram.reducer
                .contramap(action: /Action.stateDiagram)
                .contramap(state: /State.Current.stateDiagram)
                .contramap(state: \State.current)
                .contramap(environment: { _ in () }),

            Stopwatch.reducer
                .contramap(action: /Action.stopwatch)
                .contramap(state: /State.Current.stopwatch)
                .contramap(state: \State.current)
                .contramap(environment: { $0.stopwatch }),

            GitHub.reducer
                .contramap(action: /Action.github)
                .contramap(state: /State.Current.github)
                .contramap(state: \State.current)
                .contramap(environment: { $0.github }),

            GitHub.reducer
                .contramap(action: /Action.github)
                .contramap(state: /State.Current.github)
                .contramap(state: \State.current)
                .contramap(environment: { $0.github })
        )
    }
}
```

To learn more about `CasePath`, visit the official site and tutorials:

- [swift-case-paths](https://github.com/pointfreeco/swift-case-paths)
- [Episode #87: The Case for Case Paths: Introduction](https://www.pointfree.co/episodes/ep87-the-case-for-case-paths-introduction)

## Next Step

TBD
