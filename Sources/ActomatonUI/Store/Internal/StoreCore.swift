import Combine

/// `MainActomaton` wrapper that handles both `Action` as indirect messaging
/// and `State` that can directly replace `actomaton.state` via SwiftUI 2-way binding.
@MainActor
internal final class StoreCore<Action, State, Environment>
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private let actomaton: MainActomaton<BindableAction<Action, State>, State>

    private let _state: CurrentValueSubject<State, Never>

    internal let environment: Environment

    internal var cancellables: Set<AnyCancellable> = []

    /// Initializer with `environment`.
    internal init(
        state initialState: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment,
        configuration: StoreConfiguration
    )
    {
        self._state = CurrentValueSubject(initialState)
        self.environment = environment

        self.actomaton = MainActomaton(
            state: initialState,
            reducer: lift(reducer: reducer)
                .log(format: configuration.logFormat),
            environment: environment
        )

        self.actomaton.$state
            .sink(receiveValue: { [weak self] state in
                self?.updateState(state)
            })
            .store(in: &cancellables)

        // Comment-Out: Using `for await` causes SwiftUI animation not working correctly.
//        self.task = Task { [weak self] in
//            guard let stream = self?.actomaton.$state.toAsyncStream() else { return }
//
//            for await newState in stream {
//                self?.updateState(newState)
//            }
//        }
    }

    deinit
    {
        Debug.print("[deinit] StoreCore \(String(format: "%p", ObjectIdentifier(self).hashValue))")
    }

    internal var state: CurrentValuePublisher<State>
    {
        .init(self._state)
    }

    /// Sends either `action` or `state`.
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
    internal func send(
        _ action: BindableAction<Action, State>,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Error>?
    {
        switch action {
        case let .action(action):
            return self.actomaton.send(.action(action), priority: priority, tracksFeedbacks: tracksFeedbacks)

        case let .state(state):
            return self.actomaton.send(.state(state), priority: priority, tracksFeedbacks: tracksFeedbacks)
        }
    }

    private func updateState(_ newState: State)
    {
        self._state.value = newState
    }
}

// MARK: - Private

/// Lifts from `Reducer`'s `Action` to `Store.BindableAction`.
private func lift<Action, State, Environment>(
    reducer: Reducer<Action, State, Environment>
) -> Reducer<BindableAction<Action, State>, State, Environment>
{
    .init { action, state, environment in
        switch action {
        case let .action(innerAction):
            let effect = reducer.run(innerAction, &state, environment)
            return effect.map { BindableAction<Action, State>.action($0) }

        case let .state(newState):
            state = newState
            return .empty
        }
    }
}
