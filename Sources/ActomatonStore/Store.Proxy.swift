import SwiftUI

extension Store
{
    /// Lightweight `Store` proxy that is state-bindable and action-sendable without duplicating internal state.
    /// - Note: This is a common sub-store type for SwiftUI-based app.
    @dynamicMemberLookup
    @MainActor
    public struct Proxy
    {
        /// **Direct** state binding which skips sending `Action` and running `Reducer` by directly modifying state,
        /// just as plain SwiftUI does 2-way state binding.
        ///
        /// If you prefer more "strict" Elm-like architecture to always run `Action` & `Reducer`,
        /// do not use `$state` as `Binding`, and use ``stateBinding(get:onChange:)``
        /// that converts state-setter to `Action` for indirection instead.
        @Binding
        public private(set) var state: State

        /// Public `Environment` that can be passed to `SwiftUI.View`.
        ///
        /// For example, `AVPlayer` may be needed in both `Reducer` and `AVKit.VideoPlayer`.
        public let environment: Environment

        private let _send: @MainActor (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Error>?

        /// Designated initializer with receiving `send` from single-source-of-truth `Store`.
        /// - Note: This initializer is `internal`, and should only be instantiated via ``Store/proxy-swift.property``.
        internal init(
            state: Binding<State>,
            environment: Environment,
            send: @MainActor @escaping (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Error>?
        )
        {
            self._state = state
            self.environment = environment
            self._send = send
        }

        /// Initializer for mocking purpose, e.g. SwiftUI Preview.
        public static func mock(
            state: Binding<State>,
            environment: Environment
        ) -> Store.Proxy
        {
            return .init(
                state: state,
                environment: environment,
                send: { _, _, _ in Task {} }
            )
        }

        /// Sends `action` to `Store.Proxy`.
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
            self._send(action, priority, tracksFeedbacks)
        }
    }
}

// MARK: - Functor

extension Store.Proxy
{
    /// Transforms `<Action, State>` to `<Action, SubState>` using keyPath `@dynamicMemberLookup`.
    public subscript<SubState>(
        dynamicMember keyPath: WritableKeyPath<State, SubState>
    ) -> Store<Action, SubState, Environment>.Proxy
    {
        .init(
            state: self.$state[dynamicMember: keyPath],
            environment: self.environment,
            send: self.send
        )
    }

    /// Transforms `<Action, State>` to `<Action, SubState?>` using `casePath`.
    public subscript<SubState>(
        casePath casePath: CasePath<State, SubState>
    ) -> Store<Action, SubState?, Environment>.Proxy
    {
        .init(
            state: self.$state[casePath: casePath],
            environment: self.environment,
            send: self.send
        )
    }

    /// Transforms `Action` to `Action2`.
    public func contramap<Action2>(action f: @escaping (Action2) -> Action)
        -> Store<Action2, State, Environment>.Proxy
    {
        .init(
            state: self.$state,
            environment: self.environment,
            send: { self.send(f($0), priority: $1, tracksFeedbacks: $2) }
        )
    }

    /// Transforms `Environment` to `SubEnvironment` using `keyPath`.
    public func map<SubEnvironment>(
        environment f: (Environment) -> SubEnvironment
    ) -> Store<Action, State, SubEnvironment>.Proxy
    {
        .init(
            state: self.$state,
            environment: f(environment),
            send: self.send
        )
    }
}

// MARK: - Traversable

extension Store.Proxy
{
    /// Moves `SubState?`'s optional part outside of `Store.Proxy`.
    ///
    /// - Note:
    ///   Use `traverse(\.self)` as the conversion from `Store.Proxy<A, State?>` to `Store.Proxy<A, State>?`.
    public func traverse<SubState>(_ keyPath: WritableKeyPath<State, SubState?>)
        -> Store<Action, SubState, Environment>.Proxy?
    {
        guard let state = self.$state[dynamicMember: keyPath].traverse(\.self) else {
            return nil
        }

        return .init(
            state: state,
            environment: environment,
            send: self.send
        )
    }
}

// MARK: - To Binding

extension Store.Proxy
{
    /// Indirect state-to-action conversion binding to create `Binding<State>`.
    public func stateBinding(
        onChange: @escaping (State) -> Action?
    ) -> Binding<State>
    {
        self.stateBinding(get: { $0 }, onChange: onChange)
    }

    /// Indirect state-to-action conversion binding to create `Binding<SubState>`.
    public func stateBinding<SubState>(
        get: @escaping (State) -> SubState,
        onChange: @escaping (SubState) -> Action?
    ) -> Binding<SubState>
    {
        Binding<SubState>(
            get: {
                get(self.state)
            },
            set: { value, transaction in
                if let action = onChange(value) {
                    _ = withTransaction(transaction) {
                        self.send(action)
                    }
                }
            }
        )
    }

    /// Creates indirect `Binding<Bool>` as SwiftUI presentation binding from optional `State`, and sends `Action` on dismissal.
    public func isPresented<Wrapped>(onDismiss: @autoclosure @escaping () -> Action) -> Binding<Bool>
        where State == Wrapped?
    {
        self.stateBinding(
            get: { $0 != nil },
            onChange: { isPresented in
                isPresented ? nil : onDismiss()
            }
        )
    }

    /// Creates indirect `Binding<Bool>` from `State` as `Bool`, and sends `Action` on dismissal.
    public func isPresented(onDismiss: @autoclosure @escaping () -> Action) -> Binding<Bool>
        where State == Bool
    {
        self.stateBinding(
            onChange: { isPresented in
                isPresented ? nil : onDismiss()
            }
        )
    }
}

// MARK: - noEnvironment

extension Store.Proxy
{
    /// Converts `Environment` to `Void` so that `SwiftUI.View` doesn't need to know about `Environment`.
    public var noEnvironment: Store<Action, State, Void>.Proxy
    {
        self.map(environment: { _ in () })
    }
}
