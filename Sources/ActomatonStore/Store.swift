import Foundation
import SwiftUI
import Combine

/// Store of `Actomaton` optimized for SwiftUI's 2-way binding.
@MainActor
open class Store<Action, State>: ObservableObject
    where Action: Sendable, State: Sendable
{
    private let actomaton: Actomaton<BindableAction, State>

    @Published
    public private(set) var state: State

    private var cancellables: [AnyCancellable] = []

    /// Initializer without `environment`.
    public convenience init(
        state initialState: State,
        reducer: Reducer<Action, State, ()>
    )
    {
        self.init(state: initialState, reducer: reducer, environment: ())
    }

    /// Initializer with `environment`.
    public init<Environment>(
        state initialState: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment
    ) where Environment: Sendable
    {
        self.state = initialState

        self.actomaton = Actomaton(
            state: initialState,
            reducer: lift(reducer: Reducer { action, state, environment in
                reducer.run(action, &state, environment)
            }),
            environment: environment
        )

        Task {
            let statePublisher = await self.actomaton.$state

            statePublisher
                .receive(on: DispatchQueue.main)
                .assign(to: \.state, on: self)
                .store(in: &cancellables)
        }
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
    public nonisolated func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Error>
    {
        Task(priority: priority) {
            let task = await self.actomaton.send(.action(action), priority: priority, tracksFeedbacks: tracksFeedbacks)
            try await task?.value
        }
    }

    /// Lightweight `Store` proxy that is state-bindable and action-sendable without duplicating internal state.
    /// - Note: This is a common sub-store type for SwiftUI-based app.
    public var proxy: Proxy
    {
        Proxy(state: self.stateBinding, send: self.send)
    }

    /// Lightweight `Store` proxy that is state-observable and action-sendable.
    /// - Note: This is a common sub-store type for UIKit-Navigation-based app.
    public var observableProxy: ObservableProxy
    {
        ObservableProxy(state: self.$state, send: self.send)
    }
}

// MARK: - Private

// NOTE:
// These are marked as `private` since passing `Store.Proxy` instead of `Store`
// to SwiftUI's `View`s is preferred.
// To call these methods, use `proxy` instead.
extension Store
{
    private var stateBinding: Binding<State>
    {
        return Binding<State>(
            get: {
                self.state
            },
            set: { newValue in
                Task {
                    await self.actomaton.send(.state(newValue))
                }
            }
        )
    }
}

extension Store {
    /// `action` as indirect messaging, or `state` that can directly replace `actomaton.state` via SwiftUI 2-way binding.
    fileprivate enum BindableAction: Sendable
    {
        case action(Action)
        case state(State)
    }
}

/// Lifts from `Reducer`'s `Action` to `Store.BindableAction`.
private func lift<Action, State, Environment>(
    reducer: Reducer<Action, State, Environment>
) -> Reducer<Store<Action, State>.BindableAction, State, Environment>
{
    .init { action, state, environment in
        switch action {
        case let .action(innerAction):
            let effect = reducer.run(innerAction, &state, environment)
            return effect.map { Store<Action, State>.BindableAction.action($0) }

        case let .state(newState):
            state = newState
            return .empty
        }
    }
}
