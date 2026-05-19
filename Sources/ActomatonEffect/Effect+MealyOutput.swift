import ActomatonCore

/// ``Effect`` exposes synchronous feedback as ``Effect/Kind/next`` kinds. Conforming to
/// ``MealyOutput`` lets ``MealyMachine`` drive the synchronous-feedback loop directly,
/// without going through an ``EffectManager``.
extension Effect: MealyOutput
{
    public func splitSynchronousActions() -> (actions: [Action], remainder: Effect<Action>)
    {
        var actions: [Action] = []
        var remainingKinds: [Effect<Action>.Kind] = []

        for kind in kinds {
            if case let .next(action) = kind {
                actions.append(action)
            }
            else {
                remainingKinds.append(kind)
            }
        }

        return (actions: actions, remainder: Effect(kinds: remainingKinds))
    }

    // `static func + (lhs:rhs:)` is already provided by `Effect`'s monoid extension.
}
