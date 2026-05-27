# Example 5: Making a large app (Reducer Composition)

Reducer composition example.

## Overview

 [Actomaton-Gallery](https://github.com/Actomaton/Actomaton-Gallery) provides a good example of how `Reducer`s can be combined together into one big Reducer using `Reducer.combine`.

In this example, [swift-case-paths](https://github.com/pointfreeco/swift-case-paths) is used as a counterpart of `WritableKeyPath`, so if we use both, we can easily construct Mega-Reducer without a hassle.

(NOTE: `CasePath` is useful when dealing with enums, e.g. `enum Action` and `enum Current` in this example)

- `Reducer.combine(...)` merges multiple `Reducer`s into one. Each child runs in turn for the same `Action` / `State` / `Environment`, and their `Effect`s are concatenated.
- `contramap` adapts a small child `Reducer` to fit a larger parent type. It comes in three variants:
    - `.contramap(action: CasePath<ParentAction, ChildAction>)` — extracts the child action from a parent `enum Action` case. Non-matching actions are ignored.
    - `.contramap(state:)` — narrows the parent `State` to the child's `State`, using either a `WritableKeyPath` (for `struct`s) or a `CasePath` (for `enum`s). Mutations are written back to the parent.
    - `.contramap(environment: (ParentEnv) -> ChildEnv)` — projects the child's slice of dependencies out of the parent `Environment`.

Chaining these turns each child `Reducer` into a parent-shaped `Reducer<Action, State, Environment>`, which `Reducer.combine` can then merge.

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
                .contramap(environment: { $0.github })
        )
    }
}
```

To learn more about `CasePath`, visit the official site and tutorials:

- [swift-case-paths](https://github.com/pointfreeco/swift-case-paths)
- [Episode #87: The Case for Case Paths: Introduction](https://www.pointfree.co/episodes/ep87-the-case-for-case-paths-introduction)

## Next Step

For a full multi-screen app composing many `Reducer`s this way, see [Actomaton-Gallery](https://github.com/Actomaton/Actomaton-Gallery).
