import SwiftUI

extension Store
{
    /// Lightweight `Store` proxy that is state-bindable and action-sendable without duplicating internal state.
    @dynamicMemberLookup
    @MainActor
    public struct Proxy
    {
        @Binding
        public private(set) var state: State

        private let _send: @MainActor (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Never>?

        /// Designated initializer with receiving `send` from single-source-of-truth `Store`.
        public init(
            state: Binding<State>,
            send: @MainActor @escaping (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Never>?
        )
        {
            self._state = state
            self._send = send
        }

        /// Initializer with simple `send`, mainly for mocking purpose.
        public init(state: Binding<State>, send: @escaping (Action) -> Void)
        {
            self.init(state: state, send: { action, _, _ in
                send(action)
                return nil
            })
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
        ) -> Task<(), Never>?
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
    ) -> Store<Action, SubState>.Proxy
    {
        .init(state: self.$state[dynamicMember: keyPath], send: self.send)
    }

    /// Transforms `<Action, State>` to `<Action, SubState?>` using casePath.
    public subscript<SubState>(
        casePath casePath: CasePath<State, SubState>
    ) -> Store<Action, SubState?>.Proxy
    {
        .init(state: self.$state[casePath: casePath], send: self.send)
    }

    /// Transforms `Action` to `Action2`.
    public func contramap<Action2>(action f: @escaping (Action2) -> Action)
        -> Store<Action2, State>.Proxy
    {
        .init(state: self.$state, send: { self.send(f($0), priority: $1, tracksFeedbacks: $2) })
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
        -> Store<Action, SubState>.Proxy?
    {
        guard let state = self.$state[dynamicMember: keyPath].traverse(\.self) else {
            return nil
        }

        return .init(state: state, send: self.send)
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
            set: {
                if let action = onChange($0) {
                    self.send(action)
                }
            }
        )
    }

    /// **Direct** state binding which skips sending `Action` and running `Reducer` by directly modifying state,
    /// just as plain SwiftUI does 2-way state binding.
    ///
    /// - Note:
    ///   If you prefer more "strict" Elm-like architecture to always run `Action` & `Reducer`,
    ///   do not use this method, and use `stateBinding` that converts state-setter to `Action` for indirection instead.
    public var directStateBinding: Binding<State>
    {
        self._state
    }
}
