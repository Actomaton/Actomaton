/// A protocol that every effect-identifier should conform to.
public protocol EffectIDProtocol: Hashable, Sendable {}

/// Default anonymous efffect.
internal struct DefaultEffectID: EffectIDProtocol {}
