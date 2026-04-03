import ActomatonCore
import Clocks
import Foundation

/// Default ``EffectManagerProtocol`` implementation that manages ``Effect<Action>`` with queue-based task lifecycle.
///
/// Handles task creation, queue policies (newest/oldest), effect delays, and pending effect suspension.
/// Does NOT own the reducer or state — those are managed by ``MealyMachine``.
package final class EffectManager<Action, State>: EffectManagerProtocol
    where Action: Sendable
{
    package typealias Output = Effect<Action>

    private let effectContext: EffectContext

    // MARK: - Task tracking

    /// Effect-identified running tasks for manual cancellation or on-deinit cancellation.
    /// - Note: Multiple effects can have same ``EffectID``.
    private var runningTasks: [EffectID: Set<Task<(), any Error>>] = [:]

    /// Effect-queue-designated running tasks for automatic cancellation & suspension.
    private var queuedRunningTasks: [EffectQueue: [Task<(), any Error>]] = [:]

    /// Suspended effects.
    private var pendingEffectKinds: [EffectQueue: [Effect<Action>.Kind]] = [:]

    /// Tracked latest effect start time for delayed effects calculation.
    private var latestEffectTime: [EffectQueue: AnyClock<Duration>.Instant] = [:]

    // MARK: - Callbacks (set via setUp)

    private var sendAction: (@Sendable (Action, TaskPriority?, Bool) async -> Task<(), any Error>?)?

    /// Closure to run a block within the owning actor's isolation for safe bookkeeping updates.
    private var performIsolated: (
        @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, EffectManager<Action, State>) -> Void
        ) async -> Void
    )?

    package init(
        effectContext: EffectContext
    )
    {
        self.effectContext = effectContext
    }

    // MARK: - EffectManagerProtocol

    package func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, EffectManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {
        self.performIsolated = performIsolated
        self.sendAction = sendAction
    }

    package func preprocessOutput(
        _ output: Effect<Action>,
        sendReducer: (Action) -> Effect<Action>
    ) -> Effect<Action>
    {
        var syncActions: [Action] = []
        var remainingKinds: [Effect<Action>.Kind] = []

        for kind in output.kinds {
            if case let .next(nextAction) = kind {
                syncActions.append(nextAction)
            }
            else {
                remainingKinds.append(kind)
            }
        }

        for syncAction in syncActions {
            let nestedOutput = preprocessOutput(sendReducer(syncAction), sendReducer: sendReducer)
            remainingKinds.append(contentsOf: nestedOutput.kinds)
        }

        return Effect(kinds: remainingKinds)
    }

    package func processOutput(
        _ output: Effect<Action>,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?
    {
        var tasks: [Task<(), any Error>] = []
        for kind in output.kinds {
            tasks.append(
                contentsOf: processEffectKind(
                    kind,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks
                )
            )
        }

        if tasks.isEmpty { return nil }

        let tasks_ = tasks

        // Make a detached task that waits for all `tasks`.
        return Task.detached {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for task in tasks_ {
                    group.addTask {
                        try await task.value
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    private func handleTaskCompleted(
        id: EffectID,
        task: Task<(), any Error>,
        queue: AnyEffectQueue?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    )
    {
        Debug.print("[handleTaskCompleted] Removing id-task: \(id)")
        runningTasks[id]?.remove(task)

        if let queue {
            if let removingIndex = queuedRunningTasks[queue.queue]?.firstIndex(where: { $0 == task }) {
                Debug.print("[handleTaskCompleted] Remove completed queue-task: \(queue) \(removingIndex)")
                queuedRunningTasks[queue.queue]?.remove(at: removingIndex)

                // Try to dequeue pending effects.
                switch queue.effectQueuePolicy {
                case .runOldest(_, .suspendNew):
                    dequeuePendingIfPossible(
                        queue: queue,
                        priority: priority,
                        tracksFeedbacks: tracksFeedbacks
                    )
                default:
                    break
                }
            }
        }
    }

    package func shutDown()
    {
        // Cancel all running tasks.
        for (_, tasks) in runningTasks {
            for task in tasks {
                task.cancel()
            }
        }

        // Drain and cancel pending effects to trigger their cancellation handlers.
        for (queue, kinds) in pendingEffectKinds {
            for kind in kinds {
                cancelEffectKind(kind)
            }
            pendingEffectKinds[queue] = nil
        }
    }

    // MARK: - Private

    private func processEffectKind(
        _ kind: Effect<Action>.Kind,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> [Task<(), any Error>]
    {
        switch kind {
        case .single, .sequence:
            let shouldExecute = checkQueuePolicy(effectKind: kind)
            if shouldExecute {
                let time = calculateEffectTime(queue: kind.queue)
                if let task = makeTask(
                    effectKind: kind,
                    time: time,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks
                )
                {
                    return [task]
                }
            }
            return []

        case .next:
            // Should not appear — Actomaton resolves .next before passing to EffectManager.
            return []

        case let .cancel(predicate):
            cancelEffects(predicate: predicate)
            return []
        }
    }

    /// Checks queue policy and performs any needed task drops/suspensions.
    /// Returns `true` if the effect should be executed.
    private func checkQueuePolicy(
        effectKind: Effect<Action>.Kind
    ) -> Bool
    {
        guard let queue = effectKind.queue else { return true }

        switch queue.effectQueuePolicy {
        case let .runNewest(maxCount):
            // NOTE: +1 to make a space for new effect.
            let droppingCount = (queuedRunningTasks[queue.queue]?.count ?? 0) - maxCount + 1
            if droppingCount > 0 {
                for _ in 0 ..< droppingCount {
                    let droppingTask = queuedRunningTasks[queue.queue]?.removeFirst()

                    if let droppingTask {
#if DEBUG
                        let droppingEffectID = runningTasks
                            .first(where: { $0.value.contains(droppingTask) })?.key
                        Debug
                            .print(
                                "[checkQueuePolicy] [dropOldestTasks] droppingEffectID = \(String(describing: droppingEffectID))"
                            )
#endif
                        droppingTask.cancel()
                    }
                }
            }
            return true

        case let .runOldest(maxCount, overflowPolicy):
            let currentCount = queuedRunningTasks[queue.queue]?.count ?? 0
            if currentCount >= maxCount {
                switch overflowPolicy {
                case .suspendNew:
                    // Enqueue to pending buffer.
                    Debug.print("[checkQueuePolicy] [runOldest-suspendNew] Enqueue to pending buffer")
                    pendingEffectKinds[queue.queue, default: []].append(effectKind)
                    return false

                case .discardNew:
                    cancelEffectKind(effectKind)
                    return false
                }
            }
            return true
        }
    }

    /// Creates a detached task for the given effect kind.
    private func makeTask(
        effectKind: Effect<Action>.Kind,
        time: AnyClock<Duration>.Instant?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?
    {
        let sendAction = self.sendAction
        let context = self.effectContext

        switch effectKind {
        case let .single(single):
            let task = Task.detached(priority: priority) {
                if let time {
                    try? await context.clock.sleep(until: time, tolerance: nil)
                }
                let nextAction = try await single.run(context)
                if let nextAction {
                    let feedbackTask = await sendAction?(nextAction, priority, tracksFeedbacks)
                    if tracksFeedbacks {
                        try await feedbackTask?.value
                    }
                }
            }
            enqueueTask(
                task,
                id: single.id,
                queue: single.queue,
                priority: priority,
                tracksFeedbacks: tracksFeedbacks
            )
            return task

        case let .sequence(sequence):
            let task = Task<(), any Error>.detached(priority: priority) {
                if let time {
                    try? await context.clock.sleep(until: time, tolerance: nil)
                }
                guard let seq = try await sequence.sequence(context) else { return }
                var feedbackTasks: [Task<(), any Error>] = []
                for try await nextAction in seq {
                    let feedbackTask = await sendAction?(nextAction, priority, tracksFeedbacks)
                    if let feedbackTask {
                        feedbackTasks.append(feedbackTask)
                    }
                }
                if tracksFeedbacks {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for feedbackTask in feedbackTasks {
                            group.addTask(priority: priority) {
                                try await feedbackTask.value
                            }
                        }
                        try await group.waitForAll()
                    }
                }
            }
            enqueueTask(
                task,
                id: sequence.id,
                queue: sequence.queue,
                priority: priority,
                tracksFeedbacks: tracksFeedbacks
            )
            return task

        case .next, .cancel:
            return nil
        }
    }

    /// Enqueues running `task` and sets up a detached cleanup task.
    ///
    /// The cleanup task uses `performIsolated` to re-enter actor isolation
    /// for safe bookkeeping updates, avoiding strong capture of the actor.
    private func enqueueTask(
        _ task: Task<(), any Error>,
        id: EffectID?,
        queue: AnyEffectQueue?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    )
    {
        let effectID = id ?? EffectID(DefaultEffectID())

        // Register task.
        Debug.print("[enqueueTask] Append id-task: \(effectID)")
        self.runningTasks[effectID, default: []].insert(task)

        if let queue {
            Debug.print("[enqueueTask] Append queue-task: \(queue)")
            self.queuedRunningTasks[queue.queue, default: []].append(task)
        }

        // Clean up after `task` is completed.
        let performIsolated = self.performIsolated

        Task<(), any Error>.detached(priority: priority) {
            // Wait for `task` to complete.
            _ = await task.result

            Debug.print("[enqueueTask] Task completed, removing id-task: \(effectID)")

            // Re-enter actor isolation for safe bookkeeping updates.
            await performIsolated? { _, self_ in
                self_.handleTaskCompleted(
                    id: effectID,
                    task: task,
                    queue: queue,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks
                )
            }
        }
    }

    /// Cancels running and pending effects matching the predicate.
    private func cancelEffects(
        predicate: @escaping @Sendable (EffectID) -> Bool
    )
    {
        // Cancel running tasks.
        for id in runningTasks.keys {
            if predicate(id), let previousTasks = runningTasks.removeValue(forKey: id) {
                for previousTask in previousTasks {
                    previousTask.cancel()
                }
            }
        }

        // Cancel pending effects.
        for (effectQueue, effectKinds) in pendingEffectKinds {
            for (i, effectKind) in effectKinds.enumerated().reversed() {
                if let effectID = effectKind.id, predicate(effectID) {
                    if let kind = pendingEffectKinds[effectQueue]?.remove(at: i) {
                        cancelEffectKind(kind)
                    }
                }
            }
        }
    }

    /// Calculates absolute effect start time for queue-based delay scheduling.
    ///
    /// Returns `nil` when the effect should run immediately without additional sleeping.
    private func calculateEffectTime(queue: AnyEffectQueue?) -> AnyClock<Duration>.Instant?
    {
        guard let queue else { return nil }

        let now = self.effectContext.clock.now

        guard let latestTime = self.latestEffectTime[queue.queue] else {
            self.latestEffectTime[queue.queue] = now
            return nil
        }

        let targetDelay = now.duration(to: latestTime) + queue.effectQueueDelay.duration

        if targetDelay <= .zero {
            self.latestEffectTime[queue.queue] = now
            return nil
        }

        let nextTime = now.advanced(by: targetDelay)
        self.latestEffectTime[queue.queue] = nextTime

        Debug.print("[calculateEffectDelay] scheduled via effectContext.clock")
        return nextTime
    }

    /// Dequeues a pending effect if possible (for `runOldest-suspendNew` policy).
    @discardableResult
    private func dequeuePendingIfPossible(
        queue: AnyEffectQueue,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), any Error>?
    {
        guard pendingEffectKinds[queue.queue]?.isEmpty == false else { return nil }
        let kind = pendingEffectKinds[queue.queue]!.removeFirst()
        let time = calculateEffectTime(queue: queue)
        Debug.print("[dequeuePendingIfPossible] Dequeued pending effect")
        return makeTask(
            effectKind: kind,
            time: time,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks
        )
    }

    /// Cancels `effectKind`'s `single` or `sequence` immediately
    /// so that cancellation can still be delivered to `Effect`'s async scope.
    private func cancelEffectKind(_ effectKind: Effect<Action>.Kind)
    {
        let context = self.effectContext

        switch effectKind {
        case let .single(single):
            Task<Void, any Error>.detached {
                _ = try await single.run(context)
            }
            .cancel() // Cancel immediately.
        case let .sequence(sequence):
            Task<Void, any Error>.detached {
                _ = try await sequence.sequence(context)
            }
            .cancel() // Cancel immediately.
        case .next, .cancel:
            return
        }
    }
}
