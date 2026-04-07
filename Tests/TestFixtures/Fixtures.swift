import Clocks
import XCTest

// MARK: - Clock.advance(by: TestDuration)

extension TestClock where Duration == Swift.Duration
{
    public func advance(
        by duration: TestDuration
    ) async
    {
        await self.advance(by: duration.duration)
    }
}

extension ContinuousClock
{
    public func advance(
        by duration: TestDuration
    ) async
    {
        try? await self.sleep(for: duration.duration)
    }
}

// MARK: - Clock.sleep(for: TestDuration)

extension Clock where Duration == Swift.Duration
{
    public func sleep(
        for duration: TestDuration
    ) async throws
    {
        try await self.sleep(for: duration.duration)
    }

    public func sleep<T>(
        for duration: TestDuration,
        ifSucceeded: () async throws -> T,
        ifCancelled: () async throws -> T
    ) async throws -> T
    {
        do {
            try await self.sleep(for: duration.duration)
            return try await ifSucceeded()
        }
        catch is CancellationError {
            return try await ifCancelled()
        }
    }
}

// MARK: - Clock.sleep(until: TestDuration)

extension Clock where Duration == Swift.Duration
{
    public func sleep(
        until duration: TestDuration,
        tolerance: Duration? = nil
    ) async throws
    {
        let deadline = self.now.advanced(by: duration.duration)
        try await self.sleep(until: deadline, tolerance: tolerance)
    }
}

// MARK: - settle

public func settle(
    yields: Int = 10
) async
{
    for _ in 0 ..< yields {
        await Task.yield()
    }
}

// MARK: - Assert

public func assertEqual<T>(
    _ expression1: T,
    _ expression2: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) where T: Equatable
{
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

// MARK: - ResultsCollector

public actor ResultsCollector <T>
{
    public private(set) var results: [T] = []

    public init() {}

    public func append(_ value: T)
    {
        results.append(value)
    }
}
