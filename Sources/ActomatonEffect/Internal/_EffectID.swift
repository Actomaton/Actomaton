/// Effect identifier for manual cancellation via `Effect.cancel`.
struct _EffectID: Hashable, Sendable
{
    /// Raw value that conforms to `EffectIDProtocol`.
    let value: any EffectIDProtocol

    init(_ value: some EffectIDProtocol)
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
