import Clocks
import Foundation

/// Runtime-owned effect execution context.
///
/// `EffectContext` complements reducer `Environment` instead of replacing it.
/// - Use `Environment` for domain dependencies such as API clients and repositories.
/// - Use `EffectContext` for runtime capabilities such as sleeping with a replaceable clock and cancellation checks.
public struct EffectContext: Sendable
{
    public let clock: AnyClock<Duration>

    public init<C>(
        clock: C
    )
        where C: Clock, C.Duration == Duration
    {
        self.clock = AnyClock(clock)
    }
}
