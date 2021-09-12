import SwiftUI

extension Store
{
    /// Lightweight `Store` proxy that is state-bindable and action-sendable without duplicating internal state.
    @dynamicMemberLookup
    public struct Proxy
    {
        @Binding
        public private(set) var state: State

        private let _send: (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Never>?

        public init(state: Binding<State>, send: @escaping (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Never>?)
        {
            self._state = state
            self._send = send
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

        /// Transforms `<Action, State>` to `<Action, SubState>` using keyPath `@dynamicMemberLookup`.
        public subscript<SubState>(
            dynamicMember keyPath: WritableKeyPath<State, SubState>
        ) -> Store<Action, SubState>.Proxy
        {
            .init(state: self.$state[dynamicMember: keyPath], send: self.send)
        }

        /// Transforms `Action` to `Action2`.
        public func contramap<Action2>(action f: @escaping (Action2) -> Action)
            -> Store<Action2, State>.Proxy
        {
            .init(state: self.$state, send: { self.send(f($0), priority: $1, tracksFeedbacks: $2) })
        }

        // MARK: - To Binding

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
    }
}
