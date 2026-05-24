import ActomatonCore
import ActomatonEffect
import Synchronization

/// Non-actor driver for ``MealyMachine`` with `Output == Effect<Action>`, providing
/// synchronous `send(_:)`, `state` and `withState(_:)` for callers that cannot enter an
/// actor isolation — for example, a type conforming to `DistributedActorSystem` whose
/// protocol surface is largely synchronous.
///
/// `MealyDriver` is the "non-actor" sibling of ``Actomaton`` referenced by
/// ``MealyMachine``'s docstring. Both wrappers share the same internals (`MealyMachine` +
/// an ``EffectManager``); they differ only in how they provide the serial-access invariant
/// that ``MealyMachine`` requires:
///
/// - ``Actomaton`` uses Swift actor isolation.
/// - ``MealyDriver`` uses an internal `Mutex` from the `Synchronization` framework.
///
/// The class is marked `@unchecked Sendable` because ``MealyMachine`` and the underlying
/// ``EffectManager`` are both intentionally non-`Sendable`; the mutex supplies the
/// serial-access invariant they require.
public final class MealyDriver<Action, State>: @unchecked Sendable
    where Action: Sendable
{
    private let machine: MealyMachine<Action, State, Effect<Action>>

    private let effectManager: any EffectManager<Action, State, Effect<Action>>

    private let mutex = Mutex<Void>(())

    /// Designated initializer that takes an explicit ``EffectManager``.
    public init(
        state: State,
        reducer: Reducer<Action, State, ()>,
        effectManager: some EffectManager<Action, State, Effect<Action>>
    )
    {
        self.machine = MealyMachine(state: state, reducer: reducer)
        self.effectManager = effectManager

        effectManager.setUp(
            withSendability: { [weak self] runEffectManager in
                self?.runIsolatedEffectManager(runEffectManager)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks in
                self?.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
            }
        )
    }

    /// Synchronous snapshot of the current `state`. The returned value is a copy taken
    /// under the mutex; mutating it does not affect the driver's internal state.
    public var state: State {
        mutex.withLock { _ in machine.state }
    }

    /// Run `body` against the current `state` while holding the driver's mutex. Use this
    /// when you need to read multiple fields atomically.
    public func withState<R>(_ body: (State) -> R) -> R {
        mutex.withLock { _ in body(machine.state) }
    }

    /// Sends `action` to the underlying ``MealyMachine`` and forwards the resulting output
    /// to ``EffectManager/processOutput(_:priority:tracksFeedbacks:)``.
    ///
    /// The reducer is run synchronously under the mutex; the asynchronous-remainder output
    /// (`Effect<Action>`) is handed to the effect manager *after* the mutex is released, so
    /// the manager's task scheduling never re-enters the mutex from the same call stack.
    ///
    /// - Parameters:
    ///   - priority:
    ///     Priority of the task. If `nil`, the priority will come from `Task.currentPriority`.
    ///   - tracksFeedbacks:
    ///     If `true`, the returned `Task` will also track feedback effects triggered by
    ///     subsequent actions, so that wait-for-all and cancellation are possible.
    ///     Default is `false`.
    ///
    /// - Returns:
    ///   Unified task that can handle (wait for or cancel) all combined effects triggered
    ///   by `action` in the reducer.
    @discardableResult
    public func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), any Error>?
    {
        let output = mutex.withLock { _ in machine.send(action) }
        return effectManager.processOutput(output, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Runs `runEffectManager` under the driver's mutex, supplying the underlying
    /// ``EffectManager`` so that conformers can mutate their own bookkeeping safely from
    /// detached tasks without capturing `self` themselves.
    private func runIsolatedEffectManager<EffM>(
        _ runEffectManager: (EffM) -> Void
    ) where EffM: EffectManager<Action, State, Effect<Action>>
    {
        mutex.withLock { _ in
            // Safe downcast from the existential storage to the conformer's concrete `Self`.
            runEffectManager(effectManager as! EffM)
        }
    }
}
