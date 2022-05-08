import XCTest
@testable import Actomaton

import Combine

/// Tests for `Effect.cancel` to cancel pending effects by `Oldest1SuspendNewEffectQueueProtocol`.
final class PendingEffectCancellationTests: XCTestCase
{
    fileprivate var actomaton: Actomaton<Action, State>!

    private var flags = Flags()

    private actor Flags
    {
        var result1: Result = .initial
        var result2: Result = .initial

        func mark(
            result1: Result? = nil,
            result2: Result? = nil
        )
        {
            if let result1 = result1 {
                self.result1 = result1
            }
            if let result2 = result2 {
                self.result2 = result2
            }
        }

        enum Result
        {
            case initial
            case completed
            case cancelled
        }
    }

    override func setUp() async throws
    {
        flags = Flags()

        struct EffectID: EffectIDProtocol
        {
            let name: String
        }

        struct Oldest1SuspendNewEffectQueue: Oldest1SuspendNewEffectQueueProtocol {}

        let actomaton = Actomaton<Action, State>(
            state: .init(),
            reducer: Reducer { [flags] action, state, _ in
                switch action {
                case .fetch1:
                    return Effect(id: EffectID(name: "1"), queue: Oldest1SuspendNewEffectQueue()) {
                        try await tick(1) {
                            return ._didFetch1
                        } ifCancelled: {
                            Debug.print("Effect 1 cancelled")
                            await flags.mark(result1: .cancelled)
                            return nil
                        }
                    }

                case .fetch2:
                    return Effect(id: EffectID(name: "2"), queue: Oldest1SuspendNewEffectQueue()) {
                        try await tick(1) {
                            return ._didFetch2
                        } ifCancelled: {
                            // NOTE: When Effect 2 is suspended and cancelled before execution,
                            // this scope won't even be called

                            Debug.print("Effect 2 cancelled")
                            await flags.mark(result2: .cancelled)
                            return nil
                        }
                    }

                case ._didFetch1:
                    return Effect.fireAndForget { await flags.mark(result1: .completed) }

                case ._didFetch2:
                    return Effect.fireAndForget { await flags.mark(result2: .completed) }

                case .cancelAll:
                    return Effect.cancel(ids: { $0.value is EffectID })
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

    func test_noCancel() async throws
    {
        assertEqual(await flags.result1, .initial)
        assertEqual(await flags.result2, .initial)

        await actomaton.send(.fetch1)
        await actomaton.send(.fetch2) // NOTE: This fetch will be suspended by `Oldest1SuspendNewEffectQueue`.

        try await tick(1.5)

        assertEqual(await flags.result1, .completed)
        assertEqual(await flags.result2, .initial, "Should not complete yet.")

        try await tick(1.5)

        assertEqual(await flags.result1, .completed)
        assertEqual(await flags.result2, .completed)
    }

    func test_cancelPendingEffects() async throws
    {
        assertEqual(await flags.result1, .initial)
        assertEqual(await flags.result2, .initial)

        await actomaton.send(.fetch1)
        await actomaton.send(.fetch2)

        await actomaton.send(.cancelAll)

        try await tick(1.5)

        assertEqual(await flags.result1, .cancelled)
        assertEqual(await flags.result2, .cancelled)
    }
}

// MARK: - Private

private enum Action
{
    case fetch1
    case fetch2
    case cancelAll

    case _didFetch1
    case _didFetch2
}

private struct State {}
