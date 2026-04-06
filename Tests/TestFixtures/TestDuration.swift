import Foundation

/// Test-only duration unit backed by "ticks".
///
/// One tick is currently 50 ms.
public struct TestDuration: Sendable, Hashable
{
    public let ticks: Ticks

    private init(
        ticks: Ticks
    )
    {
        self.ticks = ticks
    }

    public static func ticks(
        _ ticks: Ticks
    ) -> Self
    {
        Self(ticks: ticks)
    }

    public var timeInterval: TimeInterval
    {
        self.ticks * oneTickTimeInterval
    }

    internal var duration: Duration
    {
        .nanoseconds(Int64((Double(oneTickNanoseconds) * self.ticks).rounded()))
    }

    public typealias Ticks = Double
}

public func + (
    lhs: TestDuration,
    rhs: TestDuration
) -> TestDuration
{
    .ticks(lhs.ticks + rhs.ticks)
}

public func * (
    lhs: TestDuration,
    rhs: TimeInterval
) -> TestDuration
{
    .ticks(lhs.ticks * rhs)
}

public func * (
    lhs: TimeInterval,
    rhs: TestDuration
) -> TestDuration
{
    rhs * lhs
}

private let oneTickNanoseconds: UInt64 = 50_000_000 // 50 ms
private let oneTickTimeInterval: TimeInterval = .init(oneTickNanoseconds) / 1_000_000_000
