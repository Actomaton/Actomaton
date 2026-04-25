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

    package let reducer: MealyReducer<Action, State, (), Output>

#if os(WASI) || ACTOMATON_ISOLATED_DEINIT_WORKAROUND
    /// `nonisolated(unsafe)` of `effectManager` so `deinit` can shut it down without relying on
    /// `isolated deinit`, which currently crashes some Swift 6.2.4 toolchains.
    ///
    /// `ACTOMATON_ISOLATED_DEINIT_WORKAROUND` exists for non-WASI builds compiled by the
    /// Swift.org 6.2.4 toolchain, where `isolated deinit` also crashes during SIL lowering.
    package private(set) nonisolated(unsafe) var effectManager: any EffectManager<Action, State, Output>
#else
    /// Core manages effect lifecycle: task creation, queue policies, and cancellation.
    /// Agnostic about reducer and state mutation.
    package private(set) var effectManager: any EffectManager<Action, State, Output>
#endif

    /// Underlying actor that replaces `MealyMachine`'s `unownedExecutor`.
    private let executingActor: any Actor

    /// State change handler, mainly used for synchronizing with `MainActomaton`'s `@Published state`.
    private let willChangeState: (_ isolation: isolated MealyMachine, _ old: State, _ new: State) -> Void

    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Output>,
        effectManager: consuming some EffectManager<Action, State, Output>
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
        effectManager: consuming some EffectManager<Action, State, Output>
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
        effectManager: consuming EffM,
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
        self.executingActor = executingActor
        self.willChangeState = willChangeState

        let weakSelfHolder = _WeakSelfHolder<MealyMachine<Action, State, Output>>()

        effectManager.setUp(
            performIsolated: { [weakSelfHolder] f in
                await weakSelfHolder.value?.performIsolated(f)
            },
            sendAction: { [weakSelfHolder] action, priority, tracksFeedbacks in
                await weakSelfHolder.value?.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
            }
        )

        // IMPORTANT:
        // `self.effectManager` is assigned exactly once, with the already-`setUp` value.
        //
        // - The assignment happens AFTER `effectManager.setUp` because `effectManager` is `consuming`:
        //   this assignment moves it into `self`, after which the local parameter is no longer accessible.
        //
        // - We cannot replace this with an early `self.effectManager = copy effectManager` followed by
        //   in-place `self.effectManager.setUp(...)` for two separate reasons:
        //
        //   (1) `self.effectManager` is typed as the existential `any EffectManager<...>`. Mutating
        //       methods cannot be called on existentials ("Member 'setUp' cannot be used on value of
        //       type 'any EffectManager<...>'; consider using a generic constraint instead"), since
        //       `Self` is erased. The `effectManager` parameter (typed as `EffM`) has no such
        //       restriction, so we set up the parameter instead.
        //
        //   (2) Even if (1) were sidestepped by re-assigning after `setUp`, the `[weak self]` capture
        //       inside `setUp`'s closures escapes `self` and ends the actor's phase-1 free-write
        //       window. The second `self.effectManager = ...` would then be rejected as "Cannot access
        //       property 'effectManager' here in nonisolated initializer". `_WeakSelfHolder` exists to
        //       avoid this transition by routing the capture through a separate class instance, so
        //       the single store below stays inside phase 1.
        self.effectManager = effectManager

        weakSelfHolder.value = self
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

    /// Runs `f` within `self`'s isolation, projecting the existential `effectManager`
    /// back to its concrete `EffM` type so conformers can mutate themselves through `inout`.
    ///
    /// Used by ``EffectManager`` conformers to re-enter actor isolation from detached tasks.
    private func performIsolated<EffM>(
        _ f: @Sendable (isolated any Actor, inout EffM) -> Void
    ) where EffM: EffectManager<Action, State, Output>
    {
        var typed = self.effectManager as! EffM
        f(self, &typed)
        self.effectManager = typed
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

/// Weak holder used to capture a `MealyMachine` reference inside `EffectManager.setUp` closures
/// without referencing `self` directly during init — see comment in `MealyMachine.init`.
private final class _WeakSelfHolder<T>: @unchecked Sendable
    where T: AnyObject
{
    weak var value: T?
}
