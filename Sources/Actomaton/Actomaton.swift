import ActomatonCore
import ActomatonEffect

/// Actor + Automaton = Actomaton.
///
/// `Actomaton` wraps a ``MealyMachine`` specialized with `Output == Effect<Action>` inside a
/// Swift actor, providing serial isolation for `send(_:)` and `state` access. It owns the
/// ``EffectManager`` and turns the asynchronous-remainder output from ``MealyMachine`` into
/// running Swift Concurrency tasks.
public actor Actomaton<Action, State>
    where Action: Sendable
{
    private let machine: MealyMachine<Action, State, Effect<Action>>

    private let effectManager: any EffectManager<Action, State, Effect<Action>>

    public var state: State
    {
        machine.state
    }

    /// Designated initializer that takes an explicit ``EffectManager``.
    public init(
        state: State,
        reducer: MealyReducer<Action, State, (), Effect<Action>>,
        effectManager: some EffectManager<Action, State, Effect<Action>>
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
            sendAction: { [weak self] action, priority, tracksFeedbacks in
                await self?.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
            }
        )
    }

    /// Sends `action` to the underlying ``MealyMachine`` and forwards the resulting output
    /// to ``EffectManager/processOutput(_:priority:tracksFeedbacks:)``.
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
