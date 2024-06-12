import Foundation
#if !os(Linux)
import Combine
#endif

/// `@MainActor` version of ``Actomaton``.
@MainActor
package protocol MainActomaton<Action, State> {
    associatedtype Action: Sendable
    associatedtype State: Sendable

    init<Environment>(
        state: State,
        reducer: Reducer<Action, State, Environment>,
        environment: Environment
    ) where Environment: Sendable

    var state: State { get }

#if !os(Linux)
    var statePublisher: AnyPublisher<State, Never> { get }
#endif

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
    func send(
        _ action: Action,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), Error>?
}

// MARK: - MainActomaton Ver 2

/// Simplifed ``MainActomaton`` using Swift 5.9's `actomaton.assumeIsolated`.
@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
package final class MainActomaton2<Action, State>: MainActomaton
    where Action: Sendable, State: Sendable
{
#if os(Linux)
    package var state: State {
        actomaton.state
    }
#else
    @Published
    package private(set) var state: State

    package var statePublisher: AnyPublisher<State, Never> {
        self.$state.eraseToAnyPublisher()
    }
#endif

    private let actomaton: Actomaton<Action, State>

    private var stateTask: Task<Void, Never>?

    /// Initializer without `environment`.
    package init(
        state: State,
        reducer: Reducer<Action, State, ()>
    )
    {
        self.actomaton = Actomaton(
            state: state,
            reducer: reducer,
            executingActor: MainActor.shared
        )
#if !os(Linux)
        self.state = state

        let states = self.actomaton.assumeIsolated { actomaton in
            actomaton.$state.values.dropFirst()
        }

        self.stateTask = Task { @MainActor [weak self] in
            for await state in states {
                self?.state = state
            }
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
    ) -> Task<(), Error>?
    {
        self.actomaton.assumeIsolated { actomaton in
            actomaton.send(action, priority: priority, tracksFeedbacks: tracksFeedbacks)
        }
    }
}

// MARK: - MainActomaton Ver 1

/// Pre-Swift 5.9 ``MainActomaton`` where the code is mostly copied from ``Actomaton``
/// due to the workaround of uncustomizable actor executor.
///
/// - Important: From Swift 5.9, ``Actomaton`` now supports custom executor, so use ``MainActomaton2`` for latest OS versions.
@MainActor
package final class MainActomaton1<Action, State>: MainActomaton
    where Action: Sendable, State: Sendable
{
#if os(Linux)
    package private(set) var state: State
#else
    @Published
    package private(set) var state: State

    package var statePublisher: AnyPublisher<State, Never> {
        self.$state.eraseToAnyPublisher()
    }
#endif

    /// State-transforming function wrapper that is triggered by Action.
    private let reducer: Reducer<Action, State, ()>

    /// Effect-identified running tasks for manual cancellation or on-deinit cancellation.
    /// - Note: Multiple effects can have same ``EffectID``.
    private var runningTasks: [EffectID: Set<Task<(), Error>>] = [:]

    /// Effect-queue-designated running tasks for automatic cancellation & suspension.
    private var queuedRunningTasks: [EffectQueue: [Task<(), Error>]] = [:]

    /// Suspended effects.
    private var pendingEffectKinds: [EffectQueue: [Effect<Action>.Kind]] = [:]

    /// Tracked latest effect start date for delayed effects calculation.
    private var latestEffectDate: [EffectQueue: Date] = [:]

    /// Initializer without `environment`.
    package init(
        state: State,
        reducer: Reducer<Action, State, ()>
    )
    {
        self.state = state
        self.reducer = reducer
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

    deinit
    {
        // IMPORTANT:
        // Below code is a duplicate of `cancelRunningOrPendingEffects`
        // due to too strict Swift Concurrency deinit isolation rule.
        // See `Actomaton.deinit` comment for more details.

        // Cancel running effects.
        for id in runningTasks.keys {
            if let previousTasks = runningTasks.removeValue(forKey: id) {
                for previousTask in previousTasks {
                    previousTask.cancel()
                }
            }
        }

        // Cancel pending effects.
        for (effectQueue, effectKinds) in pendingEffectKinds {
            for (i, _) in effectKinds.enumerated().reversed() {
                if let effectKind = pendingEffectKinds[effectQueue]?.remove(at: i) {
                    switch effectKind {
                    case let .single(single):
                        Task<Void, Error>.detached {
                            _ = try await single.run()
                        }
                        .cancel() // Cancel immediately.
                    case let .sequence(sequence):
                        Task<Void, Error>.detached {
                            _ = try await sequence.sequence()
                        }
                        .cancel() // Cancel immediately.
                    case .cancel:
                        return
                    }
                }
            }
        }

        Debug.print("[deinit] \(String(format: "%p", ObjectIdentifier(self).hashValue))")
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
    ) -> Task<(), Error>?
    {
        Debug.print("[send] \(action), priority = \(String(describing: priority)), tracksFeedbacks = \(tracksFeedbacks)")

        let effect = reducer.run(action, &state, ())

        var tasks: [Task<(), Error>] = []

        for effectKind in effect.kinds {
            if let task = performEffectKind(effectKind, priority: priority, tracksFeedbacks: tracksFeedbacks) {
                tasks.append(task)
            }
        }

        if tasks.isEmpty { return nil }

        let tasks_ = tasks

        // Unifies `tasks`.
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
}

// MARK: - Private

extension MainActomaton1
{
    private func performEffectKind(
        _ effectKind: Effect<Action>.Kind,
        priority: TaskPriority? = nil,
        tracksFeedbacks: Bool = false
    ) -> Task<(), Error>?
    {
        switch effectKind {
        case let .single(single):
            guard self.checkQueuePolicy(effectKind: effectKind) else { return nil }

            let delay = calculateEffectDelay(queue: effectKind.queue)
            return makeTask(single: single, delay: delay, priority: priority, tracksFeedbacks: tracksFeedbacks)

        case let .sequence(sequence):
            guard self.checkQueuePolicy(effectKind: effectKind) else { return nil }

            let delay = calculateEffectDelay(queue: effectKind.queue)
            return makeTask(sequence: sequence, delay: delay, priority: priority, tracksFeedbacks: tracksFeedbacks)

        case let .cancel(predicate):
            self.cancelRunningOrPendingEffects(predicate: predicate)
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
            let droppingCount = (self.queuedRunningTasks[queue.queue]?.count ?? 0) - maxCount + 1
            if droppingCount > 0 {
                for _ in 0 ..< droppingCount {
                    let droppingTask = self.queuedRunningTasks[queue.queue]?.removeFirst()

                    if let droppingTask = droppingTask {
#if DEBUG
                        let droppingEffectID = self.runningTasks
                            .first(where: { $0.value.contains(droppingTask) })?.key
                        Debug.print("[checkQueuePolicy] [runNewest] droppingEffectID = \(String(describing: droppingEffectID))")
#endif
                        droppingTask.cancel()
                    }
                }
            }

            // `Task` should be created.
            return true

        case let .runOldest(maxCount, overflowPolicy):
            let overflowCount = (self.queuedRunningTasks[queue.queue]?.count ?? 0) - maxCount
            if overflowCount >= 0 {
                switch overflowPolicy {
                case .suspendNew:
                    let maxCount = maxCount
                    let currentTaskCount = self.queuedRunningTasks[queue.queue]?.count ?? 0

                    if currentTaskCount >= maxCount {
                        // Enqueue to pending buffer.
                        Debug.print("[checkQueuePolicy] [runOldest-suspendNew] Enqueue to pending buffer")
                        self.pendingEffectKinds[queue.queue, default: []].append(effectKind)
                    }

                case .discardNew:
                    self.cancelEffectKind(effectKind)
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

    /// Calculates effect delay based on `latestTaskRunningDate`  for necessary sleep in `makeTask`.
    private func calculateEffectDelay(queue: AnyEffectQueue?) -> TimeInterval
    {
        // No queue means, immediate task run.
        guard let queue = queue else { return 0 }

        let delayAfterLatestEffect = queue.effectQueueDelay.timeInterval
        let latestEffectDate = self.latestEffectDate[queue.queue, default: Date(timeIntervalSince1970: 0)]

        let targetDelaySinceNow = max(latestEffectDate.timeIntervalSinceNow + delayAfterLatestEffect, 0)
        self.latestEffectDate[queue.queue] = Date(timeIntervalSinceNow: targetDelaySinceNow)

        Debug.print("[calculateEffectDelay] delayAfterLatestExec = \(delayAfterLatestEffect), latestEffectDate = \(latestEffectDate), targetDelaySinceNow = \(targetDelaySinceNow)")

        return targetDelaySinceNow
    }

    /// Makes `Task` from `async`.
    private func makeTask(
        single: Effect<Action>.Single,
        delay: TimeInterval,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), Error>
    {
        let task = Task.detached(priority: priority) { [weak self] in
            if delay > 0 {
                // NOTE:
                // In case of cancellation, this `sleep` should not early-exit here
                // and let actual effect handle it, so use `try?`.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let nextAction = try await single.run()

            // Feed back `nextAction`.
            if let nextAction = nextAction {
                let feedbackTask = await self?.send(nextAction, priority: priority, tracksFeedbacks: tracksFeedbacks)
                if tracksFeedbacks {
                    try await feedbackTask?.value
                }
            }
        }

        self.enqueueTask(task, id: single.id, queue: single.queue, priority: priority, tracksFeedbacks: tracksFeedbacks)

        return task
    }

    /// Makes `Task` from `AsyncSequence`.
    private func makeTask(
        sequence: Effect<Action>._Sequence,
        delay: TimeInterval,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> Task<(), Error>
    {
        let task = Task<(), Error>.detached(priority: priority) { [weak self] in
            if delay > 0 {
                // NOTE:
                // In case of cancellation, this `sleep` should not early-exit here
                // and let actual effect handle it, so use `try?`.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let seq = try await sequence.sequence() else { return }

            var feedbackTasks: [Task<(), Error>] = []

            for try await nextAction in seq {
                // Feed back `nextAction`.
                let feedbackTask = await self?.send(nextAction, priority: priority, tracksFeedbacks: tracksFeedbacks)

                if let feedbackTask = feedbackTask {
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

        self.enqueueTask(task, id: sequence.id, queue: sequence.queue, priority: priority, tracksFeedbacks: tracksFeedbacks)

        return task
    }

    /// Enqueues running `task` or pending `effectKind` to the buffer, and dequeue after completed.
    private func enqueueTask(
        _ task: Task<(), Error>,
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

        if let queue = queue {
            Debug.print("[enqueueTask] Append queue-task: \(queue)")
            self.queuedRunningTasks[queue.queue, default: []].append(task)
        }

        // Clean up after `task` is completed.
        Task<(), Error>.detached(priority: priority) { [weak self] in
            // Wait for `task` to complete.
            try await task.value

            Debug.print("[enqueueTask] Task completed, removing id-task: \(effectID)")
            await self?.removeTask(id: effectID, task: task)

            if let queue = queue {
                await self?.removeTaskIfNeeded(task: task, in: queue)

                switch queue.effectQueuePolicy {
                case .runOldest(_, .suspendNew):
                    if let pendingEffectKind = await self?.dequeuePendingEffectKindIfPossible(queue: queue) {
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

    private func removeTask(id: EffectID, task: Task<(), Error>)
    {
        self.runningTasks[id]?.remove(task)
    }

    private func removeTaskIfNeeded(task: Task<(), Error>, in queue: AnyEffectQueue)
    {
        // NOTE: Finding `removingIndex` and `remove` must be atomic.
        if let removingIndex = self.queuedRunningTasks[queue.queue]?.firstIndex(where: { $0 == task }) {
            Debug.print("[enqueueTask] Remove completed queue-task: \(queue) \(removingIndex)")
            self.queuedRunningTasks[queue.queue]?.remove(at: removingIndex)
        }
    }

    private func dequeuePendingEffectKindIfPossible(queue: AnyEffectQueue) -> Effect<Action>.Kind?
    {
        // NOTE: `isEmpty` check and `removeFirst` must be atomic.
        guard self.pendingEffectKinds[queue.queue]?.isEmpty == false else { return nil }
        return self.pendingEffectKinds[queue.queue]?.removeFirst()
    }

    /// Cancels currently running effects as well as pending effects.
    private func cancelRunningOrPendingEffects(predicate: (EffectID) -> Bool)
    {
        // Cancel running effects.
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
                    if let effectKind = pendingEffectKinds[effectQueue]?.remove(at: i) {
                        self.cancelEffectKind(effectKind)
                    }
                }
            }
        }
    }

    /// Cancels `effectKind`'s `single` or `sequence` immediately
    /// so that cancellation can still be delivered to `Effect`'s async scope.
    private func cancelEffectKind(_ effectKind: Effect<Action>.Kind)
    {
        switch effectKind {
        case let .single(single):
            Task<Void, Error>.detached {
                _ = try await single.run()
            }
            .cancel() // Cancel immediately.
        case let .sequence(sequence):
            Task<Void, Error>.detached {
                _ = try await sequence.sequence()
            }
            .cancel() // Cancel immediately.
        case .cancel:
            return
        }
    }
}
