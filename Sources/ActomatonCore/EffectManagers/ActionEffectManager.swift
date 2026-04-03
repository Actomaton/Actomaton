import Foundation

/// Simple `Action`-based Effect Manager where `Output` is `[Action]` that allows synchronous action feedback loop
/// without side-effects.
///
/// Each action in the output array is fed back into the reducer sequentially.
/// Any further actions produced by those feedback calls are recursively processed
/// until no more actions remain.
public final class ActionEffectManager<Action, State>: EffectManagerProtocol
    where Action: Sendable
{
    public typealias Output = [Action]

    public init() {}

    // MARK: - EffectManagerProtocol

    public func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, ActionEffectManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {}

    public func preprocessOutput(
        _ output: Output,
        sendReducer: (Action) -> Output
    ) -> Output
    {
        var remaining: [Action] = []
        for action in output {
            let nested = preprocessOutput(sendReducer(action), sendReducer: sendReducer)
            remaining.append(contentsOf: nested)
        }
        return remaining
    }

    public func processOutput(
        _ output: Output,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?
    {
        return nil
    }

    public func shutDown()
    {}
}
