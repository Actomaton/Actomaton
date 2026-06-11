// MARK: - Outcome

extension Effect
{
    /// What an async (`.single` / `.sequence` / `.stream`) step produces in a single emission.
    ///
    /// - `action`: re-feed `Action` into the reducer; no side-channel emission.
    /// - `emit`: emit `Emission` to the caller's result stream; no reducer feedback.
    /// - `both`: do both atomically in the same step.
    public enum Outcome
    {
        case action(Action)
        case emission(Emission)
        case both(Action, Emission)

        /// Returns the action half (if any).
        public var action: Action?
        {
            switch self {
            case let .action(action), let .both(action, _):
                return action
            case .emission:
                return nil
            }
        }

        /// Returns the emitted value (if any).
        public var emission: Emission?
        {
            switch self {
            case let .emission(emission), let .both(_, emission):
                return emission
            case .action:
                return nil
            }
        }
    }
}

extension Effect.Outcome: Sendable where Action: Sendable, Emission: Sendable {}

// MARK: - Outcome mapping (internal)

extension Effect.Outcome
{
    internal func map<Action2>(action f: (Action) -> Action2) -> Effect<Action2, Emission>.Outcome
    {
        switch self {
        case let .action(action):
            return .action(f(action))
        case let .emission(value):
            return .emission(value)
        case let .both(action, value):
            return .both(f(action), value)
        }
    }

    internal func map<Emission2>(emission f: (Emission) -> Emission2) -> Effect<Action, Emission2>.Outcome
    {
        switch self {
        case let .action(action):
            return .action(action)
        case let .emission(value):
            return .emission(f(value))
        case let .both(action, value):
            return .both(action, f(value))
        }
    }
}
