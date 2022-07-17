import Combine
import SwiftUI

extension Store
{
    /// Lightweight `Store` proxy that is state-observable and action-sendable.
    ///
    /// - Note: This is a common sub-store type for UIKit-Navigation-based app.
    /// - Note: This type doesn't need to protect any raw states, so no need to be `@MainActor`.
    public final class ObservableProxy: ObservableObject
    {
        /// Underlying hot state publisher.
        /// - Note: Not guranteed to emit first value immediately on `subscribe`, as it may be some filtered sub-state.
        public let state: AnyPublisher<State, Never>

        /// Public `Environment` that can be passed to `SwiftUI.View`.
        ///
        /// For example, `AVPlayer` may be needed in both `Reducer` and `AVKit.VideoPlayer`.
        public let environment: Environment

        private let _send: (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Error>?

        public var objectWillChange: AnyPublisher<State, Never>
        {
            state
        }

        /// Designated initializer with receiving `send` from single-source-of-truth `Store`.
        /// - Note: This initializer is `internal`, and should only be instantiated via ``Store/observableProxy-swift.property``.
        internal init<P>(
            state: P,
            environment: Environment,
            send: @escaping (Action, TaskPriority?, _ tracksFeedbacks: Bool) -> Task<(), Error>?
        )
            where P: Publisher, P.Output == State, P.Failure == Never
        {
            self.state = state.eraseToAnyPublisher()
            self.environment = environment
            self._send = send
        }

        /// Initializer for mocking purpose, e.g. SwiftUI Preview.
        public static func mock<P>(
            state: P,
            environment: Environment
        ) -> ObservableProxy
            where P: Publisher, P.Output == State, P.Failure == Never
        {
            return .init(
                state: state,
                environment: environment,
                send: { _, _, _ in Task {} }
            )
        }

        /// Sends `action` to `Store.ObservableProxy`.
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

extension Store.ObservableProxy
{
    /// Transforms `<Action, State>` to `<Action, SubState>` using `Publisher.map`.
    public func map<SubState>(
        state f: @escaping (State) -> SubState
    ) -> Store<Action, SubState, Environment>.ObservableProxy
    {
        .init(
            state: self.state.map(f),
            environment: self.environment,
            send: self.send
        )
    }

    /// Transforms `<Action, State>` to `<Action, SubState>` using `Publisher.compactMap`.
    public func compactMap<SubState>(
        state f: @escaping (State) -> SubState?
    ) -> Store<Action, SubState, Environment>.ObservableProxy
    {
        .init(
            state: self.state.compactMap(f),
            environment: self.environment,
            send: self.send
        )
    }

    /// Transforms `Action` to `Action2`.
    public func contramap<Action2>(action f: @escaping (Action2) -> Action)
        -> Store<Action2, State, Environment>.ObservableProxy
    {
        .init(
            state: self.state,
            environment: self.environment,
            send: { self.send(f($0), priority: $1, tracksFeedbacks: $2) }
        )
    }

    /// Transforms `Environment` to `SubEnvironment`.
    public func map<SubEnvironment>(
        environment f: @escaping (Environment) -> SubEnvironment
    ) -> Store<Action, State, SubEnvironment>.ObservableProxy
    {
        .init(
            state: self.state,
            environment: f(self.environment),
            send: self.send
        )
    }
}

// MARK: - Private

extension Store.ObservableProxy
{
    /// Optional-state `Proxy` that unsafely ignores setter-state-binding.
    @MainActor
    var unsafeProxy: Store<Action, State?, Environment>.Proxy
    {
        .init(
            state: self.unsafeStateBinding,
            environment: self.environment,
            send: self._send
        )
    }

    /// Unsafe state binding that ignores setter handling.
    private var unsafeStateBinding: Binding<State?>
    {
        return Binding<State?>(
            get: {
                self.currentState
            },
            set: { newValue in
                // Comment-Out: Setter binding is not supported.
//                Task {
//                    await self.actomaton.send(.state(newValue))
//                }
            }
        )
    }

    /// Retrieves hot `state` publisher's current value if possible, used for making `unsafeProxy`.
    private var currentState: State?
    {
        var value: State?
        _ = state.prefix(1).sink {
            value = $0
        }
        return value
    }
}
