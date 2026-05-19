import ActomatonCore
import ActomatonEffect

/// Actor + Automaton = Actomaton.
///
/// `Actomaton` wraps a ``MealyMachine`` specialized with `Output == Effect<Action>`
/// inside a Swift actor, providing serial isolation for `send(_:)` and `state` access.
public actor Actomaton<Action, State>
    where Action: Sendable, State: Sendable
{
    private let machine: MealyMachine<Action, State, Effect<Action>>

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

        self.machine.setUp(
            effectManager: effectManager,
            withSendability: { [weak self] runMachine in
                await self?.runIsolatedMachine(runMachine)
            },
            sendAction: { [weak self] action, priority, tracksFeedbacks in
                await self?.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
            }
        )
    }

    /// Sends `action` to the underlying ``MealyMachine``.
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
        machine.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
    }

    /// Runs `runMachine` within this actor's isolation, supplying the underlying ``MealyMachine`` so
    /// that conformers of ``EffectManager`` (reached via ``MealyMachine``) can mutate their own
    /// bookkeeping safely from detached tasks without capturing `self` themselves.
    fileprivate func runIsolatedMachine(
        _ runMachine: (MealyMachine<Action, State, Effect<Action>>) -> Void
    )
    {
        runMachine(machine)
    }
}
