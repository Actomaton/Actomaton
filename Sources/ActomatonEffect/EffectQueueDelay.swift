import Foundation

/// ``EffectQueueProtocol``'s  delaying strategy.
public enum EffectQueueDelay: Hashable, Sendable
{
    case constant(TimeInterval)
    case random(ClosedRange<TimeInterval>)

    var timeInterval: TimeInterval
    {
        switch self {
        case let .constant(timeInterval):
            return timeInterval
        case let .random(timeRange):
            return TimeInterval.random(in: timeRange)
        }
    }

    var duration: Duration
    {
        .nanoseconds(
            Int64(self.timeInterval * 1_000_000_000)
        )
    }
}
