# 🎭 Actomaton

[![Swift 5.5](https://img.shields.io/badge/swift-5.5-orange.svg?style=flat)](https://swift.org/download/)
![](https://github.com/inamiy/Actomaton/actions/workflows/main.yml/badge.svg)

🧑‍🎤 Actor + 🤖 Automaton = 🎭 Actomaton

**Actomaton** is Swift `async`/`await` & `Actor`-powered effectful state-management framework
inspired by [Elm](http://elm-lang.org/) and [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture).

This repository consists of 2 frameworks:

1. `Actomaton`: Actor-based effect-handling state-machine at its core. Linux ready.
2. `ActomatonStore`: SwiftUI & Combine support

These frameworks depend on [swift-case-paths](https://github.com/pointfreeco/swift-case-paths) as Functional Prism library, which is a powerful tool to construct an App-level Mega-Reducer from each screen's Reducers.

This framework is a successor of the following projects:

- [Harvest](https://github.com/inamiy/Harvest) (using Combine with SwiftUI support)
- [ReactiveAutomaton](https://github.com/inamiy/ReactiveAutomaton) (using [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift))
- [RxAutomaton](https://github.com/inamiy/RxAutomaton) (using [RxSwift](https://github.com/ReactiveX/RxSwift))

## Demo App

- [Actomaton-Gallery](https://github.com/inamiy/Actomaton-Gallery)

## Documentation

- Actomaton: https://actomaton.web.app/documentation/actomaton
- ActomatonStore: https://actomaton.web.app/documentation/actomatonstore (Currently in Japanese only)

## 1. Actomaton (Core)

### Example 1-1. Simple Counter

```swift
enum State {
    var count: Int = 0
}

enum Action {
    case increment
    case decrement
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

If you want to do some logging (side-effect), add `Effect` in `Reducer` as follows:

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

NOTE: There are 5 ways of creating `Effect` in Actomaton:

1. No side-effects, but next action only
    - `Effect.nextAction`
2. Single `async` without next action
    - `Effect.fireAndForget(id:run:)`
3. Single `async` with next action
    - `Effect.init(id:run:)`
4. Multiple `async`s (i.e. `AsyncSequence`) with next actions
    - `Effect.init(id:sequence:)`
5. Manual cancellation
    - `Effect.cancel(id:)` / `.cancel(ids:)`

### Example 1-2. Login-Logout (and ForceLogout)

![login-diagram](https://user-images.githubusercontent.com/138476/132146518-686deb5f-ff01-489a-abf2-e2ef2a2adb03.png)

```swift
enum State {
    case loggedOut, loggingIn, loggedIn, loggingOut
}

enum Action {
    case login, loginOK, logout, logoutOK
    case forceLogout
}

// NOTE:
// Use same `EffectID` so that if previous effect is still running,
// next effect with same `EffectID` will automatically cancel the previous one.
//
// Note that `EffectID` is also useful for manual cancellation via `Effect.cancel`.
struct LoginFlowEffectID: EffectIDProtocol {}

struct Environment {
    let loginEffect: (userId: String) -> Effect<Action>
    let logoutEffect: Effect<Action>
}

let environment = Environment(
    loginEffect: { userId in
        Effect(id: LoginFlowEffectID()) {
            let loginRequest = ...
            let data = try? await URLSession.shared.data(for: loginRequest)
            if Task.isCancelled { return nil }
            ...
            return Action.loginOK // next action
        }
    },
    logoutEffect: {
        Effect(id: LoginFlowEffectID()) {
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
        // Login's effect will be automatically cancelled because of same `EffectID.
        try await Task.sleep(/* 1 ms */)
        t = await actomaton.send(.forceLogout)

        assertEqual(await actomaton.state, .loggingOut)

        await t?.value // wait for previous effect
        assertEqual(await actomaton.state, .loggedOut)

    }
}
```

Here we see the notions of `EffectID`, `Environment`, and `let task: Task<(), Error> = actomaton.send(...)`

- `EffectID` is for both manual & automatic cancellation of previous running effects. In this example, `forceLogout` will cancel `login`'s networking effect.
- `Environment` is useful for injecting effects to be called inside `Reducer` so that they become replaceable. **`Environment` is known as Dependency Injection** (using Reader monad).
- (Optional) `Task<(), Error>` returned from `actomaton.send(action)` is another fancy way of dealing with "all the effects triggered by `action`". We can call `await task.value` to wait for all of them to be completed, or `task.cancel()` to cancel all. Note that `Actomaton` already manages such `task`s for us internally, so we normally don't need to handle them by ourselves (use this as a last resort!).

### Example 1-3. Timer (using `AsyncSequence`)

```swift
typealias State = Int

enum Action {
    case start, tick, stop
}

struct TimerID: EffectIDProtocol {}

struct Environment {
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

In this example, `Effect(id:sequence:)` is used for timer effect, which yields `Action.tick` multiple times.

### Example 1-4. Reducer composition

[Actomaton-Gallery](https://github.com/inamiy/Actomaton-Gallery) provides a good example of how `Reducer`s can be combined together into one big Reducer using `Reducer.combine`.

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

## 2. ActomatonStore (SwiftUI)

`Store` (from `ActomatonStore.framework`) provides a thin wrapper of `Actomaton` to work seamlessly in SwiftUI world.
It will be stored as a `@StateObject` of the App's view.

For example, from [Actomaton-Gallery](https://github.com/inamiy/Actomaton-Gallery):

```swift
struct AppView: View {
    @StateObject
    private var store: Store<Root.Action, Root.State, Roote.Environment> = .init(
        state: Root.State(...),
        reducer: Root.reducer,
        environment: Root.Environment(...)
    )

    init() {}

    var body: some View {
        // IMPORTANT: Pass `Store.Proxy` to children.
        RootView(store: self.store.proxy)
    }
}

struct RootView: View {
    // IMPORTANT: `Store.Proxy`, not `Store` itself.
    private let store: Store<Root.Action, Root.State, Root.Environment>.Proxy

    init(store: Store<Root.Action, Root.State, Root.Environment>.Proxy) {
        self.store = store
    }

    var body: some View {
        return VStack {
            NavigationView {
                List {
                    navigationLink(example: allExamples[0])
                    navigationLink(example: allExamples[1])
                    navigationLink(example: allExamples[2])
                    navigationLink(example: allExamples[3])
                    navigationLink(example: allExamples[4])
                }
                .navigationBarTitle(Text("🎭 Actomaton Gallery 🖼️"), displayMode: .large)
            }
        }
    }

    private func navigationLink(example: Example) -> some View {
        NavigationLink(
            destination: example.exampleView(store: self.store)
                .navigationBarTitle(
                    "\(example.exampleTitle)",
                    displayMode: .inline
                ),
            isActive: self.store.current
                .stateBinding(onChange: Root.Action.changeCurrent)
                .transform(
                    get: { $0?.example.exampleTitle == example.exampleTitle },
                    set: { _, isPresenting in
                        isPresenting ? example.exampleInitialState : nil
                    }
                )
        ) {
            HStack(alignment: .firstTextBaseline) {
                example.exampleIcon
                    .frame(width: 44)
                Text(example.exampleTitle)
            }
            .font(.body)
            .padding(5)
        }
    }
}
```

Here, the most important part is that the **topmost container view of the app will hold `Store` as a single source of truth**, and for the child views, **`Store.Proxy` will be passed** instead, so that we don't duplicate multiple `Store`s but `Binding` and `Store.proxy.send` (sending message to topmost `Store`) functionalities are still available.

![](https://user-images.githubusercontent.com/138476/132122727-b709322d-199f-4407-8ce3-a235ed6dd1cf.png)
![](https://user-images.githubusercontent.com/138476/132122732-4b726853-05d6-47ad-9166-a44a0f02f672.png)

This (and overall) architecture is inherited from [Harvest](https://github.com/inamiy/Harvest) which has a different `Store` structure compared to [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture).

See following information for more details:

- [Functional iOS Architecture for SwiftUI - Speaker Deck (p.39)](https://speakerdeck.com/inamiy/functional-ios-architecture-for-swiftui?slide=39)
- [Composable Architecture｜Functional iOS Architecture for SwiftUI (English)](https://zenn.dev/inamiy/books/3dd014a50f321040a047/viewer/cca752a1fe8700f9d0c0)

### `Store.Proxy.stateBinding`

To interact with SwiftUI's State-binding-based event handling, `ActomatonStore` provides `Store.Proxy.stateBinding` hook methods so that **direct state changes can be converted into action dispatches (indirection)**
This indirection allows us to build more sophisticated UI architecture including better testing.

## References

- [Functional iOS Architecture for SwiftUI - Speaker Deck](https://speakerdeck.com/inamiy/functional-ios-architecture-for-swiftui)
- [Functional iOS Architecture for SwiftUI (English)](https://zenn.dev/inamiy/books/3dd014a50f321040a047)

## License

[MIT](LICENSE)
