import ActomatonCore
import Clocks
import Foundation

/// Default ``EffectManager`` implementation that manages ``Effect`` with queue-based task lifecycle.
///
/// Handles task creation, queue policies (newest/oldest), effect delays, and pending effect suspension.
/// Does NOT own the reducer or state — those are managed by ``MealyMachine``.
///
/// `EffectQueueManager` is a plain non-`Sendable` class. Cleanup work spawned from unstructured tasks
/// re-enters the parent safe container that wraps this manager through the `withSendability`
/// callback supplied at `setUp(...)`-time, which hands `self` back as a parameter — so no
/// `[weak self]` capture of the (non-Sendable) `self` is needed in those tasks.
package final class EffectQueueManager<Action, State, Emission>: EffectManager
{
    package typealias Output = Effect<Action, Emission>

    private let effectContext: EffectContext

    // MARK: - Task tracking

    /// Effect-identified running tasks for manual cancellation or on-deinit cancellation.
    /// - Note: Multiple effects can have same ``_EffectID``.
    private var runningTasks: [_EffectID: Set<Task<(), Never>>] = [:]

    /// Effect-queue-designated running tasks for automatic cancellation & suspension.
    private var queuedRunningTasks: [_EffectQueue: [Task<(), Never>]] = [:]

    /// Suspended effects with their original send context.
    private var pendingEffects: [_EffectQueue: [PendingEffect]] = [:]

    /// Dequeued tasks still represented to the original caller by their suspended-effect task.
    ///
    /// - Key: the task returned to the public `send` / `SendResult` path while the effect is
    ///   suspended. It completes only when the pending effect is dropped or the dequeued effect
    ///   task finishes. This is the task cancelled by `SendResult.cancel()`.
    /// - Value: the actual running effect task later created by `makeTask(...)` after queue
    ///   capacity opens and the pending effect is dequeued.
    private var dequeuedTasks: [Task<(), Never>: Task<(), Never>] = [:]

    /// Tracked latest effect start time for delayed effects calculation.
    private var latestEffectTime: [_EffectQueue: AnyClock<Duration>.Instant] = [:]

    /// Latest known queue per effect queue, updated on each new effect submission.
    /// Used to retrieve the most recent `effectQueuePolicy` (e.g. dynamic `maxCount`) at dequeue time.
    private var latestQueue: [_EffectQueue: any EffectQueue] = [:]

    // MARK: - Callbacks (set via setUp)

    private var sendAction: (
        @Sendable (
            Action,
            TaskPriority?,
            Bool,
            _ emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
        ) async -> Task<(), Never>?
    )?

    /// `@Sendable` closure with **inherited sendability** from the parent safe container that
    /// wraps this manager. Hands `self` back to the supplied callback under that sendability,
    /// so cleanup tasks in ``enqueueTask`` can mutate bookkeeping safely without
    /// capturing (non-Sendable) `self`.
    private var withSendability: (
        @Sendable (
            _ runEffM: @escaping @Sendable (EffectQueueManager<Action, State, Emission>) -> Void
        ) async -> Void
    )?

    package init(
        effectContext: EffectContext
    )
    {
        self.effectContext = effectContext
    }

    deinit
    {
        shutDown()
    }

    // MARK: - EffectManager

    package func setUp(
        withSendability: @escaping @Sendable (
            _ runEffM: @escaping @Sendable (EffectQueueManager<Action, State, Emission>) -> Void
        ) async -> Void,
        sendAction: @escaping @Sendable (
            _ action: Action,
            _ priority: TaskPriority?,
            _ tracksFeedbacks: Bool,
            _ emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
        ) async -> Task<(), Never>?
    )
    {
        self.withSendability = withSendability
        self.sendAction = sendAction
    }

    package func processOutput(
        _ output: Effect<Action, Emission>,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> Task<(), Never>?
    {
        var tasks: [Task<(), Never>] = []
        for kind in output.kinds {
            tasks.append(
                contentsOf: processEffectKind(
                    kind,
                    priority: priority,
                    tracksFeedbacks: tracksFeedbacks,
                    emit: emit
                )
            )
        }

        if tasks.isEmpty { return nil }

        let tasks_ = tasks

        // Keep the returned task unstructured, but run its supervisor work off any caller actor.
        // `_runTasksForwardingCancellation` already forwards cancellation of this supervisor task
        // into `tasks_` (via its per-task `withTaskCancellationHandler`), so no outer handler is needed.
        return Task<(), Never>(priority: priority) { @concurrent in
            await _runTasksForwardingCancellation(tasks_, priority: priority)
        }
    }

    private func handleTaskCompleted(
        id: _EffectID,
        task: Task<(), Never>,
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

    private func shutDown()
    {
        // Cancel all running tasks.
        for (_, tasks) in runningTasks {
            for task in tasks {
                task.cancel()
            }
        }

        // Drain pending effects. They never started, so there is nothing to cancel —
        // just signal completion so their suspended-effect tasks finish.
        for (queue, pendings) in pendingEffects {
            for pending in pendings {
                pending.onComplete.finish()
            }
            pendingEffects[queue] = nil
        }
    }

    // MARK: - Private

    private func processEffectKind(
        _ kind: Effect<Action, Emission>.Kind,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> [Task<(), Never>]
    {
        switch kind {
        case .single, .sequence:
            let taskPriority = kind.priority ?? priority

            switch checkQueuePolicy(
                effectKind: kind,
                priority: taskPriority,
                tracksFeedbacks: tracksFeedbacks,
                emit: emit
            ) {
            case .execute:
                let time = calculateEffectTime(queue: kind.queue)
                if let task = makeTask(
                    effectKind: kind,
                    time: time,
                    priority: taskPriority,
                    tracksFeedbacks: tracksFeedbacks,
                    emit: emit
                )
                {
                    return [task]
                }
                return []

            case let .suspend(suspendedEffectTask):
                return [suspendedEffectTask]

            case .discard:
                return []
            }

        case let .emission(emission):
            // Synchronous side-channel emission — deliver to the original `send` caller.
            emit(.success(emission))
            return []

        case .next:
            // Should not appear — MealyMachine.send resolves .next before passing to EffectQueueManager.
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
        effectKind: Effect<Action, Emission>.Kind,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
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

                    let suspendedEffectTask = Task<(), Never> {
                        await withTaskCancellationHandler {
                            for await _ in stream {}
                        } onCancel: {
                            continuation.finish()
                        }
                    }

                    pendingEffects[effectQueue, default: []].append(
                        PendingEffect(
                            kind: effectKind,
                            priority: priority,
                            tracksFeedbacks: tracksFeedbacks,
                            suspendedEffectTask: suspendedEffectTask,
                            emit: emit,
                            onComplete: continuation
                        )
                    )

                    observeSuspendedEffectTaskCancellation(
                        suspendedEffectTask,
                        priority: priority
                    )

                    return .suspend(suspendedEffectTask: suspendedEffectTask)

                case .discardNew:
                    return .discard
                }
            }
            return .execute
        }
    }

    /// Creates an unstructured task for the given effect kind.
    private func makeTask(
        effectKind: Effect<Action, Emission>.Kind,
        time: AnyClock<Duration>.Instant?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> Task<(), Never>?
    {
        let sendAction = self.sendAction
        let context = self.effectContext
        let feedbackEmit: @Sendable (Result<Emission, any Error>) -> Void = { result in
            if tracksFeedbacks {
                emit(result)
            }
        }

        switch effectKind {
        case let .single(single):
            let task = Task<(), Never>(priority: priority) { @concurrent in
                do {
                    if let time {
                        try? await context.clock.sleep(until: time, tolerance: nil)
                    }
                    let outcome = try await single.run(context)
                    guard let outcome else { return }

                    if let emission = outcome.emission {
                        emit(.success(emission))
                    }
                    if let action = outcome.action {
                        let feedbackTask = await sendAction?(action, priority, tracksFeedbacks, feedbackEmit)
                        if tracksFeedbacks, let feedbackTask {
                            await _runTaskForwardingCancellation(feedbackTask)
                        }
                    }
                }
                catch is CancellationError {
                    // Cancellation is not an in-band failure; teardown is driven by the
                    // supervisor cancelling all sibling tasks. Swallow so the aggregating
                    // task group does not rethrow and cancel unrelated siblings.
                }
                catch {
                    // Surface this single effect's error in-band, leaving siblings running.
                    emit(.failure(error))
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
            let task = Task<(), Never>(priority: priority) { @concurrent in
                var feedbackTasks: [Task<(), Never>] = []

                do {
                    if let time {
                        try? await context.clock.sleep(until: time, tolerance: nil)
                    }
                    guard let seq = try await sequence.sequence(context) else { return }
                    for try await outcome in seq {
                        if let emission = outcome.emission {
                            emit(.success(emission))
                        }
                        if let action = outcome.action {
                            let feedbackTask = await sendAction?(action, priority, tracksFeedbacks, feedbackEmit)
                            if tracksFeedbacks, let feedbackTask {
                                feedbackTasks.append(feedbackTask)
                            }
                        }
                    }
                    if tracksFeedbacks {
                        await _runTasksForwardingCancellation(feedbackTasks, priority: priority)
                    }
                }
                catch is CancellationError {
                    // Cancellation is not an in-band failure; siblings are torn down by the
                    // supervisor, not by rethrowing here.
                    if tracksFeedbacks {
                        await _cancelAndDrainTasks(feedbackTasks)
                    }
                }
                catch {
                    // Surface this sequence effect's error (e.g. an `AsyncSequence` that threw,
                    // or a `.stream` failure) in-band, leaving siblings running.
                    emit(.failure(error))

                    if tracksFeedbacks {
                        // Feedback chain tasks never fail (their errors are surfaced in-band),
                        // so awaiting them forwards cancellation and drains without throwing.
                        await _runTasksForwardingCancellation(feedbackTasks, priority: priority)
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

        case .next, .emission, .cancel, .updateQueue:
            return nil
        }
    }

    /// Enqueues running `task` and sets up an unstructured cleanup task.
    ///
    /// The cleanup task snapshots `self.withSendability` (a Sendable closure value) and uses
    /// it to re-enter the parent safe container under inherited sendability. `self` is handed
    /// back as a parameter to the inner callback, so the cleanup task does NOT need to capture
    /// `self` — letting `EffectQueueManager` remain non-Sendable.
    private func enqueueTask(
        _ task: Task<(), Never>,
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

        let withSendability = self.withSendability

        // Clean up after `task` is completed.
        Task<(), Never>(priority: priority) { @concurrent in
            // Wait for `task` to complete.
            _ = await task.result

            Debug.print("[enqueueTask] Task completed, removing id-task: \(effectID)")

            // Re-enter the parent safe container. `self_` is the same `EffectQueueManager`
            // instance (handed back by the wrapper's `withSendability`); accessing it under the
            // wrapper's inherited sendability is safe without `self` being Sendable.
            await withSendability? { self_ in
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

    /// Observes cancellation of the completion task returned for a suspended pending effect.
    ///
    /// `runOldest(..., .suspendNew)` returns this task to the caller before the effect actually
    /// starts. The task completes only after the pending effect is dropped or the dequeued effect
    /// task finishes. If `SendResult.cancel()` cancels that task, the cancellation observer re-enters
    /// the manager and cancels the represented effect: either by removing it from `pendingEffects`,
    /// or by forwarding cancellation to its dequeued running task.
    private func observeSuspendedEffectTaskCancellation(
        _ suspendedEffectTask: Task<(), Never>,
        priority: TaskPriority?
    )
    {
        let withSendability = self.withSendability

        // Clean up when the suspended-effect task is cancelled,
        // whether it is still pending or already dequeued.
        Task<(), Never>(priority: priority) { @concurrent in
            _ = await suspendedEffectTask.result

            if suspendedEffectTask.isCancelled {
                await withSendability? { self_ in
                    self_.cancelPendingEffect(suspendedEffectTask: suspendedEffectTask)
                }
            }
        }
    }

    /// Cancels the effect represented by `suspendedEffectTask`.
    ///
    /// If the effect is still suspended, it is removed from `pendingEffects` without ever running.
    /// If it has already been dequeued, the pending entry is gone, so
    /// `dequeuedTasks` forwards cancellation from the suspended-effect task
    /// to the running effect task.
    private func cancelPendingEffect(suspendedEffectTask: Task<(), Never>)
    {
        // Remove pending effect that is associated with `suspendedEffectTask`.
        for (effectQueue, pendings) in pendingEffects {
            guard let index = pendings.firstIndex(where: {
                $0.suspendedEffectTask == suspendedEffectTask
            })
            else {
                continue
            }

            if let removed = pendingEffects[effectQueue]?.remove(at: index) {
                removed.onComplete.finish()
            }

            if pendingEffects[effectQueue]?.isEmpty == true {
                pendingEffects[effectQueue] = nil
            }

            return
        }

        // Or, remove current running dequeued task.
        dequeuedTasks.removeValue(forKey: suspendedEffectTask)?.cancel()
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

            if pending.suspendedEffectTask.isCancelled {
                pending.onComplete.finish()
                continue
            }

            Debug
                .print(
                    "[dequeuePendingIfPossible] Dequeued pending effect (running: \(currentCount), maxCount: \(maxCount))"
                )

            let dequeuedTask = makeTask(
                effectKind: pending.kind,
                time: time,
                priority: pending.priority,
                tracksFeedbacks: pending.tracksFeedbacks,
                emit: pending.emit
            )

            // Bridge the original suspended-effect task to the newly-created running
            // task. The bridge is used in both directions: completion of the running task
            // finishes the suspended-effect task, and cancellation of the
            // suspended-effect task cancels the running task via `dequeuedTasks`.
            let onComplete = pending.onComplete
            let suspendedEffectTask = pending.suspendedEffectTask
            if let dequeuedTask {
                dequeuedTasks[suspendedEffectTask] = dequeuedTask
                let withSendability = self.withSendability

                Task<Void, Never>(priority: pending.priority) {
                    // Wait for `task` to complete.
                    _ = await dequeuedTask.result

                    await withSendability? { self_ in
                        self_.dequeuedTasks.removeValue(forKey: suspendedEffectTask)
                    }
                    onComplete.finish()
                }
            }
            else {
                onComplete.finish()
            }
        }
    }

    // MARK: - Nested Types

    /// A suspended effect together with its original `send` context.
    private struct PendingEffect
    {
        let kind: Effect<Action, Emission>.Kind
        let priority: TaskPriority?
        let tracksFeedbacks: Bool

        /// Placeholder task returned to the original `send` while this effect is suspended.
        ///
        /// This task does not complete merely when the effect is dequeued. It stays alive until
        /// the suspended effect is dropped, or until the dequeued effect task finishes, so callers
        /// can await/cancel the full lifecycle through the original `SendResult`.
        let suspendedEffectTask: Task<(), Never>

        /// Original emission callback — preserved so a deferred dequeue still routes
        /// `Emission` emissions into the top-level result stream that issued the `send`.
        let emit: @Sendable (Result<Emission, any Error>) -> Void

        /// Signalled when the dequeued effect task completes,
        /// allowing the original `send`'s returned Task to finish.
        let onComplete: AsyncStream<Never>.Continuation
    }

    /// Result of queue policy evaluation.
    private enum QueuePolicyDecision
    {
        /// The effect should be executed immediately.
        case execute

        /// The effect was suspended.
        ///
        /// The associated task represents the suspended effect's full lifecycle: it remains pending
        /// across dequeue and completes only after the dequeued effect task finishes, or after the
        /// pending effect is cancelled/dropped.
        case suspend(suspendedEffectTask: Task<(), Never>)

        /// The effect was discarded (e.g. `discardNew` policy).
        case discard
    }
}

/// Runs and awaits `task` while forwarding cancellation from the awaiting task into `task`.
///
/// Plain `await task.value` only waits for the task's result. If the awaiting
/// task is cancelled, Swift does not automatically call `cancel()` on the task being
/// awaited, which matters here because effect tasks are unstructured task handles rather
/// than children of the waiter. This helper preserves
/// `SendResult.cancel()` semantics by turning cancellation of the waiter into
/// cancellation of the underlying effect task.
private func _runTaskForwardingCancellation(
    _ task: Task<(), Never>
) async
{
    await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}

private func _runTasksForwardingCancellation(
    _ tasks: [Task<(), Never>],
    priority: TaskPriority?
) async
{
    switch tasks.count {
    case 0:
        break
    case 1:
        if let task = tasks.first {
            await _runTaskForwardingCancellation(task)
        } 
    default:
        await withTaskGroup(of: Void.self) { group in
            for task in tasks {
                group.addTask(priority: priority) {
                    await _runTaskForwardingCancellation(task)
                }
            }
            await group.waitForAll()
        }
    }
}

private func _cancelAndDrainTasks(
    _ tasks: [Task<(), Never>]
) async
{
    for task in tasks {
        task.cancel()
    }

    // These are already-running unstructured tasks. Sequentially awaiting their results only
    // drains completion; it does not start them one-by-one, so wall-clock wait is bounded by
    // the slowest cancellation-aware task rather than the sum of all task durations.
    for task in tasks {
        _ = await task.result
    }
}
