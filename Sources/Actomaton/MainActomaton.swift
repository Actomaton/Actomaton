import Foundation
#if !DISABLE_COMBINE && canImport(Combine)
import Combine
#endif

/// ``Actomaton`` wrapper that uses `MainActor`'s executor as its custom executor.
@MainActor
public final class MainActomaton<Action, State>
    where Action: Sendable, State: Sendable
{
#if !DISABLE_COMBINE && canImport(Combine)
    @Published
    public private(set) var state: State
#else
    public var state: State
    {
        self.actomaton.assumeIsolated { actomaton in
            actomaton.state
        }
    }
#endif

    private let actomaton: Actomaton<Action, State>

    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: Reducer<Action, State, ()>,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    )
    {
        var willChangeState: (@MainActor (_ old: State, _ new: State) -> Void)?

        self.actomaton = Actomaton(
            state: state,
            reducer: reducer,
            effectManager: EffectQueueManager<Action, State>(effectContext: effectContext),
            executingActor: MainActor.shared,
            willChangeState: { @Sendable _, old, new in
                MainActor.assumeIsolated {
                    willChangeState?(old, new)
                }
            },
        )

#if !DISABLE_COMBINE && canImport(Combine)
        // Set `MainActomaton`'s `@Published` initial state.
        self.state = state

        // Update `MainActomaton`'s `@Published` state.
        willChangeState = { [weak self] _, new in
            self?.state = new
        }
#endif
    }

    /// Initializer with `environment`.
    public convenience init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment,
        effectContext: EffectContext = .init(clock: ContinuousClock())
    ) where Environment: Sendable
    {
        self.init(
            state: state,
            reducer: Reducer { action, state, _ in
                reducer.run(action, &state, environment)
            },
            effectContext: effectContext
        )
    }

    /// Sends `action` to `Actomaton`.
    @discardableResult
    public func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), any Error>?
    {
        self.actomaton.assumeIsolated { actomaton in
            actomaton.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
        }
    }
}
