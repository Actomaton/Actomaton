import ActomatonCore
import ActomatonEffect

/// Actor + Automaton = Actomaton.
///
/// `Actomaton` wraps a ``MealyMachine`` specialized with `Output == Effect<Action, Emission>`
/// inside a Swift actor, providing serial isolation for `send(_:)` and `state` access. It owns the
/// ``EffectManager`` and turns the asynchronous-remainder output from ``MealyMachine`` into
/// running Swift Concurrency tasks.
///
/// `Emission` is the typed side-channel value: each `send(_:)` call returns a ``SendResult``
/// whose `AsyncSequence` of `Emission` values is produced by the triggered effects'
/// synchronous `.emit` kinds and async `Outcome` emissions.
public actor Actomaton<Action, State, Emission>
    where Action: Sendable
{
    private let machine: MealyMachine<Action, State, Effect<Action, Emission>>

    private let effectManager: any EffectManager<Action, State, Effect<Action, Emission>>

    public var state: State
    {
        machine.state
    }

    /// Designated initializer that takes an explicit ``EffectManager``.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Effect<Action, Emission>>,
        effectManager: some EffectManager<Action, State, Effect<Action, Emission>>
    )
    {
        self.machine = MealyMachine(
            state: state,
            reducer: reducer
        )
        self.effectManager = effectManager

        effectManager.setUp(
            withSendability: { [weak self] runEffM in
                await self?.runIsolatedEffectManager(runEffM)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks, emit in
                await self?.sendInternal(
                    action,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks,
                    emit: emit
                )
            }
        )
    }

    /// Sends `action` to the underlying ``MealyMachine`` and forwards the resulting output
    /// to ``EffectManager/processSendOutput(id:_:priority:tracksFeedbacks:)``.
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
        let output = machine.send(action)
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
        // `MealyMachine.send` recursively resolves synchronous `.next(Action)` feedbacks
        // because `Effect<Action, Emission>: MealyOutput` exposes `MealyOutput.Action == Action`.
        // The returned `output` contains only the asynchronous remainder plus any synchronous
        // `.emit` kinds (which ride along unchanged).
        let output = machine.send(action)
        return effectManager.processOutput(
            output,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks,
            emit: emit
        )
    }

    /// Runs `runEffM` within this actor's isolation, supplying the underlying ``EffectManager``
    /// so that conformers can mutate their own bookkeeping safely from unstructured tasks without
    /// capturing `self` themselves.
    fileprivate func runIsolatedEffectManager<EffM>(
        _ runEffM: (EffM) -> Void
    ) where EffM: EffectManager<Action, State, Effect<Action, Emission>>
    {
        // Safe downcast from the existential storage to the conformer's concrete `Self`.
        runEffM(effectManager as! EffM)
    }
}
