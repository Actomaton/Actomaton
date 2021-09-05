import XCTest

// MARK: - Tick

/// - Note: For safe async testing, leeway should have at least 3 millisec.
func tick(_ n: Double) async
{
    await Task.sleep(UInt64(Double(tickTimeInterval) * n))
}

private let tickTimeInterval: UInt64 = 10_000_000 // 10 ms

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

// MARK: - DebugLog

enum Debug
{
    static func print(_ msg: Any)
    {
#if DEBUG
        Swift.print(msg)
#endif
    }
}

