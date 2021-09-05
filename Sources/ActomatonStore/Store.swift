import Foundation
import SwiftUI
import Combine

/// Store of `Actomaton` optimized for SwiftUI's 2-way binding.
public final class Store<Action, State>: ObservableObject
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
    )
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

    /// Lightweight `Store` proxy without duplicating internal state.
    public var proxy: Proxy
    {
        Proxy(state: self.stateBinding, send: self.send)
    }

}

// MARK: - Private

// NOTE:
// These are marked as `private` since passing `Store.Proxy` instead of `Store`
// to SwiftUI's `View`s is preferred.
// To call these methods, use `proxy` instead.
extension Store
{
    private func send(_ action: Action)
    {
        Task {
            await self.actomaton.send(.action(action))
        }
    }

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
    fileprivate enum BindableAction
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
            return effect.map(Store<Action, State>.BindableAction.action)

        case let .state(newState):
            state = newState
            return .empty
        }
    }
}
