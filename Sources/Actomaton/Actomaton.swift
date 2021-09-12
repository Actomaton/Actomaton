import Foundation

/// Actor + Automaton = Actomaton.
///
/// Deterministic finite state machine that receives "action"
/// and with "current state" transform to "next state" & additional "effect".
public actor Actomaton<Action, State>
{
#if os(Linux)
    public private(set) var state: State
#else
    @Published
    public private(set) var state: State
#endif

    private let reducer: Reducer<Action, State, ()>

    private var runningTasks: [EffectID: Task<(), Never>] = [:]

    /// Initializer without `environment`.
    public init(
        state: State,
        reducer: Reducer<Action, State, ()>
    )
    {
        self.state = state
        self.reducer = reducer
    }

    /// Initializer with `environment`.
    public convenience init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment
    )
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
    public func send(
        _ action: Action,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Never>?
    {
        let effect = reducer.run(action, &state, ())

        for cancel in effect.cancels {
            for id in runningTasks.keys {
                if cancel(id) {
                    let previousTask = runningTasks.removeValue(forKey: id)
                    previousTask?.cancel()
                }
            }
        }

        let singles = effect.singles
        let sequences = effect.sequences

        guard !singles.isEmpty || !sequences.isEmpty else { return nil }

        var tasks: [Task<(), Never>] = []

        for single in singles {
            // Cancel previous running task with same `EffectID`.
            if let id = single.id {
                let previousTask = runningTasks.removeValue(forKey: id)
                previousTask?.cancel()
            }

            let task = Task(priority: priority) {
                let nextAction = await single.run()

                // Feed back `nextAction`.
                if let nextAction = nextAction, !Task.isCancelled {
                    let feedbackTask = send(nextAction, priority: priority, tracksFeedbacks: tracksFeedbacks)
                    if tracksFeedbacks {
                        await feedbackTask?.value
                    }
                }
            }

            // Register task.
            if let id = single.id {
                runningTasks[id] = task
            }

            tasks.append(task)
        }

        for sequence in sequences {
            // Cancel previous running task with same `EffectID`.
            if let id = sequence.id {
                let previousTask = runningTasks.removeValue(forKey: id)
                previousTask?.cancel()
            }

            let task = Task(priority: priority) {
                do {
                    var feedbackTasks: [Task<(), Never>] = []

                    for try await nextAction in sequence.sequence {
                        if Task.isCancelled { break }

                        // Feed back `nextAction`.
                        let feedbackTask = send(nextAction, priority: priority, tracksFeedbacks: tracksFeedbacks)

                        if let feedbackTask = feedbackTask {
                            feedbackTasks.append(feedbackTask)
                        }
                    }

                    if tracksFeedbacks {
                        await withTaskGroup(of: Void.self) { group in
                            for feedbackTask in feedbackTasks {
                                group.addTask(priority: priority) {
                                    await feedbackTask.value
                                }
                            }

                            await group.waitForAll()
                        }
                    }

                } catch {
                    // print("[Actomaton] Warning: AsyncSequence error is ignored: \(error)")
                }
            }

            // Register task.
            if let id = sequence.id {
                runningTasks[id] = task
            }

            tasks.append(task)
        }

        let tasks_ = tasks

        // Unifies `tasks`.
        return Task {
            await withTaskGroup(of: Void.self) { group in
                for task in tasks_ {
                    await withTaskCancellationHandler {
                        group.addTask {
                            await task.value
                        }
                    } onCancel: {
                        task.cancel()
                    }
                }
                await group.waitForAll()
            }
        }
    }
}
