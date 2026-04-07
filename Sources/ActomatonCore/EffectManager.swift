import Foundation

/// Protocol for abstracting output processing in ``MealyMachine``.
///
/// Different conformers can handle different reducer output types.
///
/// The conformer does NOT own the reducer or state — those are managed by ``MealyMachine``.
/// It only receives the reducer's output and processes it (e.g., creating tasks, managing queues).
public protocol EffectManager<Action, State, Output>: AnyObject
{
    associatedtype Action
    associatedtype State
    associatedtype Output

    /// Set up communication callbacks with the owning actor.
    ///
    /// Called once by ``MealyMachine`` after initialization.
    ///
    /// - Parameters:
    ///   - performIsolated:
    ///     Closure to run a block within the owning actor's isolation.
    ///     This method is a proof that `self` (the conformer) is owned and protected by `isolated any Actor`,
    ///     which guarantees e.g. safe clean up work inside `Task` closure while `self` is usually a non-`Sendable`
    /// class.
    ///   - sendAction:
    ///     Closure to send feedback actions back to the owning actor.
    func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, Self) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )

    /// Recursively resolves synchronous output by running the reducer via `sendReducer`,
    /// returning the preprocessed output with only async effects remaining.
    ///
    /// Called by ``MealyMachine/send(_:priority:tracksFeedbacks:)`` before
    /// ``processOutput(_:priority:tracksFeedbacks:)``.
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
