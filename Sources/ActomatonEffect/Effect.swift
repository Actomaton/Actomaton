/// Effect type to run `async`, `AsyncSequence`, or cancellation.
public struct Effect<Action>
{
    internal let kinds: [Kind]
}

// MARK: - Public Initializers

extension Effect
{
    // MARK: - Single async

    /// Single-`async` side-effect with `EffectContext`.
    public init(
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    )
    {
        self.init(kinds: [.single(Single(id: nil, queue: nil, run: run))])
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public init<ID>(
        id: ID? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    )
        where ID: EffectID
    {
        self.init(kinds: [.single(Single(id: id.map(_EffectID.init), queue: nil, run: run))])
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<Queue>(
        queue: Queue? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    ) where Queue: EffectQueue
    {
        self.init(kinds: [.single(Single(id: nil, queue: queue, run: run))])
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    ) where ID: EffectID, Queue: EffectQueue
    {
        self.init(kinds: [.single(Single(id: id.map(_EffectID.init), queue: queue, run: run))])
    }

    // MARK: - AsyncSequence

    /// `AsyncSequence` side-effect with `EffectContext`.
    public static func sequence<S, E: Error>(
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action>
        where S: AsyncSequence<Action, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: nil,
                    queue: nil,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public static func sequence<ID, S, E: Error>(
        id: ID? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action>
        where ID: EffectID, S: AsyncSequence<Action, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: id.map(_EffectID.init),
                    queue: nil,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func sequence<S, E: Error, Queue>(
        queue: Queue? = nil,
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action>
        where Queue: EffectQueue, S: AsyncSequence<Action, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: nil,
                    queue: queue,
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
        _ sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) -> Effect<Action>
        where ID: EffectID, Queue: EffectQueue, S: AsyncSequence<Action, E> & SendableMetatype
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: id.map(_EffectID.init),
                    queue: queue,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    // MARK: - Finite/Infinite Stream

    /// Stream-style side-effect that emits `Action`s via `send`, with `EffectContext`.
    ///
    /// - Parameter autoFinish: `false` (default) keeps the stream alive after the closure
    ///   returns — for bridging long-lived observers (delegates, callbacks, notifications)
    ///   where the closure stores `send` into an outer reference (e.g. captured by a
    ///   handler) and keeps emitting until cancelled externally. `true` finishes the
    ///   stream on closure return — for self-terminating producers driven entirely inline.
    /// - Parameter bufferingPolicy: Buffering policy of the underlying
    ///   `AsyncThrowingStream`. Defaults to `.unbounded`; pass `.bufferingNewest(n)` or
    ///   `.bufferingOldest(n)` to apply backpressure for high-frequency producers.
    public static func stream(
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action>
    {
        .sequence {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Stream-style side-effect that emits `Action`s via `send`, with `EffectContext`.
    ///
    /// - Parameter id: Cancellation identifier.
    /// - Parameter autoFinish: `false` (default) keeps the stream alive after the closure
    ///   returns — for bridging long-lived observers that hold `send` and keep emitting
    ///   until cancelled externally. `true` finishes the stream on closure return —
    ///   for self-terminating producers driven entirely inline.
    /// - Parameter bufferingPolicy: Buffering policy of the underlying
    ///   `AsyncThrowingStream`. Defaults to `.unbounded`; pass `.bufferingNewest(n)` or
    ///   `.bufferingOldest(n)` to apply backpressure for high-frequency producers.
    public static func stream<ID>(
        id: ID? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action>
        where ID: EffectID
    {
        .sequence(id: id) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Stream-style side-effect that emits `Action`s via `send`, with `EffectContext`.
    ///
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    /// - Parameter autoFinish: `false` (default) keeps the stream alive after the closure
    ///   returns — for bridging long-lived observers that hold `send` and keep emitting
    ///   until cancelled externally. `true` finishes the stream on closure return —
    ///   for self-terminating producers driven entirely inline.
    /// - Parameter bufferingPolicy: Buffering policy of the underlying
    ///   `AsyncThrowingStream`. Defaults to `.unbounded`; pass `.bufferingNewest(n)` or
    ///   `.bufferingOldest(n)` to apply backpressure for high-frequency producers.
    public static func stream<Queue>(
        queue: Queue? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action>
        where Queue: EffectQueue
    {
        .sequence(queue: queue) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Stream-style side-effect that emits `Action`s via `send`, with `EffectContext`.
    ///
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    /// - Parameter autoFinish: `false` (default) keeps the stream alive after the closure
    ///   returns — for bridging long-lived observers that hold `send` and keep emitting
    ///   until cancelled externally. `true` finishes the stream on closure return —
    ///   for self-terminating producers driven entirely inline.
    /// - Parameter bufferingPolicy: Buffering policy of the underlying
    ///   `AsyncThrowingStream`. Defaults to `.unbounded`; pass `.bufferingNewest(n)` or
    ///   `.bufferingOldest(n)` to apply backpressure for high-frequency producers.
    public static func stream<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy = .unbounded,
        autoFinish: Bool = false,
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void
    ) -> Effect<Action>
        where ID: EffectID, Queue: EffectQueue
    {
        .sequence(id: id, queue: queue) {
            _makeStream(stream, context: $0, bufferingPolicy: bufferingPolicy, autoFinish: autoFinish)
        }
    }

    /// Bridges the user's `(send, context) async throws -> Void` closure into an
    /// `AsyncThrowingStream` whose continuation is finished when the closure returns
    /// or throws, and whose termination cancels the running task.
    private static func _makeStream(
        _ stream: @escaping @Sendable (
            _ send: @escaping @Sendable (sending Action) -> Void,
            EffectContext
        ) async throws -> Void,
        context: EffectContext,
        bufferingPolicy: AsyncThrowingStream<Action, any Error>.Continuation.BufferingPolicy,
        autoFinish: Bool
    ) -> AsyncThrowingStream<Action, any Error>
    {
        AsyncThrowingStream<Action, any Error>(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task<Void, any Error> {
                do {
                    try await stream({ continuation.yield($0) }, context)
                    if autoFinish {
                        continuation.finish()
                    }
                } catch {
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
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action>
    {
        self.init(run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public static func fireAndForget<ID>(
        id: ID? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action>
        where ID: EffectID
    {
        self.init(id: id, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<Queue>(
        queue: Queue? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action>
        where Queue: EffectQueue
    {
        self.init(queue: queue, run: { context in
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
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action>
        where ID: EffectID, Queue: EffectQueue
    {
        self.init(id: id, queue: queue, run: { context in
            try await run(context)
            return nil
        })
    }

    // MARK: - next

    /// No `async` side-effect, only returning next action.
    public static func next(action: Action) -> Effect<Action>
    {
        self.init(kinds: [.next(action)])
    }

    // MARK: - cancel

    /// Cancels running `async`s by specifying `ids`.
    public static func cancel(ids: @escaping @Sendable (any EffectID) -> Bool) -> Effect<Action>
    {
        Effect(kinds: [.cancel(ids)])
    }

    /// Cancels running `async`s by specifying `identifier`.
    public static func cancel<ID>(id: ID) -> Effect<Action>
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
    public static func updateQueue<Queue>(_ queue: Queue) -> Effect<Action>
        where Queue: EffectQueue
    {
        Effect(kinds: [.updateQueue(queue)])
    }
}

// MARK: - Monoid

extension Effect
{
    public static var empty: Effect<Action>
    {
        self.init(kinds: [])
    }

    public static func + (l: Effect, r: Effect) -> Effect
    {
        .init(kinds: l.kinds + r.kinds)
    }

    public static func combine(_ effects: [Effect]) -> Effect
    {
        effects.reduce(into: .empty, { $0 = $0 + $1 })
    }

    public static func combine(_ effects: Effect...) -> Effect
    {
        self.combine(effects)
    }
}

// MARK: - Functor

extension Effect
{
    /// Changes `Action`.
    public func map<Action2>(_ f: @escaping @Sendable (Action) -> Action2) -> Effect<Action2>
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(action: f))

            case let .sequence(sequence):
                return .sequence(sequence.map(action: f))

            case let .next(action):
                return .next(f(action))

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

            case .next:
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

            case .next:
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

        /// No async func effect, only returning next action only.
        case next(Action)

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
            case .next:
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
            case .next:
                return nil
            case .cancel:
                return nil
            case let .updateQueue(queue):
                return queue
            }
        }
    }

    /// Wrapper of `async`.
    internal struct Single
    {
        internal let id: _EffectID?
        internal let queue: (any EffectQueue)?
        internal let run: @Sendable (EffectContext) async throws -> Action?

        internal init(
            id: _EffectID? = nil,
            queue: (any EffectQueue)? = nil,
            run: @escaping @Sendable (EffectContext) async throws -> Action?
        )
        {
            self.id = id
            self.queue = queue
            self.run = run
        }

        internal func map<Action2>(action f: @escaping @Sendable (Action) -> Action2) -> Effect<Action2>.Single
        {
            .init(id: id, queue: queue) { context in
                (try await run(context)).map(f)
            }
        }

        internal func map<ID>(id f: @escaping ((any EffectID)?) -> ID?) -> Effect.Single
            where ID: EffectID
        {
            .init(id: f(id?.value).map(_EffectID.init), queue: queue, run: run)
        }

        internal func map(
            queue f: @escaping ((any EffectQueue)?) -> (any EffectQueue)?
        ) -> Effect.Single
        {
            .init(id: id, queue: f(queue), run: run)
        }
    }

    /// Wrapper of `AsyncSequence`.
    ///
    /// The wrapped existential is constrained to `SendableMetatype` (not `Sendable`)
    /// for the same reason as ``MealyMachine``: the produced `AsyncSequence` instance is not
    /// required to be `Sendable`, but its metatype must be so that the existential can appear in
    /// `@Sendable` closure signatures (here, the `sequence` factory and `Effect.map`'s open-existential
    /// helper) — it makes no claim about instance sendability.
    internal struct _Sequence
    {
        internal let id: _EffectID?
        internal let queue: (any EffectQueue)?
        internal let sequence: @Sendable (EffectContext) async throws
            -> (any AsyncSequence<Action, any Error> & SendableMetatype)?

        internal init(
            id: _EffectID? = nil,
            queue: (any EffectQueue)? = nil,
            sequence: @escaping @Sendable (EffectContext) async throws
                -> (any AsyncSequence<Action, any Error> & SendableMetatype)?
        )
        {
            self.id = id
            self.queue = queue
            self.sequence = sequence
        }

        internal func map<Action2>(action f: @escaping @Sendable (Action) -> Action2) -> Effect<Action2>._Sequence
        {
            // Open Existential
            @Sendable
            func _mapAsyncSequence(
                _ seq: some AsyncSequence<Action, any Error> & SendableMetatype
            ) -> any AsyncSequence<Action2, any Error> & SendableMetatype {
                seq.map(f)
            }

            return .init(id: id, queue: queue, sequence: { context in
                guard let seq = try await sequence(context) else { return nil }
                return _mapAsyncSequence(seq)
            })
        }

        internal func map<ID>(id f: @escaping ((any EffectID)?) -> ID?) -> Effect._Sequence
            where ID: EffectID
        {
            .init(id: f(id?.value).map(_EffectID.init), queue: queue, sequence: sequence)
        }

        internal func map(
            queue f: @escaping ((any EffectQueue)?) -> (any EffectQueue)?
        ) -> Effect._Sequence
        {
            .init(id: id, queue: f(queue), sequence: sequence)
        }
    }
}
