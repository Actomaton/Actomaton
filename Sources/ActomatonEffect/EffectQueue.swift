/// Effect queue for automatic cancellation of existing tasks or suspending of new effects.
public struct EffectQueue: Hashable, Sendable
{
    /// Raw value that conforms to `EffectQueueProtocol`.
    public let value: any EffectQueueProtocol

    internal init(_ value: some EffectQueueProtocol)
    {
        self.value = value
    }

    internal init(_ value: any EffectQueueProtocol)
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

/// A protocol that every effect queue should conform to, for automatic cancellation of existing tasks or suspending of
/// new effects.
public protocol EffectQueueProtocol: Hashable, Sendable
{
    /// Effect buffering policy.
    var effectQueuePolicy: EffectQueuePolicy { get }

    /// Effect delaying strategy.
    var effectQueueDelay: EffectQueueDelay { get }
}

extension EffectQueueProtocol
{
    public var effectQueueDelay: EffectQueueDelay
    {
        .constant(0) // Default is "no delay".
    }
}

// MARK: - Newest1EffectQueueProtocol

/// A helper protocol where `effectQueuePolicy` is set to `.runNewest(maxCount: 1)`.
public protocol Newest1EffectQueueProtocol: EffectQueueProtocol {}

extension Newest1EffectQueueProtocol
{
    public var effectQueuePolicy: EffectQueuePolicy
    {
        .runNewest(maxCount: 1)
    }
}

// MARK: - Oldest1DiscardNewEffectQueueProtocol

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .discardNew)`.
public protocol Oldest1DiscardNewEffectQueueProtocol: EffectQueueProtocol {}

extension Oldest1DiscardNewEffectQueueProtocol
{
    public var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: 1, .discardNew)
    }
}

// MARK: - Oldest1SuspendNewEffectQueueProtocol

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .suspendNew)`.
public protocol Oldest1SuspendNewEffectQueueProtocol: EffectQueueProtocol {}

extension Oldest1SuspendNewEffectQueueProtocol
{
    public var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: 1, .suspendNew)
    }
}
