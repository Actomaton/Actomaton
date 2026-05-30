import Actomaton
import XCTest

final class EffectPriorityTests: MainTestCase
{
    private var priorities = ResultsCollector<RecordedPriority>()

    override func setUp() async throws
    {
        priorities = ResultsCollector<RecordedPriority>()
    }

    func test_singleEffectPriorityOverridesSendPriority() async throws
    {
        let actomaton = makeActomaton()

        let result = await actomaton.send(.single, priority: .background)
        await result.completion()

        assertEqual(
            await priorities.results,
            [.init(name: "single", priority: .high)]
        )
    }

    func test_sequenceEffectPriorityOverridesSendPriority() async throws
    {
        let actomaton = makeActomaton()

        let result = await actomaton.send(.sequence, priority: .background)
        await result.completion()

        assertEqual(
            await priorities.results,
            [.init(name: "sequence", priority: .high)]
        )
    }

    func test_suspendedEffectUsesEffectPriorityWhenDequeued() async throws
    {
        let actomaton = makeActomaton()

        let firstResult = await actomaton.send(
            .queued(name: "first", priority: nil),
            priority: .background
        )
        let secondResult = await actomaton.send(
            .queued(name: "second", priority: .high),
            priority: .background
        )

        await settle()
        assertEqual(await priorities.results.map(\.name), ["first"])

        await clock.advance(by: .ticks(1.5))
        await settle()
        assertEqual(await priorities.results.map(\.name), ["first", "second"])

        await clock.advance(by: .ticks(1.5))
        await firstResult.completion()
        await secondResult.completion()

        assertEqual(
            await priorities.results.last,
            .init(name: "second", priority: .high)
        )
    }

    private func makeActomaton() -> Actomaton<PriorityAction, Int, Never>
    {
        Actomaton<PriorityAction, Int, Never>(
            state: 0,
            reducer: Reducer { [priorities] action, state, _ in
                switch action {
                case .single:
                    return Effect(priority: .high) { _ -> PriorityAction? in
                        await priorities.append(.init(name: "single", priority: Task.currentPriority))
                        return nil
                    }

                case .sequence:
                    return Effect.sequence(priority: .high) { _ -> AsyncStream<PriorityAction>? in
                        await priorities.append(.init(name: "sequence", priority: Task.currentPriority))
                        return AsyncStream { continuation in
                            continuation.finish()
                        }
                    }

                case let .queued(name, priority):
                    state += 1
                    return Effect(queue: PrioritySuspendQueue(), priority: priority) { context -> PriorityAction? in
                        await priorities.append(.init(name: name, priority: Task.currentPriority))
                        try await context.clock.sleep(for: .ticks(1))
                        return nil
                    }
                }
            },
            effectContext: effectContext
        )
    }
}

private enum PriorityAction: Sendable
{
    case single
    case sequence
    case queued(name: String, priority: TaskPriority?)
}

private struct RecordedPriority: Equatable, Sendable
{
    var name: String
    var priority: TaskPriority
}

private struct PrioritySuspendQueue: Oldest1SuspendNewEffectQueue {}
