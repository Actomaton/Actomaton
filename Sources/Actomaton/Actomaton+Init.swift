import ActomatonCore
import ActomatonEffect

/// Convenience initializers that default to ``EffectQueueManager``.
extension MealyMachine where Output == Effect<Action>
{
    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: Reducer<Action, State, ()>,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    ) where Action: Sendable
    {
        self.init(
            state: state,
            reducer: reducer,
            effectManager: EffectQueueManager<Action, State>(effectContext: effectContext)
        )
    }

    /// Initializer with `environment`.
    public init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    ) where Action: Sendable, Environment: Sendable
    {
        self.init(
            state: state,
            reducer: Reducer<Action, State, ()> { action, state, _ in
                reducer.run(action, &state, environment)
            },
            effectManager: EffectQueueManager<Action, State>(effectContext: effectContext)
        )
    }
}
