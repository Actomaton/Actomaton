import Actomaton
import ActomatonEffect
import Distributed

/// `DistributedActomaton` wraps a ``MealyMachine`` specialized with `Output == Effect<Action>` inside a
/// Swift distributed actor, providing serial isolation for `send(_:)` and `state` access. It owns the
/// ``EffectManager`` and turns the asynchronous-remainder output from ``MealyMachine`` into
/// running Swift Concurrency tasks.
public distributed actor DistributedActomaton<Action, State, ActorSystem>
    where Action: Sendable, State: Sendable, ActorSystem: DistributedActorSystem
{
    private let machine: MealyMachine<Action, State, Effect<Action>>

    private let effectManager: any EffectManager<Action, State, Effect<Action>>

    public distributed var state: State
    {
        machine.state
    }

    /// Designated initializer that takes an explicit ``EffectManager``.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Effect<Action>>,
        effectManager: some EffectManager<Action, State, Effect<Action>>,
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
            sendAction: { [weak self] action, priority, tracksFeedbacks in
                return await self?.whenLocal { self_ in
                    self_.sendLocal(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
                } ?? nil
            }
        )
    }

    /// Sends `action` to the underlying ``MealyMachine`` and forwards the resulting output
    /// to ``EffectManager/processOutput(_:priority:tracksFeedbacks:)``.
    ///
    /// The return type is `Void` (rather than `Task<(), any Error>?` like
    /// ``Actomaton/send(_:priority:tracksFeedbacks:)``)
    /// because a `distributed func`'s return type must satisfy the actor system's
    /// `SerializationRequirement` (typically `Codable`), and `Task` is not `Codable`.
    /// For local-only access to the launched effect task, use ``sendLocal(_:priority:tracksFeedbacks:)``
    /// via `whenLocal { ... }`.
    ///
    /// - Parameters:
    ///   - priority:
    ///     Priority of the task. If `nil`, the priority will come from `Task.currentPriority`.
    ///   - tracksFeedbacks:
    ///     If `true`, the underlying effect task will also track its feedback effects that are
    ///     triggered by next actions, so that wait-for-all and cancellations are possible
    ///     (observable only through the local API).
    ///     Default is `false`.
    public distributed func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    )
    {
        sendLocal(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Local-only variant of ``send(_:priority:tracksFeedbacks:)`` that returns the launched
    /// effect `Task`. Use through `whenLocal { local in local.sendLocal(...) }` when the caller
    /// needs to `await` or cancel the resulting effects.
    @discardableResult
    public func sendLocal(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), any Error>?
    {
        let output = machine.send(action)
        return effectManager.processOutput(output, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Runs `runEffM` within this actor's isolation, supplying the underlying ``EffectManager``
    /// so that conformers can mutate their own bookkeeping safely from detached tasks without
    /// capturing `self` themselves.
    fileprivate func runIsolatedEffectManager<EffM>(
        _ runEffM: (EffM) -> Void
    ) where EffM: EffectManager<Action, State, Effect<Action>>
    {
        // Safe downcast from the existential storage to the conformer's concrete `Self`.
        runEffM(effectManager as! EffM)
    }

    isolated deinit
    {
        effectManager.shutDown()
    }
}
