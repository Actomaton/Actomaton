/// Effect queue for automatic cancellation of existing tasks or suspending of new effects.
struct _EffectQueue: Hashable, Sendable
{
    /// Raw value that conforms to `EffectQueueProtocol`.
    let value: any EffectQueueProtocol

    init(_ value: some EffectQueueProtocol)
    {
        self.value = value
    }

    init(_ value: any EffectQueueProtocol)
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
