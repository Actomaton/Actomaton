/// `EffectQueueProtocol`'s buffering policy.
public enum EffectQueuePolicy: Hashable, Sendable
{
    /// Runs `maxCount` newest effects, cancelling old running effects.
    case runNewest(maxCount: Int)

    /// Runs `maxCount` old effects with either suspending or discarding new effects.
    case runOldest(maxCount: Int, OverflowPolicy)

    public enum OverflowPolicy: Sendable
    {
        /// Suspends new effects when `.runOldest` `maxCount` of old effects is reached until one of them is completed.
        case suspendNew

        /// Discards new effects when `.runOldest` `maxCount` of old effects is reached until one of them is completed.
        case discardNew
    }
}
