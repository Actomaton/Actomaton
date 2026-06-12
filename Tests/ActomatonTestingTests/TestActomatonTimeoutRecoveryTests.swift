#if canImport(ObjectiveC) // `XCTExpectFailure` is unavailable in swift-corelibs-xctest (Linux / Wasm).

import ActomatonCore
import ActomatonEffect
import ActomatonTesting
import TestFixtures
import XCTest

/// End-to-end regression test for the `AsyncSignal` migration:
/// a `receive` timeout must NOT break the signal mechanism for subsequent
/// `receive` calls on the same `TestActomaton`.
///
/// With the previous `AsyncStream`-based signal, the timeout's task-group
/// cancellation terminated the stream permanently, so later `receive` calls
/// could no longer wait for feedback and failed spuriously.
final class TestActomatonTimeoutRecoveryTests: MainTestCase
{
    func test_receiveTimeout_doesNotBreakSubsequentReceive() async
    {
        typealias Reducer = MealyReducer<PingPongAction, PingPongState, Void, Effect<PingPongAction, Never>>

        let testActomaton = TestActomaton(
            state: PingPongState(),
            reducer: Reducer { action, state, _ in
                switch action {
                case .ping:
                    state.isPinged = true
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(2))
                        return .pong
                    }
                case .pong:
                    state.isPonged = true
                    return .empty
                }
            },
            environment: (),
            effectContext: effectContext
        )

        _ = await testActomaton.send(.ping) { state in
            state.isPinged = true
        }

        // 1st receive: the effect is still sleeping on the clock (2 ticks = 100 ms real,
        // or suspended indefinitely under `TEST_CLOCK=1`), so a 50 ms timeout always fires.
        //
        // The expected-failure matcher is narrowed to THIS timeout's message ("0.05 seconds")
        // so that a spurious timeout of the 2nd receive (1 second) below would still surface
        // as a genuine failure instead of being masked.
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.compactDescription.contains("0.05 seconds")
        }
        XCTExpectFailure("First receive times out by design.", options: options)

        await testActomaton.receive(.pong, timeout: .milliseconds(50))

        // Drive the clock so the effect completes and feeds back `.pong`.
        await clock.advance(by: .ticks(2))

        // 2nd receive must still be able to wait for and consume the feedback.
        await testActomaton.receive(.pong) { state in
            state.isPonged = true
        }
    }
}

// MARK: - Private

private enum PingPongAction: Equatable, Sendable
{
    case ping
    case pong
}

private struct PingPongState: Equatable, Sendable
{
    var isPinged = false
    var isPonged = false
}

#endif
