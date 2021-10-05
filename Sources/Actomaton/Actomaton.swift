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

    /// State-transforming function wrapper that is triggered by Action.
    private let reducer: Reducer<Action, State, ()>

    /// Effect-identified tasks for manual cancellation.
    private var idTasks: [EffectID: Set<Task<(), Never>>] = [:]

    /// Effect-queue-designated tasks for automatic cancellation & suspension.
    private var queues: [EffectQueue: [Task<(), Never>]] = [:]

    /// Suspended effects.
    private var pendingEffectKinds: [EffectQueue: [Effect<Action>.Kind]] = [:]

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

    deinit
    {
        Debug.print("[deinit] \(String(format: "%p", ObjectIdentifier(self).hashValue))")

        for idTask in self.idTasks {
            for task in idTask.value {
                task.cancel()
            }
        }

        for queue in self.queues {
            for task in queue.value {
                task.cancel()
            }
        }
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
        Debug.print("[send] \(action), priority = \(String(describing: priority)), tracksFeedbacks = \(tracksFeedbacks)")

        let effect = reducer.run(action, &state, ())

        var tasks: [Task<(), Never>] = []

        for effectKind in effect.kinds {
            if let task = performEffectKind(effectKind, priority: priority, tracksFeedbacks: tracksFeedbacks) {
                tasks.append(task)
            }
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

// MARK: - Private

extension Actomaton
{
    private func performEffectKind(
        _ effectKind: Effect<Action>.Kind,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Never>?
    {
        switch effectKind {
        case let .single(single):
            guard self.checkQueuePolicy(effectKind: effectKind) else { return nil }

            return makeTask(single: single, priority: priority, tracksFeedbacks: tracksFeedbacks)

        case let .sequence(sequence):
            guard self.checkQueuePolicy(effectKind: effectKind) else { return nil }

            return makeTask(sequence: sequence, priority: priority, tracksFeedbacks: tracksFeedbacks)

        case let .cancel(predicate):
            for id in idTasks.keys {
                if predicate(id), let previousTasks = idTasks.removeValue(forKey: id) {
                    for previousTask in previousTasks {
                        previousTask.cancel()
                    }
                }
            }

            return nil
        }
    }

    /// Checks `EffectQueuePolicy`, dropping old running tasks or enqueue new effect to pending buffer if needed.
    /// - Returns: Flag whether `effectKind` can be immediately executed as `Task` or not.
    private func checkQueuePolicy(effectKind: Effect<Action>.Kind) -> Bool
    {
        guard let queue = effectKind.queue else { return true }

        switch queue.effectQueuePolicy {
        case let .runNewest(maxCount):
            // NOTE: +1 to make a space for new effect.
            let droppingCount = (self.queues[queue]?.count ?? 0) - maxCount + 1
            if droppingCount > 0 {
                for _ in 0 ..< droppingCount {
                    let droppingTask = self.queues[queue]?.removeFirst()
                    Debug.print("[checkQueuePolicy] [runNewest] Cancel old task")
                    droppingTask?.cancel()
                }
            }

            // `Task` should be created.
            return true

        case let .runOldest(maxCount, overflowPolicy):
            let overflowCount = (self.queues[queue]?.count ?? 0) - maxCount
            if overflowCount >= 0 {
                if overflowPolicy == .suspendNew {
                    let queue = queue
                    let maxCount = maxCount
                    let currentTaskCount = self.queues[queue]?.count ?? 0

                    if currentTaskCount >= maxCount {
                        // Enqueue to pending buffer.
                        Debug.print("[checkQueuePolicy] [runOldest-suspendNew] Enqueue to pending buffer")
                        self.pendingEffectKinds[queue, default: []].append(effectKind)
                    }
                }

                // Overflown, so `Task` should NOT be created.
                return false
            }
            else {
                // `Task` should be created.
                return true
            }
        }
    }

    /// Makes `Task` from `async`.
    private func makeTask(single: Effect<Action>.Single, priority: TaskPriority?, tracksFeedbacks: Bool) -> Task<(), Never>
    {
        let task = Task(priority: priority) { [weak self] in
            let nextAction = await single.run()

            // Feed back `nextAction`.
            if let nextAction = nextAction, !Task.isCancelled {
                let feedbackTask = await self?.send(nextAction, priority: priority, tracksFeedbacks: tracksFeedbacks)
                if tracksFeedbacks {
                    await feedbackTask?.value
                }
            }
        }

        self.enqueueTask(task, id: single.id, queue: single.queue, priority: priority, tracksFeedbacks: tracksFeedbacks)

        return task
    }

    /// Makes `Task` from `AsyncSequence`.
    func makeTask(sequence: Effect<Action>._Sequence, priority: TaskPriority?, tracksFeedbacks: Bool) -> Task<(), Never>
    {
        let task = Task(priority: priority) { [weak self] in
            do {
                var feedbackTasks: [Task<(), Never>] = []

                for try await nextAction in sequence.sequence {
                    if Task.isCancelled { break }

                    // Feed back `nextAction`.
                    let feedbackTask = await self?.send(nextAction, priority: priority, tracksFeedbacks: tracksFeedbacks)

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
                Debug.print("Warning: AsyncSequence error is ignored: \(error)")
            }
        }

        self.enqueueTask(task, id: sequence.id, queue: sequence.queue, priority: priority, tracksFeedbacks: tracksFeedbacks)

        return task
    }

    /// Enqueues running `task` or pending `effectKind` to the buffer, and dequeue after completed.
    private func enqueueTask(
        _ task: Task<(), Never>,
        id: EffectID?,
        queue: AnyEffectQueue?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    )
    {
        // Register task.
        if let id = id {
            Debug.print("[enqueueTask] Append id-task: \(id)")
            self.idTasks[id, default: []].insert(task)
        }

        if let queue = queue {
            Debug.print("[enqueueTask] Append queue-task: \(queue)")
            self.queues[queue, default: []].append(task)
        }

        // Clean up after `task` is completed.
        Task<(), Never>(priority: priority) { [weak self] in
            Debug.print("[enqueueTask] Task completed")
            await task.value

            if let id = id {
                Debug.print("[enqueueTask] Remove completed id-task: \(id)")
                await self?.removeTask(id: id, task: task)
            }

            if let queue = queue {
                if let removingIndex = await self?.queues[queue]?.firstIndex(where: { $0 == task }) {
                    Debug.print("[enqueueTask] Remove completed queue-task: \(queue)")
                    await self?.removeTask(at: removingIndex, in: queue)
                }

                switch queue.effectQueuePolicy {
                case .runOldest(_, .suspendNew):
                    guard await self?.pendingEffectKinds[queue]?.isEmpty == false else { break }

                    if let pendingEffectKind = await self?.dequeuePendingEffectKind(queue: queue) {
                        Debug.print("[enqueueTask] Extracted pending effect")

                        if let _ = await self?.performEffectKind(pendingEffectKind, priority: priority, tracksFeedbacks: tracksFeedbacks) {
                            Debug.print("[enqueueTask] Pending effect started running")
                        }
                        else {
                            Debug.print("[enqueueTask] Pending effect failed running")
                        }
                    }

                default:
                    break
                }
            }
        }
    }

    private func removeTask(id: EffectID, task: Task<(), Never>)
    {
        self.idTasks[id]?.remove(task)
    }

    private func removeTask(at index: Int, in queue: AnyEffectQueue)
    {
        self.queues[queue]?.remove(at: index)
    }

    private func dequeuePendingEffectKind(queue: AnyEffectQueue) -> Effect<Action>.Kind?
    {
        self.pendingEffectKinds[queue]?.removeFirst()
    }
}
