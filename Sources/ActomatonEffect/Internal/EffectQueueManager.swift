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

    /// Task shape used for every manager-internal effect task (own work, chain, suspended
    /// placeholder).
    ///
    /// The success value is the list of feedback-chain tasks the effect's own work
    /// dispatched along the way: it is how an own-work task conveys its descendants to
    /// the chain task that awaits them — as a plain task **result**, with no shared
    /// mutable state. Chain tasks and suspended placeholders return `[]` (their
    /// descendants are already accounted for). The feedback tasks themselves are the
    /// `Task<(), Never>` handles produced by the `sendAction` boundary.
    private typealias WorkTask = Task<[Task<(), Never>], Never>

    private let effectContext: EffectContext

    // MARK: - Task tracking

    /// ``SendResults`` supervisors registered by `send`-level `id`, so a reducer-side
    /// `Effect.cancel(id:)` can cancel a whole `send` (its `SendResults`) just like it cancels an
    /// effect task sharing that `id`. Cancelling a registered supervisor cancels its `SendResults`.
    ///
    /// - Note: The supervisor `Task` is its own identity key (it is `Hashable`), exactly like
    ///   ``runningTasks`` holds a `Set` of tasks per ``_EffectID`` — so multiple `send(id:)` calls
    ///   sharing the same `id` are all cancelled together, and each deregisters itself on completion.
    private var sendingTasks: [_EffectID: Set<Task<Void, Never>>] = [:]

    /// Effect-identified running tasks for manual cancellation or on-deinit cancellation.
    /// - Note: Multiple effects can have same ``_EffectID``.
    private var runningTasks: [_EffectID: Set<WorkTask>] = [:]

    /// Effect-queue-designated running tasks for automatic cancellation & suspension.
    private var queuedRunningTasks: [_EffectQueue: [WorkTask]] = [:]

    /// Suspended effects with their original send context.
    private var pendingEffects: [_EffectQueue: [PendingEffect]] = [:]

    /// Dequeued tasks still represented to the original caller by their suspended-effect task.
    ///
    /// - Key: the task returned to the public `send` / `SendResults` path while the effect is
    ///   suspended. It completes only when the pending effect is dropped or the dequeued effect
    ///   task finishes. This is the task cancelled by `SendResults.cancel()`.
    /// - Value: the actual running effect task later created by `makeTask(...)` after queue
    ///   capacity opens and the pending effect is dequeued.
    private var dequeuedTasks: [WorkTask: WorkTask] = [:]

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
    /// so cleanup tasks can mutate bookkeeping safely without capturing (non-Sendable) `self`.
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
        var tasks: [WorkTask] = []
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
        // This supervisor is also the single place where `WorkTask` is erased back to the
        // `Task<(), Never>` shape of the `EffectManager` protocol boundary.
        return Task<(), Never>(priority: priority) { @concurrent in
            await _runTasksForwardingCancellation(tasks_, priority: priority)
        }
    }

    package func processSendOutput(
        _ output: Effect<Action, Emission>,
        id: (any EffectID)?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> SendResults<Emission>
        where Emission: Sendable
    {
        let (stream, continuation) = AsyncStream<Result<Emission, any Error>>.makeStream()
        let emit: @Sendable (Result<Emission, any Error>) -> Void = { continuation.yield($0) }

        let processingTask = self.processOutput(
            output,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks,
            emit: emit
        )

        // Stream-finishing supervisor. Effect errors are surfaced in-band as `.failure` elements
        // by each effect task, and the chain task swallows cancellation, so the supervisor just
        // awaits the chain and finishes the stream:
        //
        // - chain completes (success or in-band failures already delivered) -> finish cleanly.
        // - supervisor cancelled — via `SendResults.cancel()` OR a reducer-side `Effect.cancel(id:)`
        //   matching the registered `id` — -> propagate cancellation to the chain, then finish.
        let supervisor = Task<Void, Never>(priority: priority) { @concurrent in
            await withTaskCancellationHandler {
                await processingTask?.value
                continuation.finish()
            } onCancel: {
                processingTask?.cancel()
            }
        }

        if let id {
            registerSendingTask(id: _EffectID(id), supervisor: supervisor, priority: priority)
        }

        return SendResults(stream: stream, supervisor: supervisor)
    }

    /// Registers `supervisor`'s cancellation under `id`, so a reducer-side `Effect.cancel(id:)`
    /// (or `Effect.cancel(ids:)`) matching `id` cancels the whole `send` — equivalent to calling
    /// `SendResults.cancel()` — in addition to cancelling effect tasks sharing that `id`.
    ///
    /// Auto-deregisters when the supervisor settles (naturally or via cancellation) so that a
    /// later reuse of the same `id` never cancels an already-finished `SendResults`.
    private func registerSendingTask(
        id: _EffectID,
        supervisor: Task<Void, Never>,
        priority: TaskPriority?
    )
    {
        sendingTasks[id, default: []].insert(supervisor)

        waitForTask(supervisor, priority: priority) { self_ in
            self_.sendingTasks[id]?.remove(supervisor)
            if self_.sendingTasks[id]?.isEmpty == true {
                self_.sendingTasks[id] = nil
            }
        }
    }

    private func handleTaskCompleted(
        id: _EffectID,
        task: WorkTask,
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

        // Cancel any registered `SendResults` supervisors so their streams finish.
        for (_, supervisors) in sendingTasks {
            for supervisor in supervisors {
                supervisor.cancel()
            }
        }
        sendingTasks.removeAll()
    }

    // MARK: - Private

    private func processEffectKind(
        _ kind: Effect<Action, Emission>.Kind,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> [WorkTask]
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
            // The incoming effect must run immediately, so make room for it by
            // cancelling the oldest queued running tasks first.
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
                    // Capacity is full, so return a lightweight suspended task to
                    // the caller now and keep the original effect context in the
                    // pending buffer until a running task completes.

                    Debug.print("[checkQueuePolicy] [runOldest-suspendNew] Enqueue to pending buffer")

                    let (stream, continuation) = AsyncStream<Never>.makeStream()

                    // The stream is finished when the pending effect is dropped or
                    // when its later dequeued running task completes. This lets the
                    // original `send` task represent the full deferred lifecycle.
                    let suspendedEffectTask = WorkTask {
                        await withTaskCancellationHandler {
                            for await _ in stream {}
                        } onCancel: {
                            continuation.finish()
                        }
                        return []
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

                    waitForTask(
                        suspendedEffectTask,
                        priority: priority,
                        condition: {
                            suspendedEffectTask.isCancelled
                        },
                        cleanUp: { self_ in
                            // Cancellation while still pending removes the pending
                            // entry; cancellation after dequeue forwards to the
                            // actual running task via `dequeuedTasks`.
                            self_.cancelPendingEffect(suspendedEffectTask: suspendedEffectTask)
                        }
                    )

                    return .suspend(suspendedEffectTask: suspendedEffectTask)

                case .discardNew:
                    return .discard
                }
            }
            return .execute
        }
    }

    /// Creates the unstructured task(s) for the given effect kind.
    ///
    /// ## Own-work task vs chain task
    ///
    /// Two lifetimes exist around one effect, and they must be tracked separately:
    ///
    /// - **Own work**: the effect's own execution (sleep + single/sequence run + feedback
    ///   *dispatch*). Queue/ID bookkeeping (``enqueueTask``: slot release & pending
    ///   dequeue, `runNewest` eviction, `Effect.cancel(id:)`) tracks THIS task, so a
    ///   queue slot is held — and eviction/ID-cancellation strikes — only while the
    ///   effect itself is running.
    /// - **Chain** (`tracksFeedbacks: true` only): own work *plus* every feedback
    ///   descendant. The returned task represents this, so `SendResults` supervisors keep
    ///   the result stream open until the whole chain settles, and `SendResults.cancel()`
    ///   tears the whole subtree down (cancellation is forwarded through the chain task
    ///   into both the own-work task and the descendants).
    ///
    /// Conflating the two (one task = own work + descendants) breaks queues on recursive
    /// feedback chains: `runNewest` evicts the still-unwinding ancestor — cancelling the
    /// live descendant chain — and `runOldest` leaks one slot per feedback round (the
    /// ancestor holds its slot while awaiting descendants). See
    /// `EffectQueueChainLifetimeTests`.
    ///
    /// The own-work task conveys its dispatched feedback-chain tasks to the chain task
    /// as its task **result** (see ``WorkTask``) — pure value flow through a structured
    /// synchronization point, with no shared mutable state.
    ///
    /// Note the asymmetry: cancelling the chain cancels own work, but cancelling own
    /// work (eviction, `cancel(id:)`) does NOT cancel already-dispatched descendants —
    /// they are independently-identified effects, consistent with the in-band error
    /// philosophy that one effect's termination never tears down its siblings.
    private func makeTask(
        effectKind: Effect<Action, Emission>.Kind,
        time: AnyClock<Duration>.Instant?,
        priority: TaskPriority?,
        tracksFeedbacks: Bool,
        emit: @escaping @Sendable (Result<Emission, any Error>) -> Void
    ) -> WorkTask?
    {
        let sendAction = self.sendAction
        let context = self.effectContext
        let feedbackEmit: @Sendable (Result<Emission, any Error>) -> Void = { result in
            if tracksFeedbacks {
                emit(result)
            }
        }

        let ownWork: WorkTask

        switch effectKind {
        case let .single(single):
            ownWork = WorkTask(priority: priority) { @concurrent in
                var feedbackTasks: [Task<(), Never>] = []
                do {
                    if let time {
                        try? await context.clock.sleep(until: time, tolerance: nil)
                    }
                    if let outcome = try await single.run(context) {
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
                return feedbackTasks
            }
            enqueueTask(
                ownWork,
                id: single.id,
                queue: single.queue,
                priority: priority,
                tracksFeedbacks: tracksFeedbacks
            )

        case let .sequence(sequence):
            ownWork = WorkTask(priority: priority) { @concurrent in
                var feedbackTasks: [Task<(), Never>] = []
                do {
                    if let time {
                        try? await context.clock.sleep(until: time, tolerance: nil)
                    }
                    if let seq = try await sequence.sequence(context) {
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
                    }
                }
                catch is CancellationError {
                    // Cancellation stops this effect's own work only. Already-dispatched
                    // feedback descendants are independent subtrees — awaited (and torn
                    // down on whole-chain cancellation) by the chain task below.
                }
                catch {
                    // Surface this sequence effect's error (e.g. an `AsyncSequence` that threw,
                    // or a `.stream` failure) in-band, leaving siblings running.
                    emit(.failure(error))
                }
                return feedbackTasks
            }
            enqueueTask(
                ownWork,
                id: sequence.id,
                queue: sequence.queue,
                priority: priority,
                tracksFeedbacks: tracksFeedbacks
            )

        case .next, .emission, .cancel, .updateQueue:
            return nil
        }

        if tracksFeedbacks {
            // Chain task: own work + all feedback descendants, received as `ownWork`'s result.
            // Feedback chain tasks never fail (their errors are surfaced in-band), so
            // awaiting them forwards cancellation and drains without throwing.
            return WorkTask(priority: priority) { @concurrent in
                let feedbackTasks = await _runTaskForwardingCancellation(ownWork)
                await _runTasksForwardingCancellation(feedbackTasks, priority: priority)
                return []
            }
        }
        else {
            // No chain tracking — the own-work task is the whole story
            // (its collected feedback tasks are always empty here).
            return ownWork
        }
    }

    /// Enqueues running `task` and sets up an unstructured cleanup task.
    private func enqueueTask(
        _ task: WorkTask,
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

        waitForTask(task, priority: priority) { self_ in
            Debug.print("[enqueueTask] Task completed, removing id-task: \(effectID)")

            self_.handleTaskCompleted(
                id: effectID,
                task: task,
                queue: queue,
                priority: priority,
                tracksFeedbacks: tracksFeedbacks
            )
        }
    }

    /// Sets up an unstructured task that waits for `task`, then re-enters the parent safe container.
    ///
    /// The cleanup task snapshots `self.withSendability` (a Sendable closure value) and uses
    /// it to re-enter the parent safe container under inherited sendability. `self` is handed
    /// back as a parameter to the inner callback, so the cleanup task does NOT need to capture
    /// `self` — letting `EffectQueueManager` remain non-Sendable.
    private func waitForTask<Success: Sendable>(
        _ task: Task<Success, Never>,
        priority: TaskPriority?,
        condition: @escaping @Sendable () -> Bool = { true },
        cleanUp: @escaping @Sendable (EffectQueueManager<Action, State, Emission>) -> Void,
        afterCleanUp: (@Sendable () -> Void)? = nil
    )
    {
        let withSendability = self.withSendability

        // Clean up after waiting for `task` to be completed.
        Task<(), Never>(priority: priority) { @concurrent in
            _ = await task.result

            guard condition() else { return }

            // Clean up with safe `self` access.
            await withSendability?(cleanUp)

            afterCleanUp?()
        }
    }

    /// Cancels the effect represented by `suspendedEffectTask`.
    ///
    /// If the effect is still suspended, it is removed from `pendingEffects` without ever running.
    /// If it has already been dequeued, the pending entry is gone, so
    /// `dequeuedTasks` forwards cancellation from the suspended-effect task
    /// to the running effect task.
    private func cancelPendingEffect(suspendedEffectTask: WorkTask)
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

        // Cancel registered `SendResults` supervisors so `Effect.cancel` reaches the whole `send`
        // (its `SendResults`), not just the effect tasks sharing this `id`.
        for id in sendingTasks.keys where predicate(id.value) {
            if let supervisors = sendingTasks.removeValue(forKey: id) {
                for supervisor in supervisors {
                    supervisor.cancel()
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

            // Re-check and remove through a local copy so the non-empty invariant
            // is explicit here instead of relying on the loop condition above.
            guard var pendings = pendingEffects[effectQueue], let pending = pendings.first else { break }
            pendings.removeFirst()
            pendingEffects[effectQueue] = pendings.isEmpty ? nil : pendings

            let time = calculateEffectTime(queue: queue)

            if pending.suspendedEffectTask.isCancelled {
                pending.onComplete.finish()
                continue
            }

            Debug
                .print(
                    "[dequeuePendingIfPossible] Dequeued pending effect (running: \(currentCount), maxCount: \(maxCount))"
                )

            // `makeTask` registers the dequeued task in `queuedRunningTasks`
            // synchronously, so the next loop iteration observes the updated
            // running count and stops when capacity is filled.
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

                waitForTask(
                    dequeuedTask,
                    priority: pending.priority,
                    cleanUp: { self_ in
                        self_.dequeuedTasks.removeValue(forKey: suspendedEffectTask)
                    },
                    afterCleanUp: {
                        onComplete.finish()
                    }
                )
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
        /// can await/cancel the full lifecycle through the original `SendResults`.
        let suspendedEffectTask: WorkTask

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
        case suspend(suspendedEffectTask: WorkTask)

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
/// `SendResults.cancel()` semantics by turning cancellation of the waiter into
/// cancellation of the underlying effect task.
@discardableResult
private func _runTaskForwardingCancellation<Success>(
    _ task: Task<Success, Never>
) async -> Success
{
    await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}

private func _runTasksForwardingCancellation<Success>(
    _ tasks: [Task<Success, Never>],
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
