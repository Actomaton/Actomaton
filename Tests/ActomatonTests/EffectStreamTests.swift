import Actomaton
import XCTest

/// Tests for `Effect.stream`.
final class EffectStreamTests: MainTestCase
{
    private var flags = Flags()

    private actor Flags
    {
        var didCancel = false
        var didCancelPrevious = false

        func markCancelled() { didCancel = true }
        func markPreviousCancelled() { didCancelPrevious = true }
    }

    override func setUp() async throws
    {
        flags = Flags()
    }

    // MARK: - stream (no id, no queue)

    func test_stream_emitsMultipleActions() async throws
    {
        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    return .stream { send, context in
                        for _ in 0 ..< 3 {
                            try await context.clock.sleep(for: .ticks(1))
                            send(.tick)
                        }
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .empty
                }
            },
            effectContext: effectContext
        )

        assertEqual(await actomaton.state, 0)

        await actomaton.send(.start)
        assertEqual(await actomaton.state, 0)

        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 1)

        await clock.advance(by: .ticks(1))
        assertEqual(await actomaton.state, 2)

        await clock.advance(by: .ticks(1))
        assertEqual(await actomaton.state, 3)

        await clock.advance(by: .ticks(5))
        assertEqual(
            await actomaton.state,
            3,
            "Closure already finished, so no more ticks."
        )
    }

    // MARK: - stream (id)

    /// Also exercises the `onTermination → task.cancel()` path: cancelling the effect
    /// terminates the underlying `AsyncThrowingStream`, which propagates `CancellationError`
    /// into the producer closure via `task.cancel()`.
    func test_stream_id_canBeCancelledById() async throws
    {
        struct TimerID: EffectID {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case .start:
                    return .stream(id: TimerID()) { send, context in
                        do {
                            while true {
                                try await context.clock.sleep(for: .ticks(1))
                                send(.tick)
                            }
                        }
                        catch is CancellationError {
                            await flags.markCancelled()
                            throw CancellationError()
                        }
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .cancel(id: TimerID())
                }
            },
            effectContext: effectContext
        )

        await actomaton.send(.start)

        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 1)

        await clock.advance(by: .ticks(1))
        assertEqual(await actomaton.state, 2)

        await actomaton.send(.stop)

        await clock.advance(by: .ticks(5))
        assertEqual(
            await actomaton.state,
            2,
            "Should not increment because stream is cancelled."
        )

        let didCancel = await flags.didCancel
        XCTAssertTrue(
            didCancel,
            "Inner closure should observe CancellationError when stream is cancelled."
        )
    }

    // MARK: - stream (queue)

    func test_stream_queue_autoCancelsPreviousStream() async throws
    {
        struct TestNewest1Queue: Newest1EffectQueue {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case .start:
                    return .stream(queue: TestNewest1Queue()) { send, context in
                        do {
                            while true {
                                try await context.clock.sleep(for: .ticks(1))
                                send(.tick)
                            }
                        }
                        catch is CancellationError {
                            await flags.markPreviousCancelled()
                            throw CancellationError()
                        }
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .empty
                }
            },
            effectContext: effectContext
        )

        await actomaton.send(.start)

        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 1)

        // Start a new stream — previous one should be auto-cancelled by `Newest1EffectQueue`.
        await actomaton.send(.start)

        // Give the queue a moment to swap streams.
        await settle()

        let didCancelPrevious = await flags.didCancelPrevious
        XCTAssertTrue(
            didCancelPrevious,
            "Previous stream should be cancelled by Newest1EffectQueue."
        )

        // New stream continues to emit.
        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 2)

        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 3)
    }

    // MARK: - stream (id + queue)

    func test_stream_idAndQueue_canBeCancelledById() async throws
    {
        struct TimerID: EffectID {}
        struct TestNewest1Queue: Newest1EffectQueue {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case .start:
                    return .stream(id: TimerID(), queue: TestNewest1Queue()) { send, context in
                        do {
                            while true {
                                try await context.clock.sleep(for: .ticks(1))
                                send(.tick)
                            }
                        }
                        catch is CancellationError {
                            await flags.markCancelled()
                            throw CancellationError()
                        }
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .cancel(id: TimerID())
                }
            },
            effectContext: effectContext
        )

        await actomaton.send(.start)

        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 1)

        await actomaton.send(.stop)
        await clock.advance(by: .ticks(5))

        assertEqual(
            await actomaton.state,
            1,
            "Should not increment because stream is cancelled."
        )

        let didCancel = await flags.didCancel
        XCTAssertTrue(didCancel)
    }

    // MARK: - continuation finish

    /// `autoFinish: true` — closure return finishes the stream, so the unified `send`
    /// task completes without explicit cancellation.
    func test_stream_autoFinishTrue_unifiedTaskCompletesWhenClosureReturns() async throws
    {
        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    return .stream(autoFinish: true) { send, context in
                        for _ in 0 ..< 2 {
                            try await context.clock.sleep(for: .ticks(1))
                            send(.tick)
                        }
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .empty
                }
            },
            effectContext: effectContext
        )

        let task = await actomaton.send(.start)
        XCTAssertNotNil(task)

        await clock.advance(by: .ticks(2.6))

        // Should NOT hang — `autoFinish: true` calls `continuation.finish()` on closure return.
        try await task?.value

        assertEqual(await actomaton.state, 2)
    }

    /// `autoFinish: false` — `send` captured into an outer reference (here a detached
    /// `Task`) can still emit `Action`s after the producer closure has returned.
    /// This is the long-lived-observer bridging pattern the docstring promises.
    func test_stream_autoFinishFalse_canEmitAfterClosureReturns() async throws
    {
        struct TimerID: EffectID {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { [clock] action, state, _ in
                switch action {
                case .start:
                    return .stream(id: TimerID()) { send, _ in
                        // Hand `send` off to a detached task, then return immediately.
                        // The continuation must stay open so the detached task can emit.
                        Task { @Sendable in
                            for _ in 0 ..< 3 {
                                try await clock.sleep(for: .ticks(1))
                                send(.tick)
                            }
                        }
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .cancel(id: TimerID())
                }
            },
            effectContext: effectContext
        )

        await actomaton.send(.start)

        await clock.advance(by: .ticks(1.3))
        assertEqual(await actomaton.state, 1)

        await clock.advance(by: .ticks(1))
        assertEqual(await actomaton.state, 2)

        await clock.advance(by: .ticks(1))
        assertEqual(
            await actomaton.state,
            3,
            "Detached task should keep emitting via `send` even after the producer closure returned."
        )

        await actomaton.send(.stop)
    }

    /// `autoFinish: false` (default) — closure return does NOT finish the stream,
    /// so the effect stays alive until explicitly cancelled.
    func test_stream_autoFinishFalse_keepsRunningAfterClosureReturns() async throws
    {
        struct TimerID: EffectID {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    return .stream(id: TimerID()) { send, context in
                        for _ in 0 ..< 2 {
                            try await context.clock.sleep(for: .ticks(1))
                            send(.tick)
                        }
                        // Closure returns here — but stream stays open because `autoFinish` is false.
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .cancel(id: TimerID())
                }
            },
            effectContext: effectContext
        )

        let task = await actomaton.send(.start)
        XCTAssertNotNil(task)

        await clock.advance(by: .ticks(2.6))
        assertEqual(await actomaton.state, 2)

        // Stream did not finish on its own — `task.value` would hang here.
        XCTAssertFalse(task?.isCancelled ?? true)

        // Explicit cancellation is required to complete the effect.
        await actomaton.send(.stop)

        do {
            try await task?.value
        }
        catch is CancellationError {
            // Cancellation is one acceptable outcome.
        }

        assertEqual(await actomaton.state, 2)
    }

    /// Verifies that the underlying `AsyncThrowingStream` continuation finishes
    /// with the thrown error, so the unified `send` task rethrows that error
    /// (rather than hanging on the inner `for try await` loop).
    func test_stream_unifiedTaskRethrowsClosureError() async throws
    {
        struct StreamError: Error, Equatable {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    return .stream { send, context in
                        try await context.clock.sleep(for: .ticks(1))
                        send(.tick)
                        throw StreamError()
                    }
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .empty
                }
            },
            effectContext: effectContext
        )

        let task = await actomaton.send(.start)
        XCTAssertNotNil(task)

        await clock.advance(by: .ticks(1.3))

        do {
            try await task?.value
            XCTFail("Should rethrow StreamError from the closure.")
        }
        catch is StreamError {
            // Expected — `continuation.finish(throwing:)` propagated the error.
        }

        assertEqual(await actomaton.state, 1)
    }
}

// MARK: - Private

private enum Action
{
    case start
    case tick
    case stop
}

private typealias State = Int
