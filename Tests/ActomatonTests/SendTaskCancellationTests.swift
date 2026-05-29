import Actomaton
import XCTest

/// Tests that calling `task.cancel()` on the `Task` returned from
/// ``Actomaton/send(_:priority:tracksFeedbacks:)`` properly cancels all tracked,
/// in-flight feedback-loop effects.
final class SendTaskCancellationTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    private var flags = Flags()

    private func setupActomaton(initialState: State) async
    {
        let actomaton = Actomaton<Action, State>(
            state: initialState,
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case ._1To2:
                    guard state == ._1 else { return .empty }
                    state = ._2
                    return Effect { context in
                        return try await context.clock.sleep(for: .ticks(1)) {
                            return ._2To3
                        } ifCancelled: {
                            Debug.print("_1To2 cancelled")
                            await flags.mark(cancelled1To2: true)
                            return nil
                        }
                    }

                case ._2To3:
                    guard state == ._2 else { return .empty }
                    state = ._3
                    return Effect { context in
                        return try await context.clock.sleep(for: .ticks(1)) {
                            return ._3To4
                        } ifCancelled: {
                            Debug.print("_2To3 cancelled")
                            await flags.mark(cancelled2To3: true)
                            return nil
                        }
                    }

                case ._3To4:
                    guard state == ._3 else { return .empty }
                    state = ._4
                    return Effect { context in
                        return try await context.clock.sleep(for: .ticks(1)) {
                            return nil
                        } ifCancelled: {
                            Debug.print("_3To4 cancelled")
                            await flags.mark(cancelled3To4: true)
                            return nil
                        }
                    }

                case ._startSeq:
                    guard state == ._1 else { return .empty }
                    state = ._2
                    return Effect.sequence { context in
                        AsyncStream<Action> { continuation in
                            let task = Task<(), any Error> {
                                try await context.clock.sleep(for: .ticks(1)) {
                                    continuation.yield(._seqInnerStep)
                                } ifCancelled: {
                                    Debug.print("seq outer cancelled")
                                }
                                continuation.finish()
                            }
                            continuation.onTermination = { @Sendable _ in
                                task.cancel()
                            }
                        }
                    }

                case ._seqInnerStep:
                    // Triggered from the sequence above. Schedules a follow-up
                    // single-effect that should be cancelled along with the
                    // returned tracked task.
                    state = ._3
                    return Effect { context in
                        return try await context.clock.sleep(for: .ticks(1)) {
                            return nil
                        } ifCancelled: {
                            Debug.print("seq inner cancelled")
                            await flags.mark(seqInnerCancelled: true)
                            return nil
                        }
                    }
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton
    }

    /// Cancelling the tracked task while a `single` feedback effect is still
    /// in-flight must propagate cancellation to that in-flight effect.
    func test_cancel_propagates_to_in_flight_single_feedback_effect() async throws
    {
        await setupActomaton(initialState: ._1)

        assertEqual(await actomaton.state, ._1)

        let task = await actomaton.send(._1To2, tracksFeedbacks: true)

        // Advance to mid-flight of `._2To3`'s effect:
        // - `._1To2`'s effect sleeps 1 tick, fires `._2To3`, state -> _3
        // - `._2To3`'s effect starts sleeping a fresh 1 tick
        await clock.advance(by: .ticks(1.5))
        assertEqual(await actomaton.state, ._3)

        // Cancel while `._2To3` is still in-flight.
        task?.cancel()
        _ = try? await task?.value

        // Advance well past every remaining sleep so the in-flight effect would
        // have completed had cancellation not propagated.
        await clock.advance(by: .ticks(10))

        // `._1To2`'s effect completed *before* the cancel, so its `ifCancelled`
        // must NOT have been called.
        let cancelled1To2 = await flags.cancelled1To2
        XCTAssertFalse(cancelled1To2, "`._1To2` already completed before cancel.")

        // `._2To3` was in-flight at cancel time — it MUST be cancelled.
        let cancelled2To3 = await flags.cancelled2To3
        XCTAssertTrue(
            cancelled2To3,
            "`._2To3`'s in-flight effect must be cancelled when the tracked Task is cancelled."
        )

        // `._3To4` never started — its `ifCancelled` must never run.
        let cancelled3To4 = await flags.cancelled3To4
        XCTAssertFalse(cancelled3To4, "`._3To4` never started.")

        // The state must remain at `._3` because `._2To3` was cut off before
        // it could fire `._3To4`.
        assertEqual(
            await actomaton.state,
            ._3,
            "State must stay at `._3` because `._2To3` was cancelled mid-flight."
        )
    }

    /// Cancelling the tracked task while the first effect is still in-flight
    /// must propagate cancellation to that effect.
    func test_cancel_propagates_to_first_effect() async throws
    {
        await setupActomaton(initialState: ._1)

        assertEqual(await actomaton.state, ._1)

        let task = await actomaton.send(._1To2, tracksFeedbacks: true)

        // `._1To2`'s effect is mid-flight (0.5 of 1 tick).
        await clock.advance(by: .ticks(0.5))
        assertEqual(await actomaton.state, ._2)

        task?.cancel()
        _ = try? await task?.value

        await clock.advance(by: .ticks(10))

        // `._1To2` was in-flight at cancel time and must be cancelled.
        let cancelled1To2 = await flags.cancelled1To2
        XCTAssertTrue(
            cancelled1To2,
            "`._1To2`'s in-flight effect must be cancelled when the tracked Task is cancelled."
        )

        // State must stay at `._2` because `._1To2` was cut off before it
        // could fire `._2To3`.
        assertEqual(
            await actomaton.state,
            ._2,
            "State must stay at `._2` because `._1To2` was cancelled mid-flight."
        )
    }

    /// Cancelling the tracked task whose first effect is a `sequence` must
    /// also cancel the in-flight follow-up `single` feedback effect spawned
    /// by it.
    func test_cancel_propagates_to_in_flight_sequence_feedback_effect() async throws
    {
        await setupActomaton(initialState: ._1)

        assertEqual(await actomaton.state, ._1)

        let task = await actomaton.send(._startSeq, tracksFeedbacks: true)

        // Advance until the sequence has emitted `._seqInnerStep` and the
        // follow-up single effect is mid-flight.
        await clock.advance(by: .ticks(1.5))
        assertEqual(await actomaton.state, ._3)

        task?.cancel()
        _ = try? await task?.value

        await clock.advance(by: .ticks(10))

        let seqInnerCancelled = await flags.seqInnerCancelled
        XCTAssertTrue(
            seqInnerCancelled,
            "The `single` feedback effect spawned by the sequence must be cancelled too."
        )
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case _1To2
    case _2To3
    case _3To4

    case _startSeq
    case _seqInnerStep
}

private enum State: Equatable, Sendable
{
    case _1
    case _2
    case _3
    case _4
}

private actor Flags
{
    var cancelled1To2 = false
    var cancelled2To3 = false
    var cancelled3To4 = false
    var seqInnerCancelled = false

    func mark(
        cancelled1To2: Bool? = nil,
        cancelled2To3: Bool? = nil,
        cancelled3To4: Bool? = nil,
        seqInnerCancelled: Bool? = nil
    )
    {
        if let cancelled1To2 {
            self.cancelled1To2 = cancelled1To2
        }
        if let cancelled2To3 {
            self.cancelled2To3 = cancelled2To3
        }
        if let cancelled3To4 {
            self.cancelled3To4 = cancelled3To4
        }
        if let seqInnerCancelled {
            self.seqInnerCancelled = seqInnerCancelled
        }
    }
}
