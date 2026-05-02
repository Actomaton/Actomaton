import Foundation

/// Deterministic finite state machine that receives "action" and with "current state" transform to "next state" &
/// additional "output",
/// which then generates Swift Concurrency side-effects via ``EffectManager``.
public actor MealyMachine<Action, State, Output>
{
#if !DISABLE_COMBINE && canImport(Combine)
    @Published
    public private(set) var state: State
    {
        willSet {
            willChangeState(#isolation, state, newValue)
        }
    }
#else
    public private(set) var state: State
    {
        willSet {
            willChangeState(#isolation, state, newValue)
        }
    }
#endif

    private let reducer: MealyReducer<Action, State, (), Output>

#if os(WASI) || ACTOMATON_ISOLATED_DEINIT_WORKAROUND
    /// `nonisolated(unsafe)` of `effectManager` so `deinit` can shut it down without relying on
    /// `isolated deinit`, which currently crashes some Swift 6.2.4 toolchains.
    ///
    /// `ACTOMATON_ISOLATED_DEINIT_WORKAROUND` exists for non-WASI builds compiled by the
    /// Swift.org 6.2.4 toolchain, where `isolated deinit` also crashes during SIL lowering.
    private nonisolated(unsafe) let effectManager: any EffectManager<Action, State, Output>
#else
    /// Core manages effect lifecycle: task creation, queue policies, and cancellation.
    /// Agnostic about reducer and state mutation.
    private let effectManager: any EffectManager<Action, State, Output>
#endif

    /// Underlying actor that replaces `MealyMachine`'s `unownedExecutor`.
    private let executingActor: any Actor

    /// State change handler, mainly used for synchronizing with `MainActomaton`'s `@Published state`.
    private let willChangeState: (_ isolation: isolated MealyMachine, _ old: State, _ new: State) -> Void

    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Output>,
        effectManager: some EffectManager<Action, State, Output>
    ) where Action: Sendable
    {
        self.init(
            state: state,
            reducer: reducer,
            effectManager: effectManager,
            executingActor: DefaultExecutingActor()
        )
    }

    /// Initializer with `environment`.
    public init<Environment>(
        state: State,
        reducer: MealyReducer<Action, State, Environment, Output>,
        environment: Environment,
        effectManager: some EffectManager<Action, State, Output>
    ) where Action: Sendable, Environment: Sendable
    {
        self.init(
            state: state,
            reducer: MealyReducer { action, state, _ in
                reducer.run(action, &state, environment)
            },
            effectManager: effectManager,
            executingActor: DefaultExecutingActor()
        )
    }

    /// Initializer with custom `executingActor`.
    /// Used for ``MainActomaton`` construction.
    package init<EffM>(
        state: State,
        reducer: MealyReducer<Action, State, (), Output>,
        effectManager: EffM,
        executingActor: any Actor,
        willChangeState: @escaping (
            _ isolation: isolated MealyMachine, _ old: State, _ new: State
        ) -> Void = { _, _, _ in }
    ) where Action: Sendable, EffM: EffectManager<Action, State, Output>
    {
#if !DISABLE_COMBINE && canImport(Combine)
        self._state = Published(initialValue: state)
#else
        self.state = state
#endif
        self.reducer = reducer
        self.effectManager = effectManager
        self.executingActor = executingActor
        self.willChangeState = willChangeState

        effectManager.setUp(
            performIsolated: { [weak self] f in
                await self?.performIsolated(f)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks in
                await self?.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
            }
        )
    }

#if os(WASI) || ACTOMATON_ISOLATED_DEINIT_WORKAROUND
    deinit
    {
        effectManager.shutDown()
    }
#else
    isolated deinit
    {
        effectManager.shutDown()
    }
#endif

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
        let output_ = effectManager.preprocessOutput(output) { action in
            reducer.run(action, &state, ())
        }
        return effectManager.processOutput(output_, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Runs a block within `self`'s isolation with `EffM` force-casting.
    /// This method is a proof that `effectManager` is owned and protected by `self`.
    ///
    /// Used by ``EffectManager`` conformers to re-enter actor isolation from detached tasks.
    private func performIsolated<EffM>(
        _ f: @Sendable (isolated any Actor, EffM) -> Void
    ) where EffM: EffectManager<Action, State, Output>
    {
        f(self, self.effectManager as! EffM)
    }
}

extension MealyMachine
{
    public nonisolated var unownedExecutor: UnownedSerialExecutor
    {
        executingActor.unownedExecutor
    }
}

// MARK: - Private

/// Underlying actor for retrieving its executor to use as `MealyMachine`'s default executor.
private actor DefaultExecutingActor {}
