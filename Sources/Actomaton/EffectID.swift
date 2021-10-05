/// Effect identifier for manual cancellation via `Effect.cancel`.
public typealias EffectID = AnyHashable

/// A protocol that every effect-identifier should conform to.
public protocol EffectIDProtocol: Hashable {}
