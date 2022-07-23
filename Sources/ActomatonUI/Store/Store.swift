/// `MainActomaton`-erased wrapper which can ``map(state:)`` into sub-store.
///
/// - Important: ``Store`` is NOT `ObservableObject` thus its state can't be observed by SwiftUI views.
///
/// To make it observable in SwiftUI, use ``WithViewStore`` (SwiftUI View) to create ``ViewStore`` which is `ObservableObject`.
/// Note that ``Store/map(state:)`` can narrow down ``Store``'s scope before passing to ``WithViewStore``
/// so that only the subset of state changes can be observed by SwiftUI, allowing optimized rendering.
///
/// ```swift
/// struct ContentView: View {
///     let store: Store<Action, State, Environment>
///     ...
///     var body: some View {
///         WithViewStore(store) { viewStore in
///             Text("Hello, \(viewStore.state.username)") // NOTE: Can shorten to `viewStore.username`.
///         }
///         // NOTE:
///         // This impl is OK, but it observes `store`'s entire state, which is not optimal.
///         // To only observe `state.username` change (for optimization whenever needed),
///         // narrow down the scope by calling `WithViewStore(store.map(state: \.username))` instead.
///     }
/// }
/// ```
///
/// For UIKit views, use `$state` publisher to observe state change.
/// To narrow down the scope and reduce duplicated partial-state update,
/// use Combine's `map`, `compactMap`, and `removeDuplicates`.
///
/// ```swift
/// let store: Store<State, Action, Environment>
/// ...
/// func viewDidLoad() {
///     super.viewDidLoad()
///
///     // Receive partial state update.
///     // (Use `removeDuplicates` for handling actual changes)
///     self.store.$state
///         .map { $0.username }
///         .removeDuplicates()
///         .sink { [weak self] in
///             self?.label.text = $0
///         }
///         .store(in: &self.cancellables)
/// }
/// ```
@MainActor
public class Store<Action, State, Environment>
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    @CurrentValuePublisher
    public var state: State

    /// Public `Environment` that can be passed to `SwiftUI.View`.
    ///
    /// For example, `AVPlayer` may be needed in both `Reducer` and `AVKit.VideoPlayer`.
    public let environment: Environment

    private let _send: @MainActor (BindableAction<Action, State>, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Error>?

    /// Initializer with `environment`.
    public convenience init(
        state initialState: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment,
        configuration: StoreConfiguration = .init()
    )
    {
        let core = StoreCore<Action, State, Environment>(
            state: initialState,
            reducer: reducer,
            environment: environment,
            configuration: configuration
        )

        self.init(
            state: core.state,
            environment: environment,
            send: { core.send($0, priority: $1, tracksFeedbacks: $2) }
        )
    }

    /// Initializer without `environment`.
    public convenience init(
        state initialState: State,
        reducer: Reducer<Action, State, Void>,
        configuration: StoreConfiguration = .init()
    ) where Environment == Void
    {
        self.init(
            state: initialState,
            reducer: reducer,
            environment: (),
            configuration: configuration
        )
    }

    /// Designated initializer with receiving `send` from single-source-of-truth `Store`.
    internal init(
        state: CurrentValuePublisher<State>,
        environment: Environment,
        send: @escaping @MainActor (BindableAction<Action, State>, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Error>?
    )
    {
        self._state = state
        self.environment = environment
        self._send = send
    }

    /// Sends `action` to `Store`.
    ///
    /// - Parameters:
    ///   - priority:
    ///     Priority of the task. If `nil`, the priority will come from `Task.currentPriority`.
    ///   - tracksFeedbacks:
    ///     If `true`, returned `Task` will also track its feedback effects that are triggered by next actions,
    ///     so that their wait-for-all and cancellations are possible.
    ///     Default is `false`.
    ///
    /// - Returns:
    ///   Unified task that can handle (wait for or cancel) all combined effects triggered by `action` in `Reducer`.
    @discardableResult
    public func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Error>?
    {
        self._send(.action(action), priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Sends either `action` or `state`.
    @discardableResult
    internal func _send(
        _ action: BindableAction<Action, State>,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Error>?
    {
        self._send(action, priority, tracksFeedbacks)
    }

    internal var currentValuePublisher: CurrentValuePublisher<State>
    {
        self._state
    }
}

// MARK: - To ViewStore

extension Store
{
    /// Creates `ViewStore` (SwiftUI `Binding`-builder).
    public func viewStore(
        areStatesEqual: @escaping (State, State) -> Bool
    ) -> ViewStore<Action, State>
    {
        .init(
            state: self._state,
            send: { self._send($0, priority: $1, tracksFeedbacks: $2) },
            areStatesEqual: areStatesEqual
        )
    }
}

extension Store where State: Equatable
{
    /// Creates `ViewStore` (SwiftUI `Binding`-builder).
    public var viewStore: ViewStore<Action, State>
    {
        self.viewStore(areStatesEqual: ==)
    }
}

// MARK: - Functor (Sub-Store)

extension Store
{
    /// Transforms `<Action, State>` to `<Action, SubState>`.
    public func map<SubState>(
        state keyPath: WritableKeyPath<State, SubState>
    ) -> Store<Action, SubState, Environment>
        where SubState: Sendable
    {
        self.map(
            state: (
                get: { $0[keyPath: keyPath] },
                set: { $0[keyPath: keyPath] = $1 }
            )
        )
    }

    /// Transforms `<Action, State?>` to `<Action, SubState?>`.
    public func map<State_, SubState>(
        optionalState keyPath: WritableKeyPath<State_, SubState>
    ) -> Store<Action, SubState?, Environment>
        where State == State_?, State_: Sendable, SubState: Sendable
    {
        self.map(
            state: (
                get: { $0.map { $0[keyPath: keyPath] } },
                set: { state, substate in
                    if let substate = substate {
                        state?[keyPath: keyPath] = substate
                    }
                }
            )
        )
    }

    /// Transforms `<Action, [State]>` to `<Action, [SubState]>`.
    public func map<State_, SubState>(
        states keyPath: WritableKeyPath<State_, SubState>
    ) -> Store<Action, [SubState], Environment>
        where State == [State_], State_: Sendable, SubState: Sendable
    {
        self.map(
            state: (
                get: { $0.map { $0[keyPath: keyPath] } },
                set: { states, substates in
                    for (i, substate) in zip(states.indices, substates) {
                        states[i][keyPath: keyPath] = substate
                    }
                }
            )
        )
    }

    /// Transforms `<Action, State>` to `<Action, SubState>`.
    fileprivate func map<SubState>(
        state lens: (get: (State) -> SubState, set: (inout State, SubState) -> Void)
    ) -> Store<Action, SubState, Environment>
        where SubState: Sendable
    {
        .init(
            state: self._state.map(lens.get),
            environment: self.environment,
            send: { action, priority, tracksFeedback in
                switch action {
                case let .action(action):
                    return self._send(.action(action), priority: priority, tracksFeedbacks: tracksFeedback)

                case let .state(substate):
                    var state = self.state
                    lens.set(&state, substate)
                    return self._send(.state(state), priority: priority, tracksFeedbacks: tracksFeedback)
                }
            }
        )
    }

    /// Transforms `Action` to `SubAction`.
    public func contramap<SubAction>(action f: @escaping (SubAction) -> Action)
        -> Store<SubAction, State, Environment>
        where SubAction: Sendable
    {
        .init(
            state: self._state,
            environment: self.environment,
            send: { action, priority, tracksFeedback in
                self._send(action.map(action: f), priority: priority, tracksFeedbacks: tracksFeedback)
            }
        )
    }

    /// Transforms `Environment` to `SubEnvironment`.
    public func map<SubEnvironment>(
        environment f: @escaping (Environment) -> SubEnvironment
    ) -> Store<Action, State, SubEnvironment>
        where SubEnvironment: Sendable
    {
        .init(
            state: self._state,
            environment: f(self.environment),
            send: self._send
        )
    }
}

// MARK: - Other state transforms

extension Store
{
    /// Transforms `<Action, State>` to `<Action, SubState>`
    /// where `SubState` is derived from `get`-only computed property which is not mutable.
    ///
    /// This is a weaker form of ``Store/map(state:)`` (which receives `WritableKeyPath`).
    ///
    /// - Warning: Returned store can NOT create direct state binding, i.e. ``ViewStore/directBinding``,
    ///   and always require ``ViewStore/binding(get:onChange:)`` (indirect binding) instead.
    public func indirectMap<SubState>(
        state get: @escaping (State) -> SubState
    ) -> Store<Action, SubState, Environment>
        where SubState: Sendable
    {
        .init(
            state: self._state.map(get),
            environment: self.environment,
            send: { action, priority, tracksFeedback in
                switch action {
                case let .action(action):
                    return self._send(.action(action), priority: priority, tracksFeedbacks: tracksFeedback)

                case .state:
                    // `SubState` is immutable, so should not reach here.
                    assertionFailure("Detected the calls of `ViewStore.directBinding` after `Store.indirectMap` which is illegal. Always use `ViewStore.binding(get:onChange:)` whenever using `indirectMap`. Otherwise, direct-binding will be discarded in Release build.")
                    return nil
                }
            }
        )
    }

    /// Transforms `Store<Action, State>` to `Store<Action, SubState?>` using `casePath`,
    /// - Note: This method should be used when `State` is enum type.
    public func caseMap<SubState>(
        state casePath: CasePath<State, SubState>
    ) -> Store<Action, SubState?, Environment>
        where SubState: Sendable
    {
        .init(
            state: self._state.map(casePath.extract),
            environment: self.environment,
            send: { action, priority, tracksFeedback in
                switch action {
                case let .action(action):
                    return self._send(.action(action), priority: priority, tracksFeedbacks: tracksFeedback)

                case let .state(substate):
                    guard let substate = substate else { return nil }

                    let state = casePath.embed(substate)
                    return self._send(.state(state), priority: priority, tracksFeedbacks: tracksFeedback)
                }
            }
        )
    }

    /// Transforms `Store<Action, State?, Environment>` to `Store<Action, State, Environment>?`.
    ///
    /// - Note: This method can often be used alongside ``caseMap(state:)``.
    ///
    /// ```swift
    /// // Decompositioning `store` into Screen1's sub-store, etc.
    /// if let currentStore = store
    ///     .map(state: \State.currentScreen) // struct State { var currentScreen: ScreenState? }
    ///     .optionalize()
    /// {
    ///     if let screen1Store = currentStore
    ///         .caseMap(state: /Screen.screen1) // enum ScreenState { case screen1(Screen1State) }
    ///         .optionalize()
    ///     {
    ///         Screen1View(store: screen1Store) // Show Screen1 if `currentScreen = .screen1`.
    ///     }
    ///     else if screen2Store = currentStore
    ///         .caseMap(state: /Screen.screen1)
    ///         .optionalize()
    ///     {
    ///         Screen2View(store: screen2Store) // Show Screen2 if `currentScreen = .screen2`.
    ///     }
    ///     else ...
    /// }
    /// ```
    public func optionalize<State_>()
        -> Store<Action, State_, Environment>?
        where State == State_?
    {
        guard let state = self.state else { return nil }
        return self.map(state: (get: { $0 ?? state }, set: { $0 = $1 }))
    }
}

// MARK: - noState, noAction, noEnvironment

extension Store
{
    /// Converts `State` to `Void` so that `SwiftUI.View` won't get re-rendered on uninterested state change
    /// when observing ``Store``'s derived ``ViewStore``.
    public var noState: Store<Action, Void, Environment>
    {
        self.map(state: (get: { _ in () }, set: { _, _ in }))
    }

    /// Converts `Action` to `Never`.
    public var noAction: Store<Never, State, Environment>
    {
        self.contramap(action: absurd)
    }

    /// Converts `Environment` to `Void` so that `SwiftUI.View` doesn't need to know about `Environment`.
    public var noEnvironment: Store<Action, State, Void>
    {
        self.map(environment: { _ in () })
    }
}

// MARK: - Private

private func absurd<A>(_ x: Never) -> A {}
