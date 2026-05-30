import ActomatonCore

/// ``Effect`` exposes synchronous feedback as ``Effect/Kind/next`` kinds. Conforming to
/// ``MealyOutput`` lets ``MealyMachine`` drive the synchronous-feedback loop directly,
/// without going through an ``EffectManager``.
///
/// Synchronous side-channel emissions (``Effect/Kind/emit``) are NOT consumed by the
/// recursion; they ride along in the remainder so that the downstream ``EffectManager``
/// can deliver them to the caller's top-level result stream.
extension Effect: MealyOutput
{
    public func splitSynchronousActions() -> (actions: [Action], remainder: Effect<Action, Emission>)
    {
        var actions: [Action] = []
        var remainingKinds: [Effect<Action, Emission>.Kind] = []

        for kind in kinds {
            switch kind {
            case let .next(action):
                actions.append(action)
            case .single, .sequence, .emission, .cancel, .updateQueue:
                remainingKinds.append(kind)
            }
        }

        return (actions: actions, remainder: Effect(kinds: remainingKinds))
    }

    // `static func + (lhs:rhs:)` is already provided by `Effect`'s monoid extension.
}

/// ``Effect`` exposes its side-channel value type via ``EffectOutput`` so that
/// ``EffectManager`` can carry it as a single `Output: EffectOutput` constraint —
/// `Output.Emission` is derived from the concrete `Effect`'s second generic parameter.
extension Effect: EffectOutput {}
