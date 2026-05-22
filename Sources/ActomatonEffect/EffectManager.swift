import Foundation

/// Protocol for abstracting output processing in ``MealyMachine``.
///
/// Different conformers can handle different reducer output types.
///
/// The conformer does NOT own the reducer or state — those are managed by ``MealyMachine``.
/// It only receives the reducer's output and processes it (e.g., creating tasks, managing queues).
public protocol EffectManager<Action, State, Output>: SendableMetatype
{
    associatedtype Action
    associatedtype State
    associatedtype Output

    /// Set up communication callbacks bridging the conformer to the parent safe container.
    ///
    /// Called once by ``MealyMachine`` from inside its `setUp(...)`.
    ///
    /// - Parameters:
    ///   - withSendability:
    ///     `@Sendable` closure that runs work against the (otherwise non-`Sendable`) conformer (`Self`)
    ///     with **inherited sendability** from the parent safe container that wraps the conformer
    ///     and is itself `Sendable` — e.g. `actor Actomaton`, or a `nonisolated final class`
    ///     marked `@unchecked Sendable`.
    ///     With this sendability, the conformer's private mutable state becomes accessible with
    ///     `@Sendable` protection, which allows robust cross-isolation Swift Concurrency handling
    ///     such as effect clean-ups via unstructured `Task.detached` — without requiring the
    ///     conformer itself to be `Sendable`. `self` is received as the callback's `Self`
    ///     parameter rather than captured, so detached cleanup tasks do not need an unsafe `[weak self]`.
    ///   - sendAction:
    ///     `@Sendable` closure that sends feedback actions back through the reducer pipeline.
    ///     This closure also derives its sendability from the parent wrapper.
    func setUp(
        withSendability: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (Self) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )

    /// Process reducer output, creating and managing tasks as needed.
    ///
    /// Called by the wrapper after ``MealyMachine/send(_:)`` returns its asynchronous-remainder
    /// output. Synchronous feedback actions have already been resolved by ``MealyMachine``.
    func processOutput(
        _ output: Output,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?

    /// Cancel all running tasks and drain pending effects.
    func shutDown()
}
