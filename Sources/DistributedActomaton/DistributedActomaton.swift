import Actomaton
import ActomatonEffect
import Distributed

/// `DistributedActomaton` wraps a ``MealyMachine`` specialized with
/// `Output == Effect<Action, Emission>` inside a Swift distributed actor, providing serial
/// isolation for `send(_:)` and `state` access. It owns the ``EffectManager`` and turns the
/// asynchronous-remainder output from ``MealyMachine`` into running Swift Concurrency tasks.
///
/// ## Serialization requirements
///
/// `Action`, `State`, and `Emission` must be `Codable`, and the actor system's
/// `SerializationRequirement` must be `any Codable` (the `DistributedActorSystem<any Codable>`
/// primary-associated-type constraint). This makes the compiler verify at declaration and call
/// sites that every distributed method's parameters and results can actually cross the wire —
/// without the constraint, an unconstrained generic `ActorSystem` would skip the
/// `SerializationRequirement` check entirely and defer failures to runtime on real remote calls.
/// `Emission = Never` works because `Never` conforms to `Codable` (SE-0396).
///
/// ## Distributed face vs local face
///
/// The distributed methods — ``send(_:id:)`` and ``state`` — expose only what is meaningful to a
/// remote peer. The richer local API — ``sendLocal(_:id:priority:tracksFeedbacks:)`` returning a
/// ``SendResults`` — is reachable through `whenLocal { local in local.sendLocal(...) }`.
/// `TaskPriority` is deliberately absent from the distributed face: although it is `Codable`, it is
/// a *local scheduling hint* for the effect tasks, and a remote caller has no business steering the
/// host's scheduler.
///
/// ## Remote observation is a non-goal
///
/// A remote caller cannot *stream* a `send`'s emissions incrementally: a ``SendResults`` (an
/// `AsyncSequence` backed by a local `Task`) cannot cross the wire, so `send` returns `Void`. This
/// is intentional — every live streaming/observation channel stays local to whichever node owns it.
/// A caller that can wait for the chain to settle may instead use
/// ``sendCollectAll(_:id:tracksFeedbacks:)`` (or ``sendCollectFirst(_:id:tracksFeedbacks:)`` for
/// just the first outcome), which awaits the effects on the host and returns the collected outcomes
/// as `Codable` ``DistributedEffectResult`` values (so they cross the wire). For truly incremental
/// or push-based results, the host's reducer sends a
/// *follow-up action* back to the caller — the "reverse letter" / action-broadcast pattern.
/// Cancellation likewise travels as an ordinary action (`send(.cancelXxx)` driving a reducer-side
/// ``Effect/cancel(id:)``).
public distributed actor DistributedActomaton<Action, State, Emission, ActorSystem>
    where Action: Codable & Sendable, State: Codable & Sendable,
    ActorSystem: DistributedActorSystem<any Codable>
{
    private let machine: MealyMachine<Action, State, Effect<Action, Emission>>

    private let effectManager: any EffectManager<Action, State, Effect<Action, Emission>>

    public distributed var state: State
    {
        machine.state
    }

    /// Designated initializer that takes an explicit ``EffectManager``.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Effect<Action, Emission>>,
        effectManager: some EffectManager<Action, State, Effect<Action, Emission>>,
        actorSystem: ActorSystem
    )
    {
        self.machine = MealyMachine(
            state: state,
            reducer: reducer
        )
        self.effectManager = effectManager
        self.actorSystem = actorSystem

        effectManager.setUp(
            withSendability: { [weak self] runEffM in
                await self?.whenLocal { self_ in
                    self_.runIsolatedEffectManager(runEffM)
                }
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks, emit in
                await self?.whenLocal { self_ in
                    self_.sendInternal(
                        action,
                        priority: priority,
                        tracksFeedbacks: tracksFeedbacks,
                        emit: emit
                    )
                } ?? nil
            }
        )
    }

    // MARK: - Distributed face

    /// Sends `action` to the underlying ``MealyMachine`` in a fire-and-forget manner,
    /// forwarding the resulting output to the ``EffectManager``.
    ///
    /// The return type is `Void` because a `distributed func`'s return type must satisfy the
    /// actor system's `SerializationRequirement` (`any Codable`), and neither `Task` nor
    /// ``SendResults`` is `Codable`. For local access to the triggered effect chain (emissions,
    /// cancellation), use ``sendLocal(_:id:priority:tracksFeedbacks:)`` via `whenLocal { ... }`. A
    /// remote caller observes results not through a return value but by receiving a follow-up
    /// action that the host's reducer sends back (the action-broadcast / "reverse letter" pattern).
    ///
    /// To instead *await* the triggered effects and get their collected outcomes back across the
    /// wire, use ``sendCollectAll(_:id:tracksFeedbacks:)`` (or ``sendCollectFirst(_:id:tracksFeedbacks:)``)
    /// — their `Codable` ``DistributedEffectResult`` returns cross the wire, unlike the live
    /// ``SendResults`` stream this fire-and-forget variant discards.
    ///
    /// - Parameters:
    ///   - action: The action to deliver to the host's reducer.
    ///   - id:
    ///     Optional cancellation tag for the whole send (see ``DistributedSendID``). When non-`nil`,
    ///     the triggered effect chain is registered under `id`, so a reducer-side
    ///     ``Effect/cancel(id:)`` matching `id` aborts it — typically driven by routing a later
    ///     cancel action back to this actor.
    public distributed func send(
        _ action: Action,
        id: DistributedSendID? = nil
    )
    {
        sendLocal(action, id: id)
    }

    /// Collecting counterpart of ``send(_:id:)``: sends `action`, awaits completion of the
    /// triggered effect chain, and returns its **collected outcomes** — successes *and* failures,
    /// in arrival order — as serializable ``DistributedEffectResult`` values.
    ///
    /// With the default `tracksFeedbacks: false` this covers only the directly-triggered effects'
    /// own work (sleep + run + feedback *dispatch*); pass `true` to also await — and collect
    /// results from — their downstream feedback descendants.
    ///
    /// The actor stays reentrant while suspended awaiting the chain, so effects that hop back onto
    /// this actor (feedback dispatch, queue bookkeeping) still make progress — no deadlock.
    ///
    /// `[DistributedEffectResult<Emission>]` crosses the wire because it is `Codable`. The live
    /// ``SendResults`` `AsyncSequence` cannot, and its ``SendResults/allResults`` —
    /// `[Result<Emission, any Error>]` — is not `Codable` either (neither `Result` nor `any Error`
    /// is), so each element is bridged into the serializable envelope (failures stringified). This
    /// returns the *fully collected* results once the chain settles, not an incremental stream.
    ///
    /// - Important: This keeps the distributed call open (suspended, not thread-blocked) for the
    ///   entire effect duration. A remote caller therefore stays suspended until the host's effects
    ///   settle, which can hit the actor system's call timeout for long-running effects (the effects
    ///   keep running on the host regardless). Prefer ``send(_:id:)`` when fire-and-forget is
    ///   acceptable.
    ///
    /// - Parameters:
    ///   - action: The action to deliver to the host's reducer.
    ///   - id: Optional cancellation tag for the whole send (see ``send(_:id:)``).
    ///   - tracksFeedbacks:
    ///     If `true`, also awaits and collects results from the downstream feedback chains
    ///     triggered by next actions, not just the directly-triggered effects' own work. Default
    ///     is `false`.
    /// - Returns: Every outcome produced by this `action`'s effect chain, in arrival order. Empty
    ///   if the chain produced nothing (or was cancelled before producing any).
    public distributed func sendCollectAll(
        _ action: Action,
        id: DistributedSendID? = nil,
        tracksFeedbacks: Bool = false
    ) async -> [DistributedEffectResult<Emission>]
        where Emission: Codable & Sendable
    {
        await sendLocal(action, id: id, tracksFeedbacks: tracksFeedbacks)
            .allResults
            .map(DistributedEffectResult.init)
    }

    /// Like ``sendCollectAll(_:id:tracksFeedbacks:)`` but returns only the **first** outcome the
    /// effect chain produces (success or failure), as a serializable ``DistributedEffectResult``.
    ///
    /// Returns as soon as the first outcome arrives — unlike ``sendCollectAll(_:id:tracksFeedbacks:)``
    /// it does not await the whole chain. The remaining effects keep running on the host
    /// (fire-and-forget); they are neither awaited nor cancelled. Pass `id` and route a cancel action
    /// back if you need to stop them.
    ///
    /// - Parameters:
    ///   - action: The action to deliver to the host's reducer.
    ///   - id: Optional cancellation tag for the whole send (see ``send(_:id:)``).
    ///   - tracksFeedbacks:
    ///     If `true`, the first outcome may also come from a downstream feedback chain, not just the
    ///     directly-triggered effects. Default is `false`.
    /// - Returns: The first outcome produced by this `action`'s effect chain, or `nil` if the chain
    ///   produced nothing (or was cancelled before producing any).
    public distributed func sendCollectFirst(
        _ action: Action,
        id: DistributedSendID? = nil,
        tracksFeedbacks: Bool = false
    ) async -> DistributedEffectResult<Emission>?
        where Emission: Codable & Sendable
    {
        await sendLocal(action, id: id, tracksFeedbacks: tracksFeedbacks)
            .firstResult
            .map(DistributedEffectResult.init)
    }

    // MARK: - Local face

    /// Local-only variant of ``send(_:id:)`` that returns the full ``SendResults``. Use through
    /// `whenLocal { local in local.sendLocal(...) }` when the caller needs to observe emissions
    /// and in-band errors, await completion, or cancel the resulting effects.
    ///
    /// - Parameters:
    ///   - action: The action to deliver to the underlying ``MealyMachine``.
    ///   - id:
    ///     Optional cancellation identifier for the whole `send`. When non-`nil`, the returned
    ///     ``SendResults`` is registered under `id`, so a reducer-side ``Effect/cancel(id:)`` (or
    ///     ``Effect/cancel(ids:)``) matching `id` cancels this ``SendResults`` exactly as
    ///     ``SendResults/cancel()`` would — in addition to cancelling effect tasks sharing `id`.
    ///     Unlike the distributed face this accepts any ``EffectID``, not just ``DistributedSendID``.
    ///   - priority:
    ///     Priority of the task. If `nil`, the priority will come from `Task.currentPriority`.
    ///   - tracksFeedbacks:
    ///     If `true`, the returned ``SendResults`` will also track feedback effects triggered by
    ///     next actions — so its `AsyncSequence` stays open until those downstream chains
    ///     complete, and recursive emissions flow into the same stream. Default is `false`.
    ///
    /// - Returns:
    ///   A ``SendResults`` exposing both a non-throwing `AsyncSequence` of
    ///   `Result<Emission, any Error>` elements (effect errors are surfaced in-band as `.failure`
    ///   without cancelling sibling effects) and a `cancel()` handle that aborts the entire chain.
    @discardableResult
    public func sendLocal(
        _ action: Action,
        id: (any EffectID)? = nil,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> SendResults<Emission>
    {
        let output = machine.send(action)
        return effectManager.processSendOutput(
            output,
            id: id,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks
        )
    }

    // MARK: - Internals

    /// Reducer-side dispatch used internally by the recursive feedback path threaded through
    /// ``EffectManager``'s `sendAction` callback. The `emit` parameter is the original caller's
    /// emission sink, so all `Emission` values produced by downstream effects flow into the
    /// single ``SendResults`` returned by ``sendLocal(_:id:priority:tracksFeedbacks:)``.
    private func sendInternal(
        _ action: Action,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> Task<(), Never>?
    {
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
