import Foundation

/// Simple `Action`-based Effect Manager where `Output` is `Action?` that allows synchronous action feedback loop
/// without side-effects.
public final class ActionEffectManager<Action, State>: EffectManagerProtocol
    where Action: Sendable
{
    public typealias Output = Action?

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
    ) -> Output
    {
        if let output {
            return preprocessOutput(sendReducer(output), sendReducer: sendReducer)
        }
        else {
            return nil
        }
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
