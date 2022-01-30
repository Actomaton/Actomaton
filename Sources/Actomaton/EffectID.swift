/// Effect identifier for manual cancellation via `Effect.cancel`.
public struct EffectID: Hashable, Sendable
{
    private let _value: AnySendableHashable

    internal init<Value>(_ value: Value) where Value: Hashable & Sendable
    {
        self._value = AnySendableHashable(value)
    }

    /// Raw value that conforms to `EffectIDProtocol`.
    public var value: AnyHashable
    {
        _value.value
    }
}

/// A protocol that every effect-identifier should conform to.
public protocol EffectIDProtocol: Hashable, Sendable {}

/// Default anonymous efffect.
internal struct DefaultEffectID: EffectIDProtocol {}
