import Foundation

/// Effectless, Actionless (feedbackless) Effect Manager where `Output` is `Void`.
public struct NoOpEffectManager<Action, State>: EffectManager
    where Action: Sendable
{
    public typealias Output = Void

    public init() {}

    // MARK: - EffectManager

    public mutating func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, inout NoOpEffectManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {}

    public mutating func preprocessOutput(
        _ output: Output,
        runReducer: (Action) -> Output
    )
    {}

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
