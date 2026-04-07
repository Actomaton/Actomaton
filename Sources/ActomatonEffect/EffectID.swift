/// A protocol that every effect-identifier should conform to.
public protocol EffectID: Hashable, Sendable {}

/// Default anonymous effect.
internal struct DefaultEffectID: EffectID {}
