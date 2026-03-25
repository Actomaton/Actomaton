import Foundation

/// Protocol for abstracting output processing in ``MealyMachine``.
///
/// Different conformers can handle different reducer output types.
///
/// The conformer does NOT own the reducer or state — those are managed by ``MealyMachine``.
/// It only receives the reducer's output and processes it (e.g., creating tasks, managing queues).
public protocol EffectManagerProtocol<Action, State, Output>: AnyObject
{
    associatedtype Action
    associatedtype State
    associatedtype Output

    /// Set up communication callbacks with the owning actor.
    ///
    /// Called once by ``MealyMachine`` after initialization.
    ///
    /// - Parameters:
    ///   - isolatedPerform:
    ///     Closure to run a block within the owning actor's isolation.
    ///     This method is a proof that `self` (EffectManager) is owned and protected by `isolated any Actor`,
    ///     which guarantees e.g. safe clean up work inside `Task` closure while `self` is usually a non-`Sendable` class.
    ///   - sendAction:
    ///     Closure to send feedback actions back to the owning actor.
    ///
    /// - Warning:
    ///   Technically, `performIsolated` closure's second parameter should be typed as `Self`
    ///   rather than `any EffectManagerProtocol`.
    ///   However, Swift 6.2 compiler complains about this due to `SendableMetatype` check
    ///   that shows a warning message: "Capture of non-Sendable type 'EffM.Type' in an isolated closure".
    ///   Thus, as a workaround, we loosen the closure parameter type from `Self` to `any EffectManagerProtocol`,
    ///   and let `EffectManager` implementation side call `as! Self` cast instead, which will be a safe operation.
    func setUp(
        performIsolated: @escaping @Sendable (
            @escaping @Sendable (isolated any Actor, any EffectManagerProtocol<Action, State, Output>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )

    /// Recursively resolves synchronous output by running the reducer via `sendReducer`,
    /// returning the preprocessed output with only async effects remaining.
    ///
    /// Called by ``MealyMachine/send(_:priority:tracksFeedbacks:)`` before ``processOutput(_:priority:tracksFeedbacks:)``.
    func preprocessOutput(
        _ output: Output,
        sendReducer: (Action) -> Output
    ) -> Output

    /// Process reducer output, creating and managing tasks as needed.
    ///
    /// Called by ``MealyMachine`` after running the reducer and resolving synchronous actions.
    func processOutput(
        _ output: Output,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?

    /// Cancel all running tasks and drain pending effects.
    func shutDown()
}
