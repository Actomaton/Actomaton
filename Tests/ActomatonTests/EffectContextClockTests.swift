@testable import Actomaton
import XCTest

final class EffectContextClockTests: XCTestCase
{
    func test_sleep_for_uses_injected_clock() async throws
    {
        let recorder = Recorder()
        let clock = RecordingClock(recorder: recorder)

        let actomaton = Actomaton<Action, State>(
            state: .idle,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    state = .running
                    return Effect { context in
                        try await context.clock.sleep(for: .seconds(1))
                        return .finished
                    }

                case .finished:
                    state = .finished
                    return .empty
                }
            },
            effectContext: EffectContext(clock: clock)
        )

        let task = await actomaton.send(.start)
        try await task?.value

        assertEqual(await actomaton.state, .finished)
        assertEqual(await recorder.durations, [.seconds(1)])
    }

    func test_sleep_until_uses_injected_clock() async throws
    {
        let recorder = Recorder()
        let clock = RecordingClock(recorder: recorder)

        let actomaton = Actomaton<Action, State>(
            state: .idle,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    state = .running
                    return Effect { context in
                        let deadline = context.clock.now.advanced(by: .seconds(2))
                        try await context.clock.sleep(until: deadline, tolerance: nil)
                        return .finished
                    }

                case .finished:
                    state = .finished
                    return .empty
                }
            },
            effectContext: EffectContext(clock: clock)
        )

        let task = await actomaton.send(.start)
        try await task?.value

        assertEqual(await actomaton.state, .finished)
        assertEqual(await recorder.durations, [.seconds(2)])
    }
}

// MARK: - Private

private enum Action
{
    case start
    case finished
}

private enum State
{
    case idle
    case running
    case finished
}

private actor Recorder
{
    var durations: [Duration] = []

    func append(_ duration: Duration)
    {
        self.durations.append(duration)
    }
}

private struct RecordingClock: Clock
{
    struct Instant: InstantProtocol
    {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant
        {
            Instant(offset: self.offset + duration)
        }

        func duration(to other: Instant) -> Duration
        {
            other.offset - self.offset
        }

        static func < (l: Instant, r: Instant) -> Bool
        {
            l.offset < r.offset
        }
    }

    let recorder: Recorder

    var now: Instant
    {
        Instant(offset: .zero)
    }

    var minimumResolution: Duration
    {
        .zero
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws
    {
        await self.recorder.append(self.now.duration(to: deadline))
    }
}
