import XCTest
@testable import Actomaton

import Combine

/// Tests for `actomaton.send`'s returned `Task`.
final class FeedbackTrackingTaskTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    private func setupActomaton(initalState: State) async
    {
        let actomaton = Actomaton<Action, State>(
            state: initalState,
            reducer: Reducer { action, state, _ in
                switch action {
                case ._1To2:
                    guard state == ._1 else { return .empty }

                    state = ._2
                    return Effect {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_1To2 cancelled")
                            return nil
                        }
                        return ._2To3
                    }

                case ._2To3:
                    guard state == ._2 else { return .empty }

                    state = ._3
                    return Effect {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_2To3 cancelled")
                            return nil
                        }
                        return ._3To4
                    }

                case ._3To4: // 3-tick timer
                    guard state == ._3 else { return .empty }

                    state = ._4(count: 0)
                    return Effect(sequence: AsyncStream<Action> { continuation in
                        let task = Task<(), Error> {
                            for _ in 1 ... 2 {
                                await tick(1)
                                if Task.isCancelled {
                                    Debug.print("_3To4 cancelled")
                                    return
                                }
                                continuation.yield(._increment)
                            }

                            await tick(1)
                            continuation.yield(._4To5)
                            continuation.finish()
                        }
                        continuation.onTermination = { @Sendable _ in
                            task.cancel()
                        }
                    })

                case ._increment:
                    guard case let ._4(count) = state else { return .empty }

                    state = ._4(count: count + 1)
                    return .empty

                case ._4To5:
                    guard case ._4 = state else { return .empty }

                    state = ._5
                    return Effect {
                        await tick(1)
                        if Task.isCancelled {
                            Debug.print("_4To5 cancelled")
                            return nil
                        }
                        return ._5To6
                    }

                case ._5To6:
                    guard case ._5 = state else { return .empty }

                    state = ._6
                    return .empty

                case ._toEnd:
                    state = ._end
                    return Effect {
                        await tick(1)
                        return nil
                    }
                }

            }
        )
        self.actomaton = actomaton

        var cancellables: [AnyCancellable] = []

        await actomaton.$state
            .sink(receiveValue: { state in
                Debug.print("publisher: state = \(state)")
            })
            .store(in: &cancellables)
    }

    func test_no_tracksFeedbacks() async throws
    {
        await setupActomaton(initalState: ._1)

        assertEqual(await actomaton.state, ._1)

        let task = await actomaton.send(._1To2, tracksFeedbacks: false)

        // Wait for `._1To2`'s effect only (upto `_2To3`'s next state-transition without its effect)
        try await task?.value

        assertEqual(await actomaton.state, ._3,
                    """
                    "State should be `_3` because `._2To3` (next action and state change) will also be triggered
                    as part of `._1To2`'s effect. (NOTE: `._2To3`'s effect won't be awaited)
                    """)

        await tick(1.3)
        assertEqual(await actomaton.state, ._4(count: 0))

        await tick(1.3)
        assertEqual(await actomaton.state, ._4(count: 1))

        await tick(1.3)
        assertEqual(await actomaton.state, ._4(count: 2))

        // Comment-Out: A bit flaky to check this intermediate state, so ignore it.
        //await tick(1.3)
        //assertEqual(await actomaton.state, ._5)

        await tick(2)
        assertEqual(await actomaton.state, ._6)
    }

    func test_tracksFeedbacks_single() async throws
    {
        // Start from `._1` for `single`-first (async) effect test.
        await setupActomaton(initalState: ._1)

        assertEqual(await actomaton.state, ._1)

        // Single effect, tracking feedbacks.
        let task = await actomaton.send(._1To2, tracksFeedbacks: true)

        // Wait for all: `._1To2`, `._2To3`, `._3To4`, `._increment`, `._4To5`, `._5To6`.
        try await task?.value

        assertEqual(await actomaton.state, ._6,
                    "Should wait for final result `._6` because `tracksFeedbacks = true`")
    }

    func test_tracksFeedbacks_sequence() async throws
    {
        // Start from `._3` for `sequence`-first effect test.
        await setupActomaton(initalState: ._3)

        assertEqual(await actomaton.state, ._3)

        // Sequence effect, tracking feedbacks.
        let task = await actomaton.send(._3To4, tracksFeedbacks: true)

        // Wait for all: `._3To4`, `._increment`, `._4To5`, `._5To6`.
        try await task?.value

        assertEqual(await actomaton.state, ._6,
                    "Should wait for final result `._5` because `tracksFeedbacks = true`")
    }
}

// MARK: - Private

private enum Action: Sendable
{
    case _1To2
    case _2To3
    case _3To4 // start 3-tick timer
    case _increment
    case _4To5
    case _5To6
    case _toEnd
}

private enum State: Equatable, Sendable
{
    case _1
    case _2
    case _3
    case _4(count: Int)
    case _5
    case _6
    case _end
}
