import Actomaton
import XCTest

/// Tests for `Effect.cancel`.
final class TimerTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    override func setUp() async throws
    {
        struct TimerID: EffectID {}

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    let timerEffect = Effect.sequence(id: TimerID()) { context in
                        AsyncStream<()> { continuation in
                            let task = Task {
                                while true {
                                    try await context.clock.sleep(for: .ticks(2))
                                    continuation.yield(())
                                }
                            }

                            continuation.onTermination = { @Sendable _ in
                                task.cancel()
                            }
                        }
                        .map { Action.tick }
                    }
                    return timerEffect
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .cancel(id: TimerID())
                }
            },
            effectContext: effectContext
        )
        self.actomaton = actomaton
    }

    func test_timer() async throws
    {
        assertEqual(await actomaton.state, 0)

        await actomaton.send(.start)

        assertEqual(await actomaton.state, 0)

        await clock.advance(by: .ticks(2.3))
        assertEqual(await actomaton.state, 1)

        await clock.advance(by: .ticks(2.3))
        assertEqual(await actomaton.state, 2)

        await clock.advance(by: .ticks(2.3))
        assertEqual(await actomaton.state, 3)

        await actomaton.send(.stop)

        await clock.advance(by: .ticks(3))
        assertEqual(
            await actomaton.state,
            3,
            "Should not increment because timer is stopped."
        )
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
