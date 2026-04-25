import ActomatonCore
import Clocks
import Foundation

/// Default ``EffectManager`` implementation that manages ``Effect<Action>`` with queue-based task lifecycle.
///
/// Handles task creation, queue policies (newest/oldest), effect delays, and pending effect suspension.
/// Does NOT own the reducer or state — those are managed by ``MealyMachine``.
package final class EffectQueueManager<Action, State>: EffectManager
    where Action: Sendable
{
    package typealias Output = Effect<Action>

    private let effectContext: EffectContext

    // MARK: - Task tracking

    /// Effect-identified running tasks for manual cancellation or on-deinit cancellation.
    /// - Note: Multiple effects can have same ``_EffectID``.
    private var runningTasks: [_EffectID: Set<Task<(), any Error>>] = [:]

    /// Effect-queue-designated running tasks for automatic cancellation & suspension.
    private var queuedRunningTasks: [_EffectQueue: [Task<(), any Error>]] = [:]

    /// Suspended effects with their original send context.
    private var pendingEffects: [_EffectQueue: [PendingEffect]] = [:]

    /// Tracked latest effect start time for delayed effects calculation.
    private var latestEffectTime: [_EffectQueue: AnyClock<Duration>.Instant] = [:]

    /// Latest known queue per effect queue, updated on each new effect submission.
    /// Used to retrieve the most recent `effectQueuePolicy` (e.g. dynamic `maxCount`) at dequeue time.
    private var latestQueue: [_EffectQueue: any EffectQueue] = [:]

    // MARK: - Callbacks (set via setUp)

    private var sendAction: (@Sendable (Action, TaskPriority?, Bool) async -> Task<(), any Error>?)?

    /// Closure to run a block within the owning actor's isolation for safe bookkeeping updates.
    private var performIsolated: (
        @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, EffectQueueManager<Action, State>) -> Void
        ) async -> Void
    )?

    package init(
        effectContext: EffectContext
    )
    {
        self.effectContext = effectContext
    }

    // MARK: - EffectManager

    package func setUp(
        performIsolated: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (isolated any Actor, EffectQueueManager<Action, State>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (Action, TaskPriority?, _ tracksFeedbacks: Bool) async -> Task<(), any Error>?
    )
    {
        self.performIsolated = performIsolated
        self.sendAction = sendAction
    }

    package func preprocessOutput(
        _ output: Effect<Action>,
        runReducer: (Action) -> Effect<Action>
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
            let nestedOutput = preprocessOutput(runReducer(syncAction), runReducer: runReducer)
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
        id: _EffectID,
        task: Task<(), any Error>,
        queue: (any EffectQueue)?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    )
    {
        Debug.print("[handleTaskCompleted] Removing id-task: \(id)")
        runningTasks[id]?.remove(task)

        if let queue {
            let effectQueue = _EffectQueue(queue)

            if let removingIndex = queuedRunningTasks[effectQueue]?.firstIndex(where: { $0 == task }) {
                Debug.print("[handleTaskCompleted] Remove completed queue-task: \(queue) \(removingIndex)")
                queuedRunningTasks[effectQueue]?.remove(at: removingIndex)

                // Use the latest known queue to get the most recent policy/maxCount,
                // falling back to the completing task's queue.
                let currentQueue = latestQueue[effectQueue] ?? queue

                // Try to dequeue pending effects.
                switch currentQueue.effectQueuePolicy {
                case .runOldest(_, .suspendNew):
                    dequeuePendingIfPossible(queue: currentQueue)
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
        for (queue, pendings) in pendingEffects {
            for pending in pendings {
                cancelEffectKind(pending.kind)
                pending.onComplete.finish()
            }
            pendingEffects[queue] = nil
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
            switch checkQueuePolicy(effectKind: kind, priority: priority, tracksFeedbacks: tracksFeedbacks) {
            case .execute:
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
                return []

            case let .suspend(waitTask):
                return [waitTask]

            case .discard:
                return []
            }

        case .next:
            // Should not appear — Actomaton resolves .next before passing to EffectQueueManager.
            return []

        case let .cancel(predicate):
            cancelEffects(predicate: predicate)
            return []

        case let .updateQueue(queue):
            latestQueue[_EffectQueue(queue)] = queue

            dequeuePendingIfPossible(queue: queue)
            return []
        }
    }

    /// Checks queue policy and performs any needed task drops/suspensions.
    private func checkQueuePolicy(
        effectKind: Effect<Action>.Kind,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> QueuePolicyDecision
    {
        guard let queue = effectKind.queue else { return .execute }

        let effectQueue = _EffectQueue(queue)

        // Track the latest queue so dequeue logic can use the most recent policy/maxCount.
        latestQueue[effectQueue] = queue

        switch queue.effectQueuePolicy {
        case let .runNewest(maxCount):
            // NOTE: +1 to make a space for new effect.
            let droppingCount = (queuedRunningTasks[effectQueue]?.count ?? 0) - maxCount + 1
            if droppingCount > 0 {
                for _ in 0 ..< droppingCount {
                    let droppingTask = queuedRunningTasks[effectQueue]?.removeFirst()

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
            return .execute

        case let .runOldest(maxCount, overflowPolicy):
            let currentCount = queuedRunningTasks[effectQueue]?.count ?? 0
            if currentCount >= maxCount {
                switch overflowPolicy {
                case .suspendNew:
                    // Enqueue to pending buffer with a completion signal
                    // so the original `send`'s Task can track deferred execution.
                    Debug.print("[checkQueuePolicy] [runOldest-suspendNew] Enqueue to pending buffer")

                    let (stream, continuation) = AsyncStream<Never>.makeStream()

                    pendingEffects[effectQueue, default: []].append(
                        PendingEffect(
                            kind: effectKind,
                            priority: priority,
                            tracksFeedbacks: tracksFeedbacks,
                            onComplete: continuation
                        )
                    )

                    let waitTask = Task<(), any Error> {
                        for await _ in stream {}
                    }
                    return .suspend(waitTask: waitTask)

                case .discardNew:
                    cancelEffectKind(effectKind)
                    return .discard
                }
            }
            return .execute
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

        case .next, .cancel, .updateQueue:
            return nil
        }
    }

    /// Enqueues running `task` and sets up a detached cleanup task.
    ///
    /// The cleanup task uses `performIsolated` to re-enter actor isolation
    /// for safe bookkeeping updates, avoiding strong capture of the actor.
    private func enqueueTask(
        _ task: Task<(), any Error>,
        id: _EffectID?,
        queue: (any EffectQueue)?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    )
    {
        let effectID = id ?? _EffectID(DefaultEffectID())

        // Register task.
        Debug.print("[enqueueTask] Append id-task: \(effectID)")
        self.runningTasks[effectID, default: []].insert(task)

        if let queue {
            Debug.print("[enqueueTask] Append queue-task: \(queue)")
            self.queuedRunningTasks[_EffectQueue(queue), default: []].append(task)
        }

        let performIsolated = self.performIsolated

        // Clean up after `task` is completed.
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
        predicate: @escaping @Sendable (any EffectID) -> Bool
    )
    {
        // Cancel running tasks.
        for id in runningTasks.keys {
            if predicate(id.value), let previousTasks = runningTasks.removeValue(forKey: id) {
                for previousTask in previousTasks {
                    previousTask.cancel()
                }
            }
        }

        // Cancel pending effects.
        for (effectQueue, pendings) in pendingEffects {
            for (i, pending) in pendings.enumerated().reversed() {
                if let effectID = pending.kind.id, predicate(effectID.value) {
                    if let removed = pendingEffects[effectQueue]?.remove(at: i) {
                        cancelEffectKind(removed.kind)
                        removed.onComplete.finish()
                    }
                }
            }
        }
    }

    /// Calculates absolute effect start time for queue-based delay scheduling.
    ///
    /// Returns `nil` when the effect should run immediately without additional sleeping.
    private func calculateEffectTime(queue: (any EffectQueue)?) -> AnyClock<Duration>.Instant?
    {
        guard let queue else { return nil }

        let effectQueue = _EffectQueue(queue)
        let now = self.effectContext.clock.now

        guard let latestTime = self.latestEffectTime[effectQueue] else {
            self.latestEffectTime[effectQueue] = now
            return nil
        }

        let targetDelay = now.duration(to: latestTime) + queue.effectQueueDelay.duration

        if targetDelay <= .zero {
            self.latestEffectTime[effectQueue] = now
            return nil
        }

        let nextTime = now.advanced(by: targetDelay)
        self.latestEffectTime[effectQueue] = nextTime

        Debug.print("[calculateEffectDelay] scheduled via effectContext.clock")
        return nextTime
    }

    /// Dequeues pending effects up to the current capacity (for `runOldest-suspendNew` policy).
    ///
    /// Uses the latest known `maxCount` so that dynamic capacity increases
    /// are reflected immediately, rather than draining one-at-a-time.
    /// Each dequeued effect uses its original `priority` and `tracksFeedbacks` from the `send` call,
    /// and signals `onComplete` when the task finishes so that the original `send`'s Task completes.
    private func dequeuePendingIfPossible(
        queue: any EffectQueue
    )
    {
        guard case let .runOldest(maxCount, _) = queue.effectQueuePolicy else { return }

        let effectQueue = _EffectQueue(queue)

        while pendingEffects[effectQueue]?.isEmpty == false {
            let currentCount = queuedRunningTasks[effectQueue]?.count ?? 0
            guard currentCount < maxCount else { break }

            let pending = pendingEffects[effectQueue]!.removeFirst()
            let time = calculateEffectTime(queue: queue)

            Debug
                .print(
                    "[dequeuePendingIfPossible] Dequeued pending effect (running: \(currentCount), maxCount: \(maxCount))"
                )

            let task = makeTask(
                effectKind: pending.kind,
                time: time,
                priority: pending.priority,
                tracksFeedbacks: pending.tracksFeedbacks
            )

            // Bridge: signal the original send's waiting task when the dequeued task completes.
            let onComplete = pending.onComplete
            if let task {
                Task<Void, Never> {
                    _ = await task.result
                    onComplete.finish()
                }
            }
            else {
                onComplete.finish()
            }
        }
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
        case .next, .cancel, .updateQueue:
            return
        }
    }

    // MARK: - Nested Types

    /// A suspended effect together with its original `send` context.
    private struct PendingEffect: Sendable
    {
        let kind: Effect<Action>.Kind
        let priority: TaskPriority?
        let tracksFeedbacks: Bool

        /// Signalled when the dequeued effect task completes,
        /// allowing the original `send`'s returned Task to finish.
        let onComplete: AsyncStream<Never>.Continuation
    }

    /// Result of queue policy evaluation.
    private enum QueuePolicyDecision
    {
        /// The effect should be executed immediately.
        case execute

        /// The effect was suspended. The associated task completes when
        /// the effect is eventually dequeued and finishes.
        case suspend(waitTask: Task<(), any Error>)

        /// The effect was discarded (e.g. `discardNew` policy).
        case discard
    }
}
