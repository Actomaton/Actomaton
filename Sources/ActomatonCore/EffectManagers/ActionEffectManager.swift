import Foundation

/// Simple `Action`-based Effect Manager where `Output` is `[Action]` that allows synchronous action feedback loop
/// without side-effects.
///
/// Each action in the output array is fed back into the reducer sequentially.
/// Any further actions produced by those feedback calls are recursively processed
/// until no more actions remain.
public struct ActionEffectManager<Action, State>: EffectManager
    where Action: Sendable
{
    public typealias Output = [Action]

    public init() {}

    // MARK: - EffectManager

    public mutating func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, inout ActionEffectManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {}

    public func preprocessOutput(
        _ output: Output,
        runReducer: (Action) -> Output
    ) -> Output
    {
        var remaining: [Action] = []
        for action in output {
            let nested = preprocessOutput(runReducer(action), runReducer: runReducer)
            remaining.append(contentsOf: nested)
        }
        return remaining
    }

    public mutating func processOutput(
        _ output: Output,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?
    {
        return nil
    }

    public mutating func shutDown()
    {}
}
