import XCTest
@testable import Actomaton

import Combine

/// Tests for `EffectQueueDelay`.
final class EffectQueueDelayTests: XCTestCase
{
    private func makeActomaton<Queue: EffectQueueProtocol>(
        queue: Queue,
        effectTime: TimeInterval
    ) -> (Actomaton<Action, State>, startedIDs: ResultsCollector<String>, cancelledIDs: ResultsCollector<String>)
    {
        let startedIDs: ResultsCollector<String> = .init()
        let cancelledIDs: ResultsCollector<String> = .init()

        let actomaton = Actomaton<Action, State>(
            state: .init(),
            reducer: Reducer { action, state, _ in
                switch action {
                case let .fetch(id):
                    return Effect(id: EffectID(name: "running \(id)"), queue: queue) {
                        // NOTE: Due to `queue`'s delay, this scope may run at delayed schedule time.

                        print("Start: \(id), Task.isCancelled = \(Task.isCancelled)")

                        // Swift 5.7 requirement:
                        // Add short delay before checking `Task.isCancelled` since Swift 5.7's cancellation propagation
                        // seems to become slower than Swift 5.6 and needs to wait for actual `Task.isCancelled` check.
                        // Note that this tweak is only needed for testing purpose,
                        // and won't be necessary for production code.
                        do {
                            try await Task.sleep(nanoseconds: 1_000_000)
                        }
                        catch {
                            // Ignore cancellation handling during `Task.sleep`.
                        }

                        print("Start (recheck): \(id), Task.isCancelled = \(Task.isCancelled)")

                        // NOTE:
                        // Because of delayed effect cancellation may occur by `EffectQueue`,
                        // `Task.isCancelled` may already be `true` at here.
                        if !Task.isCancelled {
                            await startedIDs.append(id)
                        }

                        return try await tick(effectTime) {
                            return ._didFetch(id: id)
                        } ifCancelled: { () -> Action? in
                            print("Effect \(id) cancelled")
                            await cancelledIDs.append(id)
                            return nil
                        }
                    }

                case let ._didFetch(id):
                    state.finishedIDs.insert(id)

                    return Effect.fireAndForget {
                        print("Finished: \(id)")
                    }
                }
            }
        )

        return (actomaton, startedIDs, cancelledIDs)
    }

    func test_DelayedEffectQueue() async throws
    {
        let delay: TimeInterval = 3
        let effectTime: TimeInterval = 2

        // `.runNewest(maxCount: .max)`.
        let (actomaton, startedIDs, cancelledIDs) = makeActomaton(
            queue: DelayedEffectQueue(delay: delay),
            effectTime: effectTime
        )

        assertEqual(await actomaton.state.finishedIDs, [])
        assertEqual(await startedIDs.results, [])
        assertEqual(await cancelledIDs.results, [])

        await actomaton.send(.fetch(id: "1")) // fetch at t=0
        await actomaton.send(.fetch(id: "2")) // delayed fetch at t=3
        await actomaton.send(.fetch(id: "3")) // delayed fetch at t=6
        await actomaton.send(.fetch(id: "4")) // delayed fetch at t=9

        assertEqual(await actomaton.state.finishedIDs, [])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2", "3"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2", "3", "4"])

        // ResultCollector
        assertEqual(await startedIDs.results, ["1", "2", "3", "4"],
                    "Should run all effects.")
        assertEqual(await cancelledIDs.results, [])
    }

    // NOTE: Behaves similar to debounce, but up to `.runNewest(N)` effects.
    func test_DelayedNewest2EffectQueue() async throws
    {
        let delay: TimeInterval = 2
        let effectTime: TimeInterval = 1

        // `.runNewest(2)`
        let (actomaton, startedIDs, cancelledIDs) = makeActomaton(
            queue: DelayedNewest2EffectQueue(delay: delay),
            effectTime: effectTime
        )

        assertEqual(await actomaton.state.finishedIDs, [])

        await actomaton.send(.fetch(id: "1")) // fetch at t=0, will be auto-cancelled by queue
        await actomaton.send(.fetch(id: "2")) // delayed fetch at t=2, will be auto-cancelled by queue
        await actomaton.send(.fetch(id: "3")) // delayed fetch at t=4
        await actomaton.send(.fetch(id: "4")) // delayed fetch at t=6

        assertEqual(await actomaton.state.finishedIDs, [])

        try await tick(delay * 2 + effectTime + 0.5)
        assertEqual(await actomaton.state.finishedIDs, ["3"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["3", "4"])

        // ResultCollector
        assertEqual(await startedIDs.results, ["3", "4"],
                    "Only last 2 should run effects.")
        assertEqual(await cancelledIDs.results, ["1", "2"])
    }

    func test_DelayedOldest2SuspendNewEffectQueue() async throws
    {
        let delay: TimeInterval = 2
        let effectTime: TimeInterval = 3

        // `.runOldest(2, .suspendNew)`
        let (actomaton, startedIDs, cancelledIDs) = makeActomaton(
            queue: DelayedOldest2SuspendNewEffectQueue(delay: delay),
            effectTime: effectTime
        )

        assertEqual(await actomaton.state.finishedIDs, [])

        await actomaton.send(.fetch(id: "1")) // fetch at t=0, comples at t=3
        await actomaton.send(.fetch(id: "2")) // delayed fetch at t=2, comples at t=5
        await actomaton.send(.fetch(id: "3")) // delayed fetch at t=4, comples at t=7
        await actomaton.send(.fetch(id: "4")) // delayed fetch at t=6, comples at t=9

        assertEqual(await actomaton.state.finishedIDs, [])

        try await tick(effectTime + 0.5)
        assertEqual(await actomaton.state.finishedIDs, ["1"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2", "3"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2", "3", "4"])

        // ResultCollector
        assertEqual(await startedIDs.results, ["1", "2", "3", "4"],
                    "Should run all effects.")
        assertEqual(await cancelledIDs.results, [])
    }

    func test_DelayedOldest2DiscardNewEffectQueue() async throws
    {
        let delay: TimeInterval = 2
        let effectTime: TimeInterval = 3

        // `.runOldest(2, .discardNew)`
        let (actomaton, startedIDs, cancelledIDs) = makeActomaton(
            queue: DelayedOldest2DiscardNewEffectQueue(delay: delay),
            effectTime: effectTime
        )

        assertEqual(await actomaton.state.finishedIDs, [])

        await actomaton.send(.fetch(id: "1")) // fetch at t=0, comples at t=3
        await actomaton.send(.fetch(id: "2")) // delayed fetch at t=2, comples at t=5
        await actomaton.send(.fetch(id: "3")) // delayed fetch at t=4, will be auto-cancelled by queue
        await actomaton.send(.fetch(id: "4")) // delayed fetch at t=6, will be auto-cancelled by queue

        assertEqual(await actomaton.state.finishedIDs, [])

        try await tick(effectTime + 0.5)
        assertEqual(await actomaton.state.finishedIDs, ["1"])

        try await tick(delay)
        assertEqual(await actomaton.state.finishedIDs, ["1", "2"])

        // ResultCollector
        assertEqual(await startedIDs.results.sorted(), ["1", "2"],
                    "Only first 2 should run effects.")
        assertEqual(await cancelledIDs.results.sorted(), ["3", "4"])
    }
}

// MARK: - Private

private enum Action
{
    case fetch(id: String)
    case _didFetch(id: String)
}

private struct State: Equatable
{
    var finishedIDs: Set<String> = []
}

private struct EffectID: EffectIDProtocol
{
    var name: String
}

private struct DelayedEffectQueue: EffectQueueProtocol
{
    let delay: TimeInterval
    var effectQueuePolicy: EffectQueuePolicy { .runNewest(maxCount: .max) }
    var effectQueueDelay: EffectQueueDelay { .constant(delay * timescale) }
}

private struct DelayedNewest2EffectQueue: EffectQueueProtocol
{
    let delay: TimeInterval
    var effectQueuePolicy: EffectQueuePolicy { .runNewest(maxCount: 2) }
    var effectQueueDelay: EffectQueueDelay { .constant(delay * timescale) }
}

private struct DelayedOldest2SuspendNewEffectQueue: EffectQueueProtocol
{
    let delay: TimeInterval
    var effectQueuePolicy: EffectQueuePolicy { .runOldest(maxCount: 2, .suspendNew) }
    var effectQueueDelay: EffectQueueDelay { .constant(delay * timescale) }
}

private struct DelayedOldest2DiscardNewEffectQueue: EffectQueueProtocol
{
    let delay: TimeInterval
    var effectQueuePolicy: EffectQueuePolicy { .runOldest(maxCount: 2, .discardNew) }
    var effectQueueDelay: EffectQueueDelay { .constant(delay * timescale) }
}

private let timescale: TimeInterval = TimeInterval(tickTimeInterval) / 1_000_000_000
