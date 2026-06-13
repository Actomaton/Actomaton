import ActomatonCore
import ActomatonEffect
import Synchronization

/// Non-actor driver for ``MealyMachine`` with `Output == Effect<Action, Emission>`, providing
/// synchronous `send(_:)`, `state` and `withState(_:)` for callers that cannot enter an
/// actor isolation — for example, a type conforming to `DistributedActorSystem` whose
/// protocol surface is largely synchronous.
///
/// `MealyDriver` is the "non-actor" sibling of ``Actomaton`` referenced by
/// ``MealyMachine``'s docstring. Both wrappers share the same internals (``MealyMachine`` +
/// an ``EffectManager``) and the same typed side-channel `Emission` semantics; they differ
/// only in how they provide the serial-access invariant that ``MealyMachine`` requires:
///
/// - ``Actomaton`` uses Swift actor isolation.
/// - ``MealyDriver`` uses an internal `Mutex` from the `Synchronization` framework.
///
/// The class is marked `@unchecked Sendable` because ``MealyMachine`` and the underlying
/// ``EffectManager`` are both intentionally non-`Sendable`; the mutex supplies the
/// serial-access invariant they require.
public final class MealyDriver<Action, State, Emission>: @unchecked Sendable
    where Action: Sendable
{
    private let machine: MealyMachine<Action, State, Effect<Action, Emission>>

    private let effectManager: any EffectManager<Action, State, Effect<Action, Emission>>

    private let mutex = Mutex<Void>(())

    /// Designated initializer that takes an explicit ``EffectManager``.
    public init(
        state: State,
        reducer: Reducer<Action, State, (), Emission>,
        effectManager: some EffectManager<Action, State, Effect<Action, Emission>>
    )
    {
        self.machine = MealyMachine(state: state, reducer: reducer)
        self.effectManager = effectManager

        effectManager.setUp(
            withSendability: { [weak self] runEffectManager in
                self?.runIsolatedEffectManager(runEffectManager)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks, emit in
                self?.sendInternal(
                    action,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks,
                    emit: emit
                )
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
    /// to ``EffectManager/processSendOutput(id:_:priority:tracksFeedbacks:)``.
    ///
    /// The reducer is run synchronously under the mutex; the asynchronous-remainder output
    /// is handed to the effect manager *after* the mutex is released, so the manager's
    /// task scheduling never re-enters the mutex from the same call stack.
    ///
    /// - Parameters:
    ///   - id:
    ///     Optional cancellation identifier for the whole `send`. When non-`nil`, the returned
    ///     ``SendResult`` is registered under `id`, so a reducer-side ``Effect/cancel(id:)``
    ///     (or ``Effect/cancel(ids:)``) matching `id` cancels this ``SendResult`` exactly as
    ///     ``SendResult/cancel()`` would — in addition to cancelling effect tasks sharing `id`.
    ///   - priority:
    ///     Priority of the task. If `nil`, the priority will come from `Task.currentPriority`.
    ///   - tracksFeedbacks:
    ///     If `true`, the returned ``SendResult`` will also track feedback effects triggered by
    ///     next actions — so its `AsyncSequence` stays open until those downstream chains
    ///     complete, and recursive ``Effect/Outcome/emit`` values flow into the same stream.
    ///     Default is `false`.
    ///
    /// - Returns:
    ///   A ``SendResult`` exposing both a non-throwing `AsyncSequence` of
    ///   `Result<Emission, any Error>` elements (effect errors are surfaced in-band as `.failure`
    ///   without cancelling sibling effects) and a `cancel()` handle that aborts the entire chain.
    @discardableResult
    public func send(
        id: (any EffectID)? = nil,
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> SendResult<Emission>
    {
        let output = mutex.withLock { _ in machine.send(action) }
        return effectManager.processSendOutput(
            id: id,
            output,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks
        )
    }

    /// Reducer-side dispatch used internally by the recursive feedback path threaded through
    /// ``EffectManager``'s `sendAction` callback. The `emit` parameter is the original caller's
    /// emission sink, so all `Emission` values produced by downstream effects flow into the
    /// single ``SendResult`` returned by the public `send`.
    private func sendInternal(
        _ action: Action,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> Task<(), Never>?
    {
        let output = mutex.withLock { _ in machine.send(action) }
        return effectManager.processOutput(
            output,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks,
            emit: emit
        )
    }

    /// Runs `runEffectManager` under the driver's mutex, supplying the underlying
    /// ``EffectManager`` so that conformers can mutate their own bookkeeping safely from
    /// unstructured tasks without capturing `self` themselves.
    private func runIsolatedEffectManager<EffM>(
        _ runEffectManager: (EffM) -> Void
    ) where EffM: EffectManager<Action, State, Effect<Action, Emission>>
    {
        mutex.withLock { _ in
            // Safe downcast from the existential storage to the conformer's concrete `Self`.
            runEffectManager(effectManager as! EffM)
        }
    }
}
