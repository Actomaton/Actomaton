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
{
    public private(set) var state: State

    private let reducer: MealyReducer<Action, State, (), Output>

    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Output>
    )
    {
        self.state = state
        self.reducer = reducer
    }

    /// Initializer with `environment`.
    public convenience init<Environment>(
        state: State,
        reducer: MealyReducer<Action, State, Environment, Output>,
        environment: Environment
    ) where Environment: Sendable
    {
        self.init(
            state: state,
            reducer: MealyReducer { action, state, _ in
                reducer.run(action, &state, environment)
            }
        )
    }
}

// MARK: - MealyMachine + run (Output)

extension MealyMachine
{
    /// Runs the reducer once for `action` and returns the resulting `Output` as-is.
    ///
    /// This is the primitive single-step operation. It does NOT resolve synchronous feedback,
    /// because `Output` is not constrained to ``MealyOutput`` here. If your `Output` conforms
    /// to ``MealyOutput``, prefer ``send(_:)`` (defined in a constrained extension below),
    /// which composes ``run(_:)`` with recursive feedback resolution.
    @discardableResult
    public func run(_ action: Action) -> Output
    {
        reducer.run(action, &state, ())
    }
}

// MARK: - MealyMachine + send (MealyOutput)

extension MealyMachine where Output: MealyOutput, Output.Action == Action
{
    /// Sends `action` to the state machine, running the reducer and recursively resolving any
    /// synchronous feedback actions reported by ``MealyOutput/splitSynchronousActions()``
    /// until the returned `Output` contains only asynchronous remainders.
    ///
    /// Built on top of ``run(_:)``: runs the reducer once, then re-feeds each synchronous
    /// action recursively through `send(_:)`, accumulating asynchronous remainders.
    ///
    /// - Returns: The combined asynchronous-remainder output. Wrappers hand this to their effect manager.
    @discardableResult
    public func send(_ action: Action) -> Output
    {
        let initial = run(action)
        let (syncActions, remainder) = initial.splitSynchronousActions()
        var remainingOutputs = remainder

        for syncAction in syncActions {
            let nestedRemainder = send(syncAction)
            remainingOutputs = remainingOutputs + nestedRemainder
        }
        return remainingOutputs
    }
}
