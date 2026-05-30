import ActomatonCore
import ActomatonEffect

/// Convenience initializers that default to ``EffectQueueManager``.
extension MealyDriver
{
    /// Initializer without `environment`.
    public convenience init(
        state: State,
        reducer: Reducer<Action, State, (), Emission>,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    )
    {
        self.init(
            state: state,
            reducer: reducer,
            effectManager: EffectQueueManager<Action, State, Emission>(effectContext: effectContext)
        )
    }

    /// Initializer with `environment`.
    public convenience init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment, Emission>,
        environment: Environment,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    ) where Environment: Sendable
    {
        self.init(
            state: state,
            reducer: Reducer<Action, State, (), Emission> { action, state, _ in
                reducer.run(action, &state, environment)
            },
            effectManager: EffectQueueManager<Action, State, Emission>(effectContext: effectContext)
        )
    }
}
