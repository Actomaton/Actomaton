import XCTest

// MARK: - Tick

/// - Note: For safe async testing, leeway should have at least 50 millisec (30 millsec isn't enough for MacBook Pro (15-inch, 2018)).
func tick(_ n: Double) async
{
    await Task.sleep(UInt64(Double(tickTimeInterval) * n))
}

private let tickTimeInterval: UInt64 = 50_000_000 // 50 ms

// MARK: - Assert

func assertEqual<T>(
    _ expression1: T,
    _ expression2: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) where T : Equatable
{
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

// MARK: - ResultsCollector

actor ResultsCollector<T>
{
    var results: [T] = []

    func append(_ value: T)
    {
        results.append(value)
    }
}
