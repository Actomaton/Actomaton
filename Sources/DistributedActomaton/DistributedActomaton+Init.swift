import Actomaton
import ActomatonEffect
import Distributed
import Foundation

/// Convenience initializers that default to ``EffectQueueManager``.
extension DistributedActomaton
{
    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: Reducer<Action, State, (), Emission>,
        effectContext: EffectContext = .init(clock: ContinuousClock()),
        actorSystem: ActorSystem
    )
    {
        self.init(
            state: state,
            reducer: reducer,
            effectManager: EffectQueueManager<Action, State, Emission>(effectContext: effectContext),
            actorSystem: actorSystem
        )
    }

    /// Initializer with `environment`.
    public init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment, Emission>,
        environment: Environment,
        effectContext: EffectContext = .init(clock: ContinuousClock()),
        actorSystem: ActorSystem
    ) where Environment: Sendable
    {
        self.init(
            state: state,
            reducer: Reducer<Action, State, (), Emission> { action, state, _ in
                reducer.run(action, &state, environment)
            },
            effectManager: EffectQueueManager<Action, State, Emission>(effectContext: effectContext),
            actorSystem: actorSystem
        )
    }
}
