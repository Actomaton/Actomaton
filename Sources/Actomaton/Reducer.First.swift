extension Reducer
{
    /// A composable, `State`-transforming function wrapper that is triggered by `Action`.
    ///
    /// - Note:
    /// This alternative reducer type allows `Reducer.First.combine` as "Run first reducer only" operation until returning `Effect?.some()`.
    /// In case of `Effect?.none` (`nil`), `Reducer.First.combine`will run next reducers until some effect will match.
    public struct First
    {
        public let run: (Action, inout State, Environment) -> Effect<Action>?

        /// - Note: Returns effect as `Optional`.
        public init(_ run: @escaping (Action, inout State, Environment) -> Effect<Action>?)
        {
            self.run = run
        }

        // MARK: - Lift from Reducer

        /// Lifts `Reducer` into `Reducer.First`, treating `Effect.empty` as a non-terminal of running reducer in `Reducer.First.combine`.
        /// - Note: `Effect.empty` will be treated as `Reducer.First?.none`.
        public static func lift(reducer: Reducer) -> Reducer.First
        {
            .init { action, state, environment in
                let effect = reducer.run(action, &state, environment)

                // Treat `Effect.empty` as `Reducer.First?.none`,
                // which allows next reducers to be run.
                return effect.kinds.isEmpty ? nil : effect
            }
        }

        /// Lifts `Reducer` into `Reducer.First`, treating `Effect.empty` as a terminal of running reducer in `Reducer.First.combine`.
        ///
        /// - Note:
        ///   `Effect.empty` will be treated as `Reducer.First?.some(.empty)`,
        ///   which will terminate the consecutive runs in `Reducer.First.combine`.
        public static func liftAsTerminal(reducer: Reducer) -> Reducer.First
        {
            .init { action, state, environment in
                reducer.run(action, &state, environment)
            }
        }

        // MARK: - Lower to Reducer

        public func lower() -> Reducer
        {
            .init { action, state, environment in
                self.run(action, &state, environment) ?? .empty
            }
        }

        // MARK: - First Monoid

        public static var empty: Reducer.First
        {
            .init { _, _, _ in nil }
        }

        public static func + (l: Reducer.First, r: Reducer.First) -> Reducer.First
        {
            .init { action, state, environment in
                if let effect = l.run(action, &state, environment) {
                    return effect
                }
                else {
                    return r.run(action, &state, environment)
                }
            }
        }

        public static func combine(_ reducers: [Reducer.First]) -> Reducer.First
        {
            .init { action, state, environment in
                for reducer in reducers {
                    if let effect = reducer.run(action, &state, environment) {
                        return effect
                    }
                }
                return .empty
            }
        }

        public static func combine(_ reducers: Reducer.First...) -> Reducer.First
        {
            self.combine(reducers)
        }
    }
}
