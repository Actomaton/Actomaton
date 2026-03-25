/// `Effect`-specific `ActomatonCore.Reducer` extensions: monoid, contramap(action:), map(id:), map(queue:).
extension MealyReducer where Output == Effect<Action>
{
    // MARK: - Monoid

    public static var empty: Self
    {
        .init { _, _, _ in .empty }
    }

    public static func + (l: Self, r: Self) -> Self
    {
        .init { action, state, environment in
            l.run(action, &state, environment) + r.run(action, &state, environment)
        }
    }

    public static func combine(_ reducers: [Self]) -> Self
    {
        reducers.reduce(into: .empty, { $0 = $0 + $1 })
    }

    public static func combine(_ reducers: Self...) -> Self
    {
        self.combine(reducers)
    }

    // MARK: - Contravariant Functor (Action)

    /// Transforms `Action` using `CasePath`.
    public func contramap<GlobalAction>(
        action toLocalAction: CasePath<GlobalAction, Action>
    ) -> MealyReducer<GlobalAction, State, Environment, Effect<GlobalAction>>
    {
        .init { action, state, environment in
            guard let localAction = toLocalAction.extract(from: action) else { return .empty }

            return self
                .run(
                    localAction,
                    &state,
                    environment
                )
                .map { toLocalAction.embed($0) }
        }
    }

    /// Transforms `State` using `CasePath`.
    /// - Note: Overrides the generic version to provide `.empty` fallback.
    public func contramap<GlobalState>(
        state toLocalState: CasePath<GlobalState, State>
    ) -> MealyReducer<Action, GlobalState, Environment, Effect<Action>>
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

    // MARK: - Functor

    /// Changes `EffectID`.
    public func map<ID>(id f: @escaping @Sendable (EffectID?) -> ID?) -> Self
        where ID: EffectIDProtocol
    {
        .init { action, state, environment in
            let effect = self.run(action, &state, environment)
                .map(id: f)
            return effect
        }
    }

    /// Changes `EffectQueue`.
    public func map<Queue>(queue f: @escaping @Sendable (EffectQueue?) -> Queue?) -> Self
        where Queue: EffectQueueProtocol
    {
        .init { action, state, environment in
            let effect = self.run(action, &state, environment)
                .map(queue: f)
            return effect
        }
    }
}
