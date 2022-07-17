import Foundation
import Combine
import SwiftUI

/// Store of `Actomaton` optimized for SwiftUI's 2-way binding.
@MainActor
open class Store<Action, State, Environment>: ObservableObject
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private let actomaton: MainActomaton<BindableAction, State>
    private let reducer: Reducer<Action, State, Environment>

    @Published
    public private(set) var state: State

    /// Public `Environment` that can be passed to `SwiftUI.View`.
    ///
    /// For example, `AVPlayer` may be needed in both `Reducer` and `AVKit.VideoPlayer`.
    public let environment: Environment

    private var cancellables: Set<AnyCancellable> = []

    /// Initializer without `environment`.
    public convenience init(
        state initialState: State,
        reducer: Reducer<Action, State, Void>
    ) where Environment == Void
    {
        self.init(
            state: initialState,
            reducer: reducer,
            environment: ()
        )
    }

    /// Initializer with `environment`.
    public init(
        state initialState: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment
    )
    {
        self.state = initialState
        self.reducer = reducer
        self.environment = environment

        self.actomaton = MainActomaton(
            state: initialState,
            reducer: lift(reducer: Reducer { action, state, environment in
                reducer.run(action, &state, environment)
            }),
            environment: environment
        )

        self.actomaton.$state
            .sink(receiveValue: { [weak self] state in
                self?.state = state
            })
            .store(in: &cancellables)

        // Comment-Out: Using `for await` causes SwiftUI animation not working correctly.
//        self.task = Task { [weak self] in
//            guard let stream = self?.actomaton.$state.toAsyncStream() else { return }
//
//            for await state in stream {
//                self?.state = state
//            }
//        }
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
        // Send `action` to `actomaton`,
        // which also calls `reducer` inside its actor to update state and also runs effects.
        self.actomaton.send(.action(action), priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Lightweight `Store` proxy that is state-bindable and action-sendable without duplicating internal state.
    /// - Note: This is a common sub-store type for SwiftUI-based app.
    public var proxy: Proxy
    {
        Proxy(
            state: self.stateBinding,
            environment: self.environment,
            send: self.send
        )
    }

    /// Lightweight `Store` proxy that is state-observable and action-sendable.
    /// - Note: This is a common sub-store type for UIKit-Navigation-based app.
    public var observableProxy: ObservableProxy
    {
        ObservableProxy(
            state: self.$state,
            environment: self.environment,
            send: { action, _, _ in self.send(action) }
        )
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
            set: { newValue, transaction in
                // Send `BindableAction.state` to `actomaton` asynchronously,
                // which calls `lift`-ed reducer to update whole state (`newValue`) directly.
                self.actomaton.send(.state(newValue))
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
) -> Reducer<Store<Action, State, Environment>.BindableAction, State, Environment>
{
    .init { action, state, environment in
        switch action {
        case let .action(innerAction):
            let effect = reducer.run(innerAction, &state, environment)
            return effect.map { Store<Action, State, Environment>.BindableAction.action($0) }

        case let .state(newState):
            state = newState
            return .empty
        }
    }
}
