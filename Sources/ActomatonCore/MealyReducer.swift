/// A composable, `State`-transforming function wrapper that is triggered by `Action`.
public struct MealyReducer<Action, State, Environment, Output>: Sendable
{
    public let run: @Sendable (Action, inout State, Environment) -> Output

    public init(_ run: @escaping @Sendable (Action, inout State, Environment) -> Output)
    {
        self.run = run
    }

    // MARK: - Contravariant Functor

    /// Transforms `Action`.
    public func contramap<GlobalAction>(
        action toLocalAction: @escaping @Sendable (GlobalAction) -> Action
    ) -> MealyReducer<GlobalAction, State, Environment, Output>
    {
        .init { action, state, environment in
            self.run(
                toLocalAction(action),
                &state,
                environment
            )
        }
    }

    /// Transforms `State` using `WritableKeyPath`.
    public func contramap<GlobalState>(
        state toLocalState: WritableKeyPath<GlobalState, State>
    ) -> MealyReducer<Action, GlobalState, Environment, Output>
    {
        .init { action, state, environment in
            self.run(
                action,
                &state[keyPath: toLocalState],
                environment
            )
        }
    }

    /// Transforms `Environment`.
    public func contramap<GlobalEnvironment>(
        environment toLocalEnvironment: @escaping @Sendable (GlobalEnvironment) -> Environment
    ) -> MealyReducer<Action, State, GlobalEnvironment, Output>
    {
        .init { action, state, environment in
            self.run(
                action,
                &state,
                toLocalEnvironment(environment)
            )
        }
    }

    // MARK: - Functor

    /// Changes `Output`.
    public func map<Output2>(output f: @escaping @Sendable (Output) -> Output2)
        -> MealyReducer<Action, State, Environment, Output2>
    {
        .init { action, state, environment in
            let output = self.run(action, &state, environment)
            return f(output)
        }
    }
}
