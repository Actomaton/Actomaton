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
    public mutating func splitSynchronousActions() -> [Action]
    {
        var actions: [Action] = []

        self.kinds.removeAll { kind in
            switch kind {
            case let .next(action):
                actions.append(action)
                return true

            case .single, .sequence, .emission, .cancel, .updateQueue:
                return false
            }
        }

        return actions
    }

    // `append(_:)` is provided by `Effect`'s monoid extension.
}

/// ``Effect`` exposes its side-channel value type via ``EffectOutput`` so that
/// ``EffectManager`` can carry it as a single `Output: EffectOutput` constraint —
/// `Output.Emission` is derived from the concrete `Effect`'s second generic parameter.
extension Effect: EffectOutput {}
