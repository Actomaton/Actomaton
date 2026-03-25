import Foundation

/// Effectless, Actionless (feedbackless) Effect Manager where `Output` is `Void`.
public final class NoOpEffectManager<Action, State>: EffectManagerProtocol
    where Action: Sendable
{
    public typealias Output = Void

    public init() {}

    // MARK: - EffectManagerProtocol

    public func setUp(
        performIsolated: @escaping @Sendable (
            @escaping @Sendable (isolated any Actor, any EffectManagerProtocol<Action, State, Output>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {}

    public func preprocessOutput(
        _ output: Output,
        sendReducer: (Action) -> Output
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
