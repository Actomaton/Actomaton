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
/// A remote caller cannot stream a `send`'s emissions or await its completion: `send` returns
/// `Void`, and a ``SendResults`` (an `AsyncSequence` backed by a local `Task`) cannot cross the
/// wire. This is intentional. When a peer needs results back, the host's reducer sends a *follow-up
/// action* to the caller — the "reverse letter" / action-broadcast pattern — so every streaming or
/// observation channel stays local to whichever node owns it. Cancellation likewise travels as an
/// ordinary action (`send(.cancelXxx)` driving a reducer-side ``Effect/cancel(id:)``).
public distributed actor DistributedActomaton<Action, State, Emission, ActorSystem>
    where Action: Codable & Sendable, State: Codable & Sendable, Emission: Codable & Sendable,
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
