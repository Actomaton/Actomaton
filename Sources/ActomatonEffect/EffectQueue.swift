/// A protocol that every effect queue should conform to, for automatic cancellation of existing tasks or suspending of
/// new effects.
///
/// Queue bookkeeping is scoped to an effect's **own work** (its single/sequence
/// execution): the slot is released — and `runNewest` eviction strikes — when the
/// effect itself completes, NOT when its `tracksFeedbacks` descendant chain settles.
/// The descendant chain remains tracked by `SendResults` (stream lifetime and
/// `cancel()` teardown), so recursive feedback chains can safely route every
/// generation through the same queue.
public protocol EffectQueue: Hashable, Sendable
{
    /// Effect buffering policy.
    var effectQueuePolicy: EffectQueuePolicy { get }

    /// Effect delaying strategy.
    var effectQueueDelay: EffectQueueDelay { get }
}

extension EffectQueue
{
    public var effectQueueDelay: EffectQueueDelay
    {
        .constant(0) // Default is "no delay".
    }
}

// MARK: - Newest1EffectQueue

/// A helper protocol where `effectQueuePolicy` is set to `.runNewest(maxCount: 1)`.
public protocol Newest1EffectQueue: EffectQueue {}

extension Newest1EffectQueue
{
    public var effectQueuePolicy: EffectQueuePolicy
    {
        .runNewest(maxCount: 1)
    }
}

// MARK: - Oldest1DiscardNewEffectQueue

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .discardNew)`.
public protocol Oldest1DiscardNewEffectQueue: EffectQueue {}

extension Oldest1DiscardNewEffectQueue
{
    public var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: 1, .discardNew)
    }
}

// MARK: - Oldest1SuspendNewEffectQueue

/// A helper protocol where `effectQueuePolicy` is set to `.runOldest(maxCount: 1, .suspendNew)`.
public protocol Oldest1SuspendNewEffectQueue: EffectQueue {}

extension Oldest1SuspendNewEffectQueue
{
    public var effectQueuePolicy: EffectQueuePolicy
    {
        .runOldest(maxCount: 1, .suspendNew)
    }
}
