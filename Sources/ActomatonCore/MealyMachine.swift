import Foundation

/// Deterministic finite state machine that receives "action" and with "current state" transform to "next state" &
/// additional "output", which then generates Swift Concurrency side-effects via ``EffectManager``.
///
/// `MealyMachine` is a plain `final class` and does NOT provide its own isolation.
/// Wrap it inside a safe container — e.g. `actor Actomaton`, a `@MainActor`-isolated class
/// (like `Store` in `ActomatonUI`), or a `nonisolated final class` marked `@unchecked Sendable` —
/// that serializes access to `send(_:)` and `state`.
///
/// Instances of `MealyMachine` are intentionally non-`Sendable`; the wrapper enforces the
/// serial-access invariant. The ``Swift/SendableMetatype`` conformance only marks
/// `MealyMachine.Type` itself as `Sendable` so it can appear in `@Sendable` closure signatures —
/// it makes no claim about instance sendability.
public final class MealyMachine<Action, State, Output>: SendableMetatype
{
    public private(set) var state: State
    {
        willSet {
            willChangeState(state, newValue)
        }
    }

    /// Core manages effect lifecycle: task creation, queue policies, and cancellation.
    /// Agnostic about reducer and state mutation.
    ///
    /// The surrounding wrapper (e.g. `actor Actomaton`, or a `@MainActor`-isolated class like
    /// `Store`'s `StoreCore`) can hand this back to the conformer via its `runIsolatedMachine`
    /// callback.
    private var effectManager: (any EffectManager<Action, State, Output>)?

    private let reducer: MealyReducer<Action, State, (), Output>

    /// State change handler. Wrappers can use this to fan out state changes to their own
    /// observers (Combine publishers, callbacks, etc.).
    private let willChangeState: (_ old: State, _ new: State) -> Void

    /// Initializer without `environment`.
    ///
    /// - Parameters:
    ///   - willChangeState:
    ///     Hook fired inside `state.willSet`. Wrappers can use it to forward state changes
    ///     to external observers.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Output>,
        willChangeState: @escaping (_ old: State, _ new: State) -> Void = { _, _ in }
    ) where Action: Sendable
    {
        self.state = state
        self.reducer = reducer
        self.willChangeState = willChangeState
    }

    /// Initializer with `environment`.
    public convenience init<Environment>(
        state: State,
        reducer: MealyReducer<Action, State, Environment, Output>,
        environment: Environment,
        willChangeState: @escaping (_ old: State, _ new: State) -> Void = { _, _ in }
    ) where Action: Sendable, Environment: Sendable
    {
        self.init(
            state: state,
            reducer: MealyReducer { action, state, _ in
                reducer.run(action, &state, environment)
            },
            willChangeState: willChangeState
        )
    }

    deinit
    {
        effectManager?.shutDown()
    }

    /// Sets up ``EffectManager``.
    ///
    /// This method should normally be called right after `MealyMachine.init` is complete,
    /// so that its wrapper `Sendable` reference types (e.g. `actor Actomaton`) can enter
    /// this method's `@Sendable` closure arguments.
    ///
    /// - Parameters:
    ///   - withSendability:
    ///     `@Sendable` closure that runs work against the (otherwise `nonisolated`) ``MealyMachine``
    ///     with **inherited sendability** from the parent safe container that wraps ``MealyMachine``
    ///     and is itself `Sendable` — e.g. `actor Actomaton`, or a `nonisolated final class`
    ///     marked `@unchecked Sendable`.
    ///     With this sendability, the private non-sendable ``EffectManager`` inside ``MealyMachine``
    ///     becomes accessible with `@Sendable` protection, which allows robust cross-isolation
    ///     Swift Concurrency handling such as effect clean-ups via unstructured `Task.detached`.
    ///   - sendAction:
    ///     ``MealyMachine`` effect-feedback loop handler that is triggered by ``EffectManager``.
    ///     This closure is also `@Sendable`, deriving its sendability from the parent wrapper.
    public func setUp<EffM>(
        effectManager: EffM,
        withSendability: @escaping @Sendable (
            _ runMachine: sending @escaping (MealyMachine<Action, State, Output>) -> Void
        ) async -> Void = { _ in },
        sendAction: @escaping @Sendable (
            Action, TaskPriority?, _ tracksFeedbacks: Bool
        ) async -> Task<(), any Error>? = { _, _, _ in nil }
    ) where EffM: EffectManager<Action, State, Output>
    {
        self.effectManager = effectManager

        effectManager.setUp(
            withSendability: { runEffM in
                await withSendability { machine in
                    // Safe downcast from type-erased `any EffectManager` storage to satisfy `Self` in the protocol
                    // callback.
                    runEffM(machine.effectManager as! EffM)
                }
            },
            sendAction: sendAction
        )
    }

    /// Sends `action` to `MealyMachine`.
    ///
    /// - Parameters:
    ///   - priority:
    ///     Priority of the task. If `nil`, the priority will come from `Task.currentPriority`.
    ///   - tracksFeedbacks:
    ///     If `true`, returned `Task` will also track its feedback effects that are triggered by next actions,
    ///     so that their wait-for-all and cancellations are possible.
    ///     Default is `false`.
    ///
    /// - Returns:
    ///   Unified task that can handle (wait for or cancel) all combined effects triggered by `action` in `Reducer`.
    @discardableResult
    public func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), any Error>?
    {
        let output = reducer.run(action, &state, ())

        guard let effectManager else { return nil }

        let output_ = effectManager.preprocessOutput(output) { action in
            reducer.run(action, &state, ())
        }
        return effectManager.processOutput(output_, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }
}
