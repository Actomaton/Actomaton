import XCTest
@testable import Actomaton

#if canImport(Combine)
import Combine
#endif

/// Tests for `Effect.cancel`.
final class TimerTests: MainTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    override func setUp() async throws
    {
        struct TimerID: EffectIDProtocol {}

        let timerEffect = Effect(id: TimerID(), sequence: {
            AsyncStream<()> { continuation in
                let task = Task {
                    while true {
                        try await tick(1)
                        continuation.yield(())
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
            .map { Action.tick }
        })

        let actomaton = Actomaton<Action, State>(
            state: 0,
            reducer: Reducer { action, state, _ in
                switch action {
                case .start:
                    return timerEffect
                case .tick:
                    state += 1
                    return .empty
                case .stop:
                    return .cancel(id: TimerID())
                }
            }
        )
        self.actomaton = actomaton

#if canImport(Combine)
        var cancellables: [AnyCancellable] = []

        await actomaton.$state
            .sink(receiveValue: { state in
                Debug.print("publisher: state = \(state)")
            })
            .store(in: &cancellables)
#endif
    }

    func test_timer() async throws
    {
        assertEqual(await actomaton.state, 0)

        await actomaton.send(.start)

        assertEqual(await actomaton.state, 0)

        try await tick(1.3)
        assertEqual(await actomaton.state, 1)

        try await tick(1.3)
        assertEqual(await actomaton.state, 2)

        try await tick(1.3)
        assertEqual(await actomaton.state, 3)

        await actomaton.send(.stop)

        try await tick(3)
        assertEqual(await actomaton.state, 3,
                    "Should not increment because timer is stopped.")
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
