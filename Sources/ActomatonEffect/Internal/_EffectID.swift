/// Effect identifier for manual cancellation via `Effect.cancel`.
struct _EffectID: Hashable, Sendable
{
    /// Raw value that conforms to `EffectID`.
    let value: any EffectID

    init(_ value: some EffectID)
    {
        self.value = value
    }

    static func == (lhs: Self, rhs: Self) -> Bool
    {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    func hash(into hasher: inout Hasher)
    {
        AnyHashable(value).hash(into: &hasher)
    }
}
