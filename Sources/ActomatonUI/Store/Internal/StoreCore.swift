#if !DISABLE_COMBINE && canImport(Combine)
import Combine

/// Internal core that drives a ``MealyMachine`` from the MainActor and exposes its state through a
/// Combine `CurrentValueSubject` for SwiftUI / UIKit consumers.
///
/// Handles both `Action` as indirect messaging and `State` that can directly replace
/// state via SwiftUI 2-way binding (through ``BindableAction``).
@MainActor
internal final class StoreCore<Action, State, Environment>
    where Action: Sendable, State: Sendable, Environment: Sendable
{
    private typealias Machine = MealyMachine<
        BindableAction<Action, State>,
        State,
        Effect<BindableAction<Action, State>>
    >

    private let machine: Machine

    private let effectManager: EffectQueueManager<BindableAction<Action, State>, State>

    private let _state: CurrentValueSubject<State, Never>

    internal let environment: Environment

    internal var cancellables: Set<AnyCancellable> = []

    /// Initializer with `environment`.
    internal init(
        state initialState: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment,
        effectContext: EffectContext,
        configuration: StoreConfiguration
    )
    {
        let _state = CurrentValueSubject<State, Never>(initialState)
        self._state = _state
        self.environment = environment

        let machine = Machine(
            state: initialState,
            reducer: lift(reducer: reducer)
                .log(format: configuration.logFormat),
            environment: environment,
            willChangeState: { _, new in
                _state.value = new
            }
        )

        self.machine = machine

        let effectManager = EffectQueueManager<BindableAction<Action, State>, State>(effectContext: effectContext)
        self.effectManager = effectManager

        effectManager.setUp(
            withSendability: { [weak self] runEffM in
                await self?.runIsolatedEffectManager(runEffM)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks in
                await self?.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
            }
        )
    }

    isolated deinit
    {
        Debug.print("[deinit] StoreCore \(String(format: "%p", ObjectIdentifier(self).hashValue))")
        effectManager.shutDown()
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
    ) -> Task<(), any Error>?
    {
        let output = machine.send(action)
        return effectManager.processOutput(output, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Runs `runEffM` on the MainActor, supplying the underlying ``EffectManager`` so that
    /// conformers can mutate their own bookkeeping safely from detached tasks without
    /// capturing `self` itself.
    private func runIsolatedEffectManager<EffM>(
        _ runEffM: (EffM) -> Void
    ) where EffM: EffectManager<BindableAction<Action, State>, State, Effect<BindableAction<Action, State>>>
    {
        runEffM(effectManager as! EffM)
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

#endif
