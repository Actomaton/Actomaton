import Foundation

/// Effectless, Actionless (feedbackless) Effect Manager where `Output` is `Void`.
public struct NoOpEffectManager<Action, State>: EffectManager
    where Action: Sendable
{
    public typealias Output = Void

    public init() {}

    // MARK: - EffectManager

    public func setUp(
        withSendability: @escaping @Sendable (
            _ runEffM: sending @escaping (NoOpEffectManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {}

    public func preprocessOutput(
        _ output: Output,
        runReducer: (Action) -> Output
    )
    {}

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
