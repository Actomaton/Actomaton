/// Effect type to run `async`, `AsyncSequence`, or cancellation.
///
/// `Effect` carries two channels:
///
/// - **`Action`**: synchronous (`.next`) and asynchronous (`.single` / `.sequence` / `.stream`)
///   feedback actions, recursively re-fed into the reducer through ``MealyMachine/send(_:)``.
/// - **`Emission`**: side-channel values yielded back to top-level `send` callers.
///   Use `Never` when no side-channel is needed.
///
/// Async-effect steps produce ``Outcome`` values that may carry an action, an emission, or both.
public struct Effect<Action, Emission>
{
    internal var kinds: [Kind]
}

// MARK: - Public Initializers (canonical: Outcome)

// NOTE: The canonical inits are marked `@_disfavoredOverload` so that, when `Emission == Never`,
// Swift overload resolution prefers the more specialized `init(run: -> Action?)` (and friends)
// defined later in the `extension Effect where Emission == Never` block. This keeps existing
// `Effect { context in return .someAction }` call sites unambiguous when `Emission == Never`,
// while non-`Never` users still get the same Outcome-returning init via `Effect { context in
// return .action(.foo) }` / `.emission(...)` / `.both(...)`.

extension Effect
{
    // MARK: - Single async

    /// Single-`async` side-effect with `EffectContext`.
    ///
    /// The closure returns an ``Outcome`` describing either a feedback action, an emitted
    /// `Emission`, or both. Return `nil` to produce no output.
    @_disfavoredOverload
    public init(
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Outcome?
    )
    {
        self.init(kinds: [.single(Single(id: nil, queue: nil, priority: priority, run: run))])
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    @_disfavoredOverload
    public init<ID>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Outcome?
    )
        where ID: EffectID
    {
        self.init(kinds: [.single(Single(id: id.map(_EffectID.init), queue: nil, priority: priority, run: run))])
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    @_disfavoredOverload
    public init<Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Outcome?
    ) where Queue: EffectQueue
    {
        self.init(kinds: [.single(Single(id: nil, queue: queue, priority: priority, run: run))])
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    @_disfavoredOverload
    public init<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Outcome?
    ) where ID: EffectID, Queue: EffectQueue
    {
        self.init(kinds: [.single(Single(id: id.map(_EffectID.init), queue: queue, priority: priority, run: run))])
    }

    // MARK: - AsyncSequence

    /// `AsyncSequence` side-effect with `EffectContext`.
    ///
    /// Each element produced by the underlying `AsyncSequence` is an ``Outcome`` describing
    /// a feedback action, an emission, or both.
    public static func sequence<S, E: Error>(
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Emission>
        where S: AsyncSequence<Outcome, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: nil,
                    queue: nil,
                    priority: priority,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public static func sequence<ID, S, E: Error>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Emission>
        where ID: EffectID, S: AsyncSequence<Outcome, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: id.map(_EffectID.init),
                    queue: nil,
                    priority: priority,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func sequence<S, E: Error, Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Emission>
        where Queue: EffectQueue, S: AsyncSequence<Outcome, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: nil,
                    queue: queue,
                    priority: priority,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func sequence<ID, S, E: Error, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Emission>
        where ID: EffectID, Queue: EffectQueue, S: AsyncSequence<Outcome, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: id.map(_EffectID.init),
                    queue: queue,
                    priority: priority,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    // MARK: - Finite/Infinite Stream

    /// Stream-style side-effect that emits ``Outcome``s via `send`, with `EffectContext`.
    ///
    /// - Parameter autoFinish: `false` (default) keeps the stream alive after the closure
    ///   returns; `true` finishes it on return.
    /// - Parameter priority: Priority of the task that runs this effect.
    /// - Parameter bufferingPolicy: Buffering policy of the underlying `AsyncThrowingStream`.
    public static func stream(
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Outcome, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Outcome) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Emission>
    {
        .sequence(priority: priority) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Stream-style side-effect with cancellation identifier.
    public static func stream<ID>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Outcome, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Outcome) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Emission>
        where ID: EffectID
    {
        .sequence(id: id, priority: priority) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Stream-style side-effect with effect-management queue.
    public static func stream<Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Outcome, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Outcome) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Emission>
        where Queue: EffectQueue
    {
        .sequence(queue: queue, priority: priority) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Stream-style side-effect with cancellation identifier and effect-management queue.
    public static func stream<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Outcome, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Outcome) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Emission>
        where ID: EffectID, Queue: EffectQueue
    {
        .sequence(id: id, queue: queue, priority: priority) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Bridges the user's `(send, context) async throws -> Void` closure into an
    /// `AsyncThrowingStream` whose continuation is finished when the closure returns
    /// or throws, and whose termination cancels the running task.
    private static func _makeStream(
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Outcome) -> Void,
            EffectContext
        ) async throws -> Void,
        context: EffectContext,
        bufferingPolicy: AsyncThrowingStream<Outcome, any Error>.Continuation.BufferingPolicy,
        autoFinish: Bool
    ) -> AsyncThrowingStream<Outcome, any Error>
    {
        AsyncThrowingStream<Outcome, any Error>(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task<Void, any Error> {
                do {
                    try await stream({ continuation.yield($0) }, context)
                    if autoFinish {
                        continuation.finish()
                    }
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - fireAndForget

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    public static func fireAndForget(
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action, Emission>
    {
        self.init(priority: priority, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public static func fireAndForget<ID>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action, Emission>
        where ID: EffectID
    {
        self.init(id: id, priority: priority, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action, Emission>
        where Queue: EffectQueue
    {
        self.init(queue: queue, priority: priority, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action, Emission>
        where ID: EffectID, Queue: EffectQueue
    {
        self.init(id: id, queue: queue, priority: priority, run: { context in
            try await run(context)
            return nil
        })
    }

    // MARK: - next (sync feedback action only)

    /// No `async` side-effect, only returning next action (synchronous reducer feedback).
    public static func next(action: Action) -> Effect<Action, Emission>
    {
        self.init(kinds: [.next(action)])
    }

    // MARK: - emit (sync side-channel emission only)

    /// No `async` side-effect, only emitting an `Emission` value to the `send` caller.
    public static func emit(_ emission: Emission) -> Effect<Action, Emission>
    {
        self.init(kinds: [.emission(emission)])
    }

    // MARK: - cancel

    /// Cancels running `async`s by specifying `ids`.
    public static func cancel(ids: @escaping @Sendable (any EffectID) -> Bool) -> Effect<Action, Emission>
    {
        Effect(kinds: [.cancel(ids)])
    }

    /// Cancels running `async`s by specifying `identifier`.
    public static func cancel<ID>(id: ID) -> Effect<Action, Emission>
        where ID: EffectID
    {
        Effect(kinds: [.cancel { AnyHashable($0) == AnyHashable(id) }])
    }

    // MARK: - updateQueue

    /// Updates queue metadata (e.g. dynamic `maxCount`) and re-evaluates pending effects
    /// without creating any async task.
    ///
    /// Use this when changing queue capacity via state without sending a new effect:
    /// ```swift
    /// case let .updateMaxConcurrent(n):
    ///     state.maxConcurrent = n
    ///     return .updateQueue(DynamicQueue(maxCount: n))
    /// ```
    public static func updateQueue<Queue>(_ queue: Queue) -> Effect<Action, Emission>
        where Queue: EffectQueue
    {
        Effect(kinds: [.updateQueue(queue)])
    }
}

// MARK: - Convenience for Emission == Never (Action-only API)

extension Effect where Emission == Never
{
    /// Single-`async` side-effect returning a feedback action (or `nil`).
    public init(
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    )
    {
        self.init(priority: priority, run: { context -> Outcome? in
            (try await run(context)).map(Outcome.action)
        })
    }

    /// Single-`async` side-effect returning a feedback action (or `nil`).
    /// - Parameter id: Cancellation identifier.
    public init<ID>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    )
        where ID: EffectID
    {
        self.init(id: id, priority: priority, run: { context -> Outcome? in
            (try await run(context)).map(Outcome.action)
        })
    }

    /// Single-`async` side-effect returning a feedback action (or `nil`).
    /// - Parameter queue: Effect management queue.
    public init<Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    ) where Queue: EffectQueue
    {
        self.init(queue: queue, priority: priority, run: { context -> Outcome? in
            (try await run(context)).map(Outcome.action)
        })
    }

    /// Single-`async` side-effect returning a feedback action (or `nil`).
    public init<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    ) where ID: EffectID, Queue: EffectQueue
    {
        self.init(id: id, queue: queue, priority: priority, run: { context -> Outcome? in
            (try await run(context)).map(Outcome.action)
        })
    }

    /// `AsyncSequence<Action>` side-effect.
    public static func sequence<S, E: Error>(
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Never>
        where S: AsyncSequence<Action, E> & SendableMetatype
    {
        Effect<Action, Never>(
            kinds: [.sequence(
                Effect<Action, Never>._Sequence(
                    id: nil,
                    queue: nil,
                    priority: priority,
                    sequence: { context in
                        guard let seq = try await sequence(context) else { return nil }
                        return seq.map(Outcome.action).eraseToAnyError()
                    }
                )
            )]
        )
    }

    /// `AsyncSequence<Action>` side-effect with cancellation identifier.
    public static func sequence<ID, S, E: Error>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Never>
        where ID: EffectID, S: AsyncSequence<Action, E> & SendableMetatype
    {
        Effect<Action, Never>(
            kinds: [.sequence(
                Effect<Action, Never>._Sequence(
                    id: id.map(_EffectID.init),
                    queue: nil,
                    priority: priority,
                    sequence: { context in
                        guard let seq = try await sequence(context) else { return nil }
                        return seq.map(Outcome.action).eraseToAnyError()
                    }
                )
            )]
        )
    }

    /// `AsyncSequence<Action>` side-effect with effect-management queue.
    public static func sequence<S, E: Error, Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Never>
        where Queue: EffectQueue, S: AsyncSequence<Action, E> & SendableMetatype
    {
        Effect<Action, Never>(
            kinds: [.sequence(
                Effect<Action, Never>._Sequence(
                    id: nil,
                    queue: queue,
                    priority: priority,
                    sequence: { context in
                        guard let seq = try await sequence(context) else { return nil }
                        return seq.map(Outcome.action).eraseToAnyError()
                    }
                )
            )]
        )
    }

    /// `AsyncSequence<Action>` side-effect with cancellation identifier and effect-management queue.
    public static func sequence<ID, S, E: Error, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action, Never>
        where ID: EffectID, Queue: EffectQueue, S: AsyncSequence<Action, E> & SendableMetatype
    {
        Effect<Action, Never>(
            kinds: [.sequence(
                Effect<Action, Never>._Sequence(
                    id: id.map(_EffectID.init),
                    queue: queue,
                    priority: priority,
                    sequence: { context in
                        guard let seq = try await sequence(context) else { return nil }
                        return seq.map(Outcome.action).eraseToAnyError()
                    }
                )
            )]
        )
    }

    /// Stream-style side-effect that emits `Action`s via `send` (no side-channel).
    ///
    /// - Parameter autoFinish: `false` (default) keeps the stream alive after the closure
    ///   returns; `true` finishes it on return.
    /// - Parameter priority: Priority of the task that runs this effect.
    /// - Parameter bufferingPolicy: Buffering policy of the underlying `AsyncThrowingStream`.
    public static func stream(
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Never>
    {
        Effect<Action, Never>.stream(
            priority: priority,
            bufferingPolicy: _liftBufferingPolicy(bufferingPolicy),
            autoFinish: autoFinish
        ) { sendOutcome, context in
            try await stream({ action in sendOutcome(.action(action)) }, context)
        }
    }

    /// Stream-style side-effect with cancellation identifier.
    public static func stream<ID>(
        id: ID? = nil,
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Never>
        where ID: EffectID
    {
        Effect<Action, Never>.stream(
            id: id,
            priority: priority,
            bufferingPolicy: _liftBufferingPolicy(bufferingPolicy),
            autoFinish: autoFinish
        ) { sendOutcome, context in
            try await stream({ action in sendOutcome(.action(action)) }, context)
        }
    }

    /// Stream-style side-effect with effect-management queue.
    public static func stream<Queue>(
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Never>
        where Queue: EffectQueue
    {
        Effect<Action, Never>.stream(
            queue: queue,
            priority: priority,
            bufferingPolicy: _liftBufferingPolicy(bufferingPolicy),
            autoFinish: autoFinish
        ) { sendOutcome, context in
            try await stream({ action in sendOutcome(.action(action)) }, context)
        }
    }

    /// Stream-style side-effect with cancellation identifier and effect-management queue.
    public static func stream<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        priority: TaskPriority? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action, Never>
        where ID: EffectID, Queue: EffectQueue
    {
        Effect<Action, Never>.stream(
            id: id, queue: queue, priority: priority,
            bufferingPolicy: _liftBufferingPolicy(bufferingPolicy),
            autoFinish: autoFinish
        ) { sendOutcome, context in
            try await stream({ action in sendOutcome(.action(action)) }, context)
        }
    }

    /// Translates an `T`-typed buffering policy to the equivalent `U`-typed one.
    private static func _liftBufferingPolicy<T, U>(
        _ policy: AsyncThrowingStream<T, any Error>.Continuation.BufferingPolicy
    ) -> AsyncThrowingStream<U, any Error>.Continuation.BufferingPolicy
    {
        switch policy {
        case .unbounded:
            return .unbounded
        case let .bufferingNewest(n):
            return .bufferingNewest(n)
        case let .bufferingOldest(n):
            return .bufferingOldest(n)
        @unknown default:
            return .unbounded
        }
    }
}

// MARK: - Monoid

extension Effect
{
    public static var empty: Effect<Action, Emission>
    {
        self.init(kinds: [])
    }

    public static func + (l: Effect, r: Effect) -> Effect
    {
        .init(kinds: l.kinds + r.kinds)
    }

    public mutating func append(_ other: Effect)
    {
        self.kinds.append(contentsOf: other.kinds)
    }

    public static func combine(_ effects: [Effect]) -> Effect
    {
        effects.reduce(into: .empty, { $0.append($1) })
    }

    public static func combine(_ effects: Effect...) -> Effect
    {
        self.combine(effects)
    }
}

// MARK: - Functor

extension Effect
{
    /// Maps `Action` while keeping `Emission`.
    public func map<Action2>(action f: @escaping @Sendable (Action) -> Action2)
        -> Effect<Action2, Emission>
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(action: f))

            case let .sequence(sequence):
                return .sequence(sequence.map(action: f))

            case let .next(action):
                return .next(f(action))

            case let .emission(value):
                return .emission(value)

            case let .cancel(predicate):
                return .cancel(predicate)

            case let .updateQueue(queue):
                return .updateQueue(queue)
            }
        })
    }

    /// Maps `Emission` while keeping `Action`.
    public func map<Emission2>(emission f: @escaping @Sendable (Emission) -> Emission2)
        -> Effect<Action, Emission2>
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(emission: f))

            case let .sequence(sequence):
                return .sequence(sequence.map(emission: f))

            case let .next(action):
                return .next(action)

            case let .emission(value):
                return .emission(f(value))

            case let .cancel(predicate):
                return .cancel(predicate)

            case let .updateQueue(queue):
                return .updateQueue(queue)
            }
        })
    }

    /// Changes `_EffectID`.
    public func map<ID>(id f: @escaping ((any EffectID)?) -> ID?) -> Effect
        where ID: EffectID
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(id: f))

            case let .sequence(sequence):
                return .sequence(sequence.map(id: f))

            case .next, .emission:
                return kind

            case let .cancel(predicate):
                return .cancel(predicate)

            case .updateQueue:
                return kind
            }
        })
    }

    /// Changes `EffectQueue`.
    public func map<Queue>(queue f: @escaping ((any EffectQueue)?) -> Queue?) -> Effect
        where Queue: EffectQueue
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(queue: { f($0) }))

            case let .sequence(sequence):
                return .sequence(sequence.map(queue: { f($0) }))

            case .next, .emission:
                return kind

            case let .cancel(predicate):
                return .cancel(predicate)

            case let .updateQueue(queue):
                if let newQueue = f(queue) {
                    return .updateQueue(newQueue)
                }
                return kind
            }
        })
    }
}

// MARK: - Internals

extension Effect
{
    internal var singles: [Single]
    {
        self.kinds.compactMap { $0.single }
    }

    internal var sequences: [_Sequence]
    {
        self.kinds.compactMap { $0.sequence }
    }

    internal var cancels: [(any EffectID) -> Bool]
    {
        self.kinds.compactMap { $0.cancel }
    }
}

extension Effect
{
    internal enum Kind
    {
        /// Single async func effect.
        case single(Single)

        /// AsyncSequence effect.
        case sequence(_Sequence)

        /// Synchronous feedback action (re-fed to the reducer by ``MealyMachine/send(_:)``).
        case next(Action)

        /// Synchronous side-channel emission (delivered to caller via the top-level result stream).
        case emission(Emission)

        /// Cancellation effect with filtering effect IDs by a predicate.
        case cancel(@Sendable (any EffectID) -> Bool)

        /// Updates queue metadata (e.g. dynamic `maxCount`) and re-evaluates pending effects.
        case updateQueue(any EffectQueue)

        internal var single: Single?
        {
            guard case let .single(value) = self else { return nil }
            return value
        }

        internal var sequence: _Sequence?
        {
            guard case let .sequence(value) = self else { return nil }
            return value
        }

        internal var cancel: ((any EffectID) -> Bool)?
        {
            guard case let .cancel(value) = self else { return nil }
            return value
        }

        internal var id: _EffectID?
        {
            switch self {
            case let .single(single):
                return single.id
            case let .sequence(sequence):
                return sequence.id
            case .next, .emission:
                return nil
            case .cancel:
                return nil
            case .updateQueue:
                return nil
            }
        }

        internal var queue: (any EffectQueue)?
        {
            switch self {
            case let .single(single):
                return single.queue
            case let .sequence(sequence):
                return sequence.queue
            case .next, .emission:
                return nil
            case .cancel:
                return nil
            case let .updateQueue(queue):
                return queue
            }
        }

        internal var priority: TaskPriority?
        {
            switch self {
            case let .single(single):
                return single.priority
            case let .sequence(sequence):
                return sequence.priority
            case .next, .emission:
                return nil
            case .cancel:
                return nil
            case .updateQueue:
                return nil
            }
        }
    }

    /// Wrapper of `async`.
    internal struct Single
    {
        internal let id: _EffectID?
        internal let queue: (any EffectQueue)?
        internal let priority: TaskPriority?
        internal let run: @Sendable (EffectContext) async throws -> Outcome?

        internal init(
            id: _EffectID? = nil,
            queue: (any EffectQueue)? = nil,
            priority: TaskPriority? = nil,
            run: @escaping @Sendable (EffectContext) async throws -> Outcome?
        )
        {
            self.id = id
            self.queue = queue
            self.priority = priority
            self.run = run
        }

        internal func map<Action2>(
            action f: @escaping @Sendable (Action) -> Action2
        ) -> Effect<Action2, Emission>.Single
        {
            .init(id: id, queue: queue, priority: priority) { context in
                guard let outcome = try await run(context) else { return nil }
                return outcome.map(action: f)
            }
        }

        internal func map<Emission2>(
            emission f: @escaping @Sendable (Emission) -> Emission2
        ) -> Effect<Action, Emission2>.Single
        {
            .init(id: id, queue: queue, priority: priority) { context in
                guard let outcome = try await run(context) else { return nil }
                return outcome.map(emission: f)
            }
        }

        internal func map<ID>(id f: @escaping ((any EffectID)?) -> ID?) -> Effect.Single
            where ID: EffectID
        {
            .init(id: f(id?.value).map(_EffectID.init), queue: queue, priority: priority, run: run)
        }

        internal func map(
            queue f: @escaping ((any EffectQueue)?) -> (any EffectQueue)?
        ) -> Effect.Single
        {
            .init(id: id, queue: f(queue), priority: priority, run: run)
        }
    }

    /// Wrapper of `AsyncSequence`.
    ///
    /// The wrapped existential is constrained to `SendableMetatype` (not `Sendable`)
    /// for the same reason as ``MealyMachine``: the produced `AsyncSequence` instance is not
    /// required to be `Sendable`, but its metatype must be so that the existential can appear in
    /// `@Sendable` closure signatures.
    internal struct _Sequence
    {
        internal let id: _EffectID?
        internal let queue: (any EffectQueue)?
        internal let priority: TaskPriority?
        internal let sequence: @Sendable (EffectContext) async throws
            -> (any AsyncSequence<Outcome, any Error> & SendableMetatype)?

        internal init(
            id: _EffectID? = nil,
            queue: (any EffectQueue)? = nil,
            priority: TaskPriority? = nil,
            sequence: @escaping @Sendable (EffectContext) async throws
                -> (any AsyncSequence<Outcome, any Error> & SendableMetatype)?
        )
        {
            self.id = id
            self.queue = queue
            self.priority = priority
            self.sequence = sequence
        }

        internal func map<Action2>(
            action f: @escaping @Sendable (Action) -> Action2
        ) -> Effect<Action2, Emission>._Sequence
        {
            // Open Existential
            @Sendable
            func _mapAsyncSequence(
                _ seq: some AsyncSequence<Outcome, any Error> & SendableMetatype
            ) -> any AsyncSequence<Effect<Action2, Emission>.Outcome, any Error> & SendableMetatype {
                seq.map { $0.map(action: f) }
            }

            return .init(id: id, queue: queue, priority: priority, sequence: { context in
                guard let seq = try await sequence(context) else { return nil }
                return _mapAsyncSequence(seq)
            })
        }

        internal func map<Emission2>(
            emission f: @escaping @Sendable (Emission) -> Emission2
        ) -> Effect<Action, Emission2>._Sequence
        {
            @Sendable
            func _mapAsyncSequence(
                _ seq: some AsyncSequence<Outcome, any Error> & SendableMetatype
            ) -> any AsyncSequence<Effect<Action, Emission2>.Outcome, any Error> & SendableMetatype {
                seq.map { $0.map(emission: f) }
            }

            return .init(id: id, queue: queue, priority: priority, sequence: { context in
                guard let seq = try await sequence(context) else { return nil }
                return _mapAsyncSequence(seq)
            })
        }

        internal func map<ID>(id f: @escaping ((any EffectID)?) -> ID?) -> Effect._Sequence
            where ID: EffectID
        {
            .init(id: f(id?.value).map(_EffectID.init), queue: queue, priority: priority, sequence: sequence)
        }

        internal func map(
            queue f: @escaping ((any EffectQueue)?) -> (any EffectQueue)?
        ) -> Effect._Sequence
        {
            .init(id: id, queue: f(queue), priority: priority, sequence: sequence)
        }
    }
}

// MARK: - Outcome

extension Effect
{
    /// What an async (`.single` / `.sequence` / `.stream`) step produces in a single emission.
    ///
    /// - `action`: re-feed `Action` into the reducer; no side-channel emission.
    /// - `emit`: emit `Emission` to the caller's result stream; no reducer feedback.
    /// - `both`: do both atomically in the same step.
    public enum Outcome
    {
        case action(Action)
        case emission(Emission)
        case both(Action, Emission)

        /// Returns the action half (if any).
        public var action: Action?
        {
            switch self {
            case let .action(action), let .both(action, _):
                return action
            case .emission:
                return nil
            }
        }

        /// Returns the emitted value (if any).
        public var emission: Emission?
        {
            switch self {
            case let .emission(emission), let .both(_, emission):
                return emission
            case .action:
                return nil
            }
        }
    }
}

extension Effect.Outcome: Sendable where Action: Sendable, Emission: Sendable {}

// MARK: - Outcome mapping (internal)

extension Effect.Outcome
{
    internal func map<Action2>(action f: (Action) -> Action2) -> Effect<Action2, Emission>.Outcome
    {
        switch self {
        case let .action(action):
            return .action(f(action))
        case let .emission(value):
            return .emission(value)
        case let .both(action, value):
            return .both(f(action), value)
        }
    }

    internal func map<Emission2>(emission f: (Emission) -> Emission2) -> Effect<Action, Emission2>.Outcome
    {
        switch self {
        case let .action(action):
            return .action(action)
        case let .emission(value):
            return .emission(f(value))
        case let .both(action, value):
            return .both(action, f(value))
        }
    }
}
