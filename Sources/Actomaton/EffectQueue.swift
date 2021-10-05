/// Effect queue for automatic cancellation of existing tasks or suspending of new effects.
public typealias EffectQueue = AnyHashable

/// A protocol that every effect queue should conform to, for automatic cancellation of existing tasks or suspending of new effects.
public protocol EffectQueueProtocol: Hashable
{
    var effectQueuePolicy: EffectQueuePolicy { get }
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

// MARK: - Internals

struct AnyEffectQueue: EffectQueueProtocol
{
    let queue: EffectQueue
    let effectQueuePolicy: EffectQueuePolicy

    init<Queue>(_ queue: Queue)
        where Queue: EffectQueueProtocol
    {
        self.queue = queue
        self.effectQueuePolicy = queue.effectQueuePolicy
    }
}
