/// Effect identifier for manual cancellation via `Effect.cancel`.
public struct EffectID: Hashable, Sendable
{
    /// Raw value that conforms to `EffectIDProtocol`.
    public let value: any EffectIDProtocol

    internal init(_ value: some EffectIDProtocol)
    {
        self.value = value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool
    {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    public func hash(into hasher: inout Hasher)
    {
        AnyHashable(value).hash(into: &hasher)
    }
}

/// A protocol that every effect-identifier should conform to.
public protocol EffectIDProtocol: Hashable, Sendable {}

/// Default anonymous efffect.
internal struct DefaultEffectID: EffectIDProtocol {}
