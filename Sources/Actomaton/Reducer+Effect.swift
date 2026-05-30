import ActomatonCore
import CasePaths

/// `Effect`-specific `MealyReducer` extensions: monoid, contramap(action:), map(id:), map(queue:).
///
/// `Emission` is exposed as a method-level generic so these helpers cover every
/// `Effect<Action, Emission>` reducer output shape. Use `Emission == Never` for wrappers
/// that do not expose a side-channel result stream, and a concrete `Emission` for
/// `Actomaton` / `MealyDriver` callers that do.

// MARK: - Monoid

extension MealyReducer
{
    public static func empty<Emission>() -> Self where Output == Effect<Action, Emission>
    {
        .init { _, _, _ in .empty }
    }

    public static func + <Emission>(l: Self, r: Self) -> Self
        where Output == Effect<Action, Emission>
    {
        .init { action, state, environment in
            l.run(action, &state, environment) + r.run(action, &state, environment)
        }
    }

    public static func combine<Emission>(_ reducers: [Self]) -> Self
        where Output == Effect<Action, Emission>
    {
        reducers.reduce(into: .empty(), { $0 = $0 + $1 })
    }

    public static func combine<Emission>(_ reducers: Self...) -> Self
        where Output == Effect<Action, Emission>
    {
        combine(reducers)
    }
}

// MARK: - Contravariant Functor (Action)

extension MealyReducer
{
    /// Transforms `Action` using `CasePath`.
    public func contramap<GlobalAction, Emission>(
        action toLocalAction: CasePath<GlobalAction, Action>
    ) -> MealyReducer<GlobalAction, State, Environment, Effect<GlobalAction, Emission>>
        where Output == Effect<Action, Emission>
    {
        .init { action, state, environment in
            guard let localAction = toLocalAction.extract(from: action) else { return .empty }

            return self
                .run(
                    localAction,
                    &state,
                    environment
                )
                .map(action: { toLocalAction.embed($0) })
        }
    }

    /// Transforms `State` using `CasePath`.
    /// - Note: Overrides the generic version to provide `.empty` fallback.
    public func contramap<GlobalState, Emission>(
        state toLocalState: CasePath<GlobalState, State>
    ) -> MealyReducer<Action, GlobalState, Environment, Effect<Action, Emission>>
        where Output == Effect<Action, Emission>
    {
        .init { action, state, environment in
            guard var localState = toLocalState.extract(from: state) else { return .empty }

            let effect = self.run(
                action,
                &localState,
                environment
            )
            state = toLocalState.embed(localState)
            return effect
        }
    }
}

// MARK: - Functor (EffectID / EffectQueue)

extension MealyReducer
{
    /// Changes `EffectID`.
    public func map<ID, Emission>(id f: @escaping @Sendable ((any EffectID)?) -> ID?) -> Self
        where ID: EffectID, Output == Effect<Action, Emission>
    {
        .init { action, state, environment in
            self.run(action, &state, environment)
                .map(id: f)
        }
    }

    /// Changes `EffectQueue`.
    public func map<Queue, Emission>(queue f: @escaping @Sendable ((any EffectQueue)?) -> Queue?) -> Self
        where Queue: EffectQueue, Output == Effect<Action, Emission>
    {
        .init { action, state, environment in
            self.run(action, &state, environment)
                .map(queue: f)
        }
    }
}
