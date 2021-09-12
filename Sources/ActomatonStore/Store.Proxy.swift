import SwiftUI

extension Store
{
    /// Lightweight `Store` proxy that is state-bindable and action-sendable without duplicating internal state.
    @dynamicMemberLookup
    public struct Proxy
    {
        @Binding
        public private(set) var state: State

        public let send: (Action, TaskPriority) -> Void

        public init(state: Binding<State>, send: @escaping (Action, TaskPriority) -> Void)
        {
            self._state = state
            self.send = send
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
            .init(state: self.$state, send: { self.send(f($0), $1) })
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
                        self.send(action, stateBindingTaskPriority)
                    }
                }
            )
        }
    }
}
