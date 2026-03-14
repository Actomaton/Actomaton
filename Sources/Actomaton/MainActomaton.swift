import Foundation
#if !DISABLE_COMBINE && canImport(Combine)
import Combine
#endif

/// ``Actomaton`` wrapper that uses `MainActor`'s executor as its custom executor.
@MainActor
package final class MainActomaton<Action, State>
    where Action: Sendable, State: Sendable
{
#if !DISABLE_COMBINE && canImport(Combine)
    @Published
    package private(set) var state: State

    package var statePublisher: AnyPublisher<State, Never> {
        self.$state.eraseToAnyPublisher()
    }
#else
    package var state: State
    {
        self.actomaton.assumeIsolated { actomaton in
            actomaton.state
        }
    }
#endif

    private let actomaton: Actomaton<Action, State>

    /// Initializer without `environment`.
    package init(
        state: State,
        reducer: Reducer<Action, State, ()>
    )
    {
        var willChangeState: (@MainActor (_ old: State, _ new: State) -> Void)?

        self.actomaton = Actomaton(
            state: state,
            reducer: reducer,
            executingActor: MainActor.shared,
            willChangeState: { @Sendable _, old, new in
                MainActor.assumeIsolated {
                    willChangeState?(old, new)
                }
            }
        )

#if !DISABLE_COMBINE && canImport(Combine)
        // Set `MainActomaton`'s `@Published` initial state.
        self.state = state

        // Update `MainActomaton`'s `@Published` state.
        willChangeState = { [weak self] old, new in
            self?.state = new
        }
#endif
    }

    /// Initializer with `environment`.
    package convenience init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment
    ) where Environment: Sendable
    {
        self.init(state: state, reducer: Reducer { action, state, _ in
            reducer.run(action, &state, environment)
        })
    }

    /// Sends `action` to `Actomaton`.
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
    package func send(
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
