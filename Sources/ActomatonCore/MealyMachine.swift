/// Deterministic finite state machine that, given an `Action` and the current `State`, transitions
/// to the next `State` and produces an `Output`.
///
/// `MealyMachine` is side-effect-less: `send(_:)` runs the reducer (recursively, when the output
/// reports synchronous feedback actions via ``MealyOutput``) and returns the resulting `Output`.
/// It never spawns Swift Concurrency tasks itself. Wrappers that need async effects (e.g.
/// `actor Actomaton`, or `Store` in `ActomatonUI`) hand the returned `Output` to their own
/// effect manager.
///
/// `MealyMachine` is a plain `final class` and does NOT provide its own isolation. Wrap it
/// inside a safe container — e.g. `actor Actomaton`, a `@MainActor`-isolated class, or a
/// `nonisolated final class` marked `@unchecked Sendable` — that serializes access to `send(_:)`
/// and `state`.
///
/// Instances of `MealyMachine` are intentionally non-`Sendable`; the wrapper enforces the
/// serial-access invariant. The ``Swift/SendableMetatype`` conformance only marks
/// `MealyMachine.Type` itself as `Sendable` so it can appear in `@Sendable` closure signatures —
/// it makes no claim about instance sendability.
public final class MealyMachine<Action, State, Output>: SendableMetatype
    where Output: MealyOutput<Action>
{
    public private(set) var state: State
    {
        willSet {
            willChangeState(state, newValue)
        }
    }

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

    /// Sends `action` to the state machine, running the reducer and recursively resolving any
    /// synchronous feedback actions reported by ``MealyOutput/synchronousActions()`` until the
    /// returned `Output` contains only asynchronous remainders.
    ///
    /// - Returns: The combined asynchronous-remainder output. Wrappers hand this to their effect manager.
    @discardableResult
    public func send(_ action: Action) -> Output
    {
        let initial = reducer.run(action, &state, ())
        let (syncActions, remainder) = initial.splitSynchronousActions()
        var remainingOutputs = remainder

        for syncAction in syncActions {
            let nestedRemainder = send(syncAction)
            remainingOutputs = remainingOutputs + nestedRemainder
        }
        return remainingOutputs
    }
}
