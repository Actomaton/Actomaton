import Actomaton
import Foundation
import XCTest

#if !DISABLE_COMBINE && canImport(Combine)
import Combine
#endif

/// Compile-only test for README.
private func readMe1_1_effectContext() async throws
{
    enum Action: Sendable {
        case start
        case finished
    }

    struct State: Sendable {
        var isRunning = false
    }

    let reducer = Reducer<Action, State, Void> { action, state, _ in
        switch action {
        case .start:
            state.isRunning = true
            return Effect { context in
                try await context.clock.sleep(for: .seconds(1))
                return .finished
            }

        case .finished:
            state.isRunning = false
            return .empty
        }
    }

    let actomaton = Actomaton<Action, State>(
        state: State(),
        reducer: reducer
    )

    _ = await actomaton.send(.start)
}

/// Compile-only test for README.
private func readMe1_4() async throws
{
    enum Action: Sendable {
        case fetch(id: String)
        case _didFetch(Data)
    }

    struct State: Sendable {} // no state

    struct Environment: Sendable {
        let fetch: @Sendable (_ id: String) async throws -> Data
    }

    struct DelayedEffectQueue: EffectQueue {
        // First 3 effects will run concurrently, and other sent effects will be suspended.
        var effectQueuePolicy: EffectQueuePolicy {
            .runOldest(maxCount: 3, .suspendNew)
        }

        // Adds delay between effect start. (This is useful for throttling / deboucing)
        var effectQueueDelay: EffectQueueDelay {
            .random(0.1 ... 0.3)
        }
    }

    let reducer = Reducer<Action, State, Environment> { action, _, environment in
        switch action {
        case let .fetch(id):
            return Effect(queue: DelayedEffectQueue()) {
                let data = try await environment.fetch(id)
                return ._didFetch(data)
            }
        case let ._didFetch(data):
            // Do something with `data`.
            print(data)
            return .empty
        }
    }

    let actomaton = Actomaton<Action, State>(
        state: State(),
        reducer: reducer,
        environment: Environment(fetch: { _ in Data() /* ... */ })
    )

    await actomaton.send(.fetch(id: "item1"))
    await actomaton.send(.fetch(id: "item2")) // min delay of 0.1
    await actomaton.send(.fetch(id: "item3")) // min delay of 0.1 (after item2 actually starts)
    await actomaton.send(.fetch(id: "item4")) // starts when item1 or 2 or 3 finishes
}
