import Actomaton
import Clocks
import XCTest

final class EffectContextClockTests: XCTestCase
{
    func test_sleep_for_uses_injected_clock() async throws
    {
        let clock = TestClock<Duration>()

        let actomaton = Actomaton<Action, State, Never>(
            state: .idle,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    state = .running
                    return Effect { context in
                        try await context.clock.sleep(for: .ticks(1))
                        return .finished
                    }

                case .finished:
                    state = .finished
                    return .empty
                }
            },
            effectContext: EffectContext(clock: clock)
        )

        let results = await actomaton.send(.start)
        assertEqual(await actomaton.state, .running)

        await clock.advance(by: .ticks(1))
        await results.completion

        assertEqual(await actomaton.state, .finished)
    }

    func test_sleep_until_uses_injected_clock() async throws
    {
        let clock = TestClock<Duration>()

        let actomaton = Actomaton<Action, State, Never>(
            state: .idle,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    state = .running
                    return Effect { context in
                        try await context.clock.sleep(until: .ticks(2))
                        return .finished
                    }

                case .finished:
                    state = .finished
                    return .empty
                }
            },
            effectContext: EffectContext(clock: clock)
        )

        let results = await actomaton.send(.start)
        assertEqual(await actomaton.state, .running)

        await clock.advance(by: .ticks(2))
        await results.completion

        assertEqual(await actomaton.state, .finished)
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
