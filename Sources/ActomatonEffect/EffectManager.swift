import Foundation

/// Bare-minimum contract that ``EffectManager``'s `Output` type must satisfy so that the
/// manager can carry the caller's `Emission` channel without knowing the concrete output
/// shape (e.g. ``Effect``). Conformers expose the side-channel value type via
/// ``EffectOutput/Emission`` so a single `EffectManager<Action, State, Output>` constraint
/// suffices — `Output.Emission` is derived rather than separately bound.
public protocol EffectOutput
{
    associatedtype Emission
}

/// Protocol for abstracting output processing in ``MealyMachine``.
///
/// Different conformers can handle different reducer output types — the protocol is generic
/// over `Output`, and each concrete manager (e.g. ``EffectQueueManager``) refines `Output`
/// to its specific output shape (`Effect<Action, Emission>` in the queue manager's case).
///
/// The conformer does NOT own the reducer or state — those are managed by ``MealyMachine``.
/// It only receives the reducer's output and processes it (e.g., creating tasks, managing queues).
///
/// `Action` is the feedback channel re-fed into the reducer. `Output.Emission` is the
/// side-channel value type emitted to the `send` caller via the `emit` callback.
public protocol EffectManager<Action, State, Output>: SendableMetatype
{
    associatedtype Action
    associatedtype State
    associatedtype Output: EffectOutput

    /// Set up communication callbacks bridging the conformer to the parent safe container.
    ///
    /// Called once by the wrapping safe container (e.g. ``Actomaton``, `MealyDriver`, `Store`,
    /// `TestActomaton`, `DistributedActomaton`) during its initialization.
    ///
    /// - Parameters:
    ///   - withSendability:
    ///     `@Sendable` closure that runs work against the (otherwise non-`Sendable`) conformer (`Self`)
    ///     with **inherited sendability** from the parent safe container that wraps the conformer
    ///     and is itself `Sendable` — e.g. `actor Actomaton`, or a `nonisolated final class`
    ///     marked `@unchecked Sendable`.
    ///     With this sendability, the conformer's private mutable state becomes accessible with
    ///     `@Sendable` protection, which allows robust cross-isolation Swift Concurrency handling
    ///     such as effect clean-ups via unstructured `Task` — without requiring the
    ///     conformer itself to be `Sendable`. `self` is received as the callback's `Self`
    ///     parameter rather than captured, so unstructured cleanup tasks do not need an unsafe `[weak self]`.
    ///   - sendAction:
    ///     `@Sendable` closure that sends feedback actions back through the reducer pipeline.
    ///     The trailing `emit` parameter forwards the original `send`'s emission callback so
    ///     that any `Output.Emission` values produced by the feedback's downstream effects
    ///     flow into the same top-level result stream observed by the original caller (only
    ///     meaningful when `tracksFeedbacks: true`; otherwise the recursive chain is
    ///     fire-and-forget). This closure also derives its sendability from the parent wrapper.
    func setUp(
        withSendability: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (Self) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (
            _ action: Action,
            _ priority: TaskPriority?,
            _ tracksFeedbacks: Bool,
            _ emit: @escaping @Sendable (Result<Output.Emission, any Error>) -> Void
        ) async -> Task<(), Never>?
    )

    /// Process the reducer output, creating and managing tasks as needed.
    ///
    /// Called by the wrapper after ``MealyMachine/send(_:)`` returns its asynchronous-remainder
    /// output. Synchronous feedback (e.g. ``Effect/Kind/next``) has already been resolved by
    /// ``MealyMachine``; this method is responsible for translating the remaining `Output` into
    /// async tasks while routing synchronous side-channel values via `emit`.
    func processOutput(
        _ output: Output,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Output.Emission, any Error>) -> Void
    ) -> Task<(), Never>?

    /// Processes the top-level `send` output and wraps its emitted side-channel values in a
    /// ``SendResults``.
    ///
    /// This is the entry point for public `send` calls (as opposed to recursive feedback, which
    /// keeps using the primitive ``processOutput(_:priority:tracksFeedbacks:emit:)`` overload so
    /// all downstream emissions flow into the original caller's single ``SendResults`` stream).
    ///
    /// - Parameter id:
    ///   Optional cancellation identifier for the whole `send`. When non-`nil`, the returned
    ///   ``SendResults``'s cancellation is registered under `id`, so a reducer-side
    ///   ``Effect/cancel(id:)`` (or ``Effect/cancel(ids:)``) matching `id` cancels this
    ///   ``SendResults`` exactly as ``SendResults/cancel()`` would — in addition to cancelling any
    ///   effect tasks sharing that `id`.
    func processSendOutput(
        _ output: Output,
        id: (any EffectID)?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> SendResults<Output.Emission>
}
