/// Effect type to run `async`, `AsyncSequence`, or cancellation.
public struct Effect<Action>: Sendable where Action: Sendable
{
    package let kinds: [Kind]

    package init(kinds: [Kind])
    {
        self.kinds = kinds
    }
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

    /// Single-`async` side-effect without `EffectContext`.
    public init(run: @escaping @Sendable () async throws -> Action?)
    {
        self.init(run: { _ in
            try await run()
        })
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public init<ID>(
        id: ID? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    )
        where ID: EffectIDProtocol
    {
        self.init(kinds: [.single(Single(id: id.map(EffectID.init), queue: nil, run: run))])
    }

    /// Single-`async` side-effect without `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public init<ID>(id: ID? = nil, run: @escaping @Sendable () async throws -> Action?)
        where ID: EffectIDProtocol
    {
        self.init(id: id, run: { _ in
            try await run()
        })
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<Queue>(
        queue: Queue? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    ) where Queue: EffectQueueProtocol
    {
        self.init(kinds: [.single(Single(id: nil, queue: queue.map(AnyEffectQueue.init), run: run))])
    }

    /// Single-`async` side-effect without `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<Queue>(queue: Queue? = nil, run: @escaping @Sendable () async throws -> Action?)
        where Queue: EffectQueueProtocol
    {
        self.init(queue: queue, run: { _ in
            try await run()
        })
    }

    /// Single-`async` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> Action?
    ) where ID: EffectIDProtocol, Queue: EffectQueueProtocol
    {
        self.init(kinds: [.single(Single(id: id.map(EffectID.init), queue: queue.map(AnyEffectQueue.init), run: run))])
    }

    /// Single-`async` side-effect without `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<ID, Queue>(id: ID? = nil, queue: Queue? = nil, run: @escaping @Sendable () async throws -> Action?)
        where ID: EffectIDProtocol, Queue: EffectQueueProtocol
    {
        self.init(id: id, queue: queue, run: { _ in
            try await run()
        })
    }

    // MARK: - AsyncSequence

    /// `AsyncSequence` side-effect with `EffectContext`.
    public init<S, E: Error>(
        sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) where S: AsyncSequence<Action, E> & Sendable
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

    /// `AsyncSequence` side-effect without `EffectContext`.
    public init<S, E: Error>(sequence: @escaping @Sendable () async throws -> S?)
        where S: AsyncSequence<Action, E> & Sendable
    {
        self.init(sequence: { _ in
            try await sequence()
        })
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public init<ID, S, E: Error>(
        id: ID? = nil,
        sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) where ID: EffectIDProtocol, S: AsyncSequence<Action, E> & Sendable
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: id.map(EffectID.init),
                    queue: nil,
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect without `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public init<ID, S, E: Error>(id: ID? = nil, sequence: @escaping @Sendable () async throws -> S?)
        where ID: EffectIDProtocol, S: AsyncSequence<Action, E> & Sendable
    {
        self.init(id: id, sequence: { _ in
            try await sequence()
        })
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<S, E: Error, Queue>(
        queue: Queue? = nil,
        sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) where S: AsyncSequence<Action, E> & Sendable, Queue: EffectQueueProtocol
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: nil,
                    queue: queue.map(AnyEffectQueue.init),
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect without `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<S, E: Error, Queue>(queue: Queue? = nil, sequence: @escaping @Sendable () async throws -> S?)
        where S: AsyncSequence<Action, E> & Sendable, Queue: EffectQueueProtocol
    {
        self.init(queue: queue, sequence: { _ in
            try await sequence()
        })
    }

    /// `AsyncSequence` side-effect with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<ID, S, E: Error, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        sequence: @escaping @Sendable (EffectContext) async throws -> S?
    ) where ID: EffectIDProtocol, S: AsyncSequence<Action, E> & Sendable, Queue: EffectQueueProtocol
    {
        self.init(
            kinds: [.sequence(
                _Sequence(
                    id: id.map(EffectID.init),
                    queue: queue.map(AnyEffectQueue.init),
                    sequence: { context in try await sequence(context)?.eraseToAnyError() }
                )
            )]
        )
    }

    /// `AsyncSequence` side-effect without `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<ID, S, E: Error, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        sequence: @escaping @Sendable () async throws -> S?
    ) where ID: EffectIDProtocol, S: AsyncSequence<Action, E> & Sendable, Queue: EffectQueueProtocol
    {
        self.init(id: id, queue: queue, sequence: { _ in
            try await sequence()
        })
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

    /// Single-`async` side-effect without returning next action, without `EffectContext`.
    public static func fireAndForget(run: @escaping @Sendable () async throws -> ()) -> Effect<Action>
    {
        self.fireAndForget(run: { _ in
            try await run()
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public static func fireAndForget<ID>(
        id: ID? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action>
        where ID: EffectIDProtocol
    {
        self.init(id: id, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, without `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    public static func fireAndForget<ID>(
        id: ID? = nil,
        run: @escaping @Sendable () async throws -> ()
    ) -> Effect<Action>
        where ID: EffectIDProtocol
    {
        self.fireAndForget(id: id, run: { _ in
            try await run()
        })
    }

    /// Single-`async` side-effect without returning next action, with `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<Queue>(
        queue: Queue? = nil,
        run: @escaping @Sendable (EffectContext) async throws -> ()
    ) -> Effect<Action>
        where Queue: EffectQueueProtocol
    {
        self.init(queue: queue, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, without `EffectContext`.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<Queue>(
        queue: Queue? = nil,
        run: @escaping @Sendable () async throws -> ()
    ) -> Effect<Action>
        where Queue: EffectQueueProtocol
    {
        self.fireAndForget(queue: queue, run: { _ in
            try await run()
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
        where ID: EffectIDProtocol, Queue: EffectQueueProtocol
    {
        self.init(id: id, queue: queue, run: { context in
            try await run(context)
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action, without `EffectContext`.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil,
        run: @escaping @Sendable () async throws -> ()
    ) -> Effect<Action>
        where ID: EffectIDProtocol, Queue: EffectQueueProtocol
    {
        self.fireAndForget(id: id, queue: queue, run: { _ in
            try await run()
        })
    }

    // MARK: - nextAction

    /// No `async` side-effect, only returning next action.
    public static func nextAction(_ action: Action) -> Effect<Action>
        where Action: Sendable
    {
        self.init(kinds: [.next(action)])
    }

    // MARK: - cancel

    /// Cancels running `async`s by specifying `ids`.
    public static func cancel(ids: @escaping @Sendable (EffectID) -> Bool) -> Effect<Action>
    {
        Effect(kinds: [.cancel(ids)])
    }

    /// Cancels running `async`s by specifying `identifier`.
    public static func cancel<ID>(id: ID) -> Effect<Action>
        where ID: EffectIDProtocol
    {
        Effect(kinds: [.cancel { $0 == EffectID(id) }])
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
            }
        })
    }

    /// Changes `EffectID`.
    public func map<ID>(id f: @escaping (EffectID?) -> ID?) -> Effect
        where ID: EffectIDProtocol
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
            }
        })
    }

    /// Changes `EffectQueue`.
    public func map<Queue>(queue f: @escaping (EffectQueue?) -> Queue?) -> Effect
        where Queue: EffectQueueProtocol
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(queue: { f($0?.queue) }))

            case let .sequence(sequence):
                return .sequence(sequence.map(queue: { f($0?.queue) }))

            case .next:
                return kind

            case let .cancel(predicate):
                return .cancel(predicate)
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

    internal var cancels: [(EffectID) -> Bool]
    {
        self.kinds.compactMap { $0.cancel }
    }
}

extension Effect
{
    package enum Kind: Sendable
    {
        /// Single async func effect.
        case single(Single)

        /// AsyncSequence effect.
        case sequence(_Sequence)

        /// No async func effect, only returning next action only.
        case next(Action)

        /// Cancellation effect with filtering `EffectID`s by a predicate.
        case cancel(@Sendable (EffectID) -> Bool)

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

        internal var cancel: ((EffectID) -> Bool)?
        {
            guard case let .cancel(value) = self else { return nil }
            return value
        }

        internal var id: EffectID?
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
            }
        }

        internal var queue: AnyEffectQueue?
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
            }
        }
    }

    /// Wrapper of `async`.
    package struct Single: Sendable
    {
        internal let id: EffectID?
        internal let queue: AnyEffectQueue?
        internal let run: @Sendable (EffectContext) async throws -> Action?

        internal init(
            id: EffectID? = nil,
            queue: AnyEffectQueue? = nil,
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

        internal func map<ID>(id f: @escaping (EffectID?) -> ID?) -> Effect.Single
            where ID: EffectIDProtocol
        {
            .init(id: f(id).map(EffectID.init), queue: queue, run: run)
        }

        internal func map<Queue>(queue f: @escaping (AnyEffectQueue?) -> Queue?) -> Effect.Single
            where Queue: EffectQueueProtocol
        {
            .init(id: id, queue: f(queue).map(AnyEffectQueue.init), run: run)
        }
    }

    /// Wrapper of `AsyncSequence`.
    package struct _Sequence: Sendable
    {
        internal let id: EffectID?
        internal let queue: AnyEffectQueue?
        internal let sequence: @Sendable (EffectContext) async throws
            -> (any AsyncSequence<Action, any Error> & Sendable)?

        internal init(
            id: EffectID? = nil,
            queue: AnyEffectQueue? = nil,
            sequence: @escaping @Sendable (EffectContext) async throws
                -> (any AsyncSequence<Action, any Error> & Sendable)?
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
                _ seq: some AsyncSequence<Action, any Error> & Sendable
            ) -> any AsyncSequence<Action2, any Error> & Sendable {
                seq.map(f)
            }

            return .init(id: id, queue: queue, sequence: { context in
                guard let seq = try await sequence(context) else { return nil }
                return _mapAsyncSequence(seq)
            })
        }

        internal func map<ID>(id f: @escaping (EffectID?) -> ID?) -> Effect._Sequence
            where ID: EffectIDProtocol
        {
            .init(id: f(id).map(EffectID.init), queue: queue, sequence: sequence)
        }

        internal func map<Queue>(queue f: @escaping (AnyEffectQueue?) -> Queue?) -> Effect._Sequence
            where Queue: EffectQueueProtocol
        {
            .init(id: id, queue: f(queue).map(AnyEffectQueue.init), sequence: sequence)
        }
    }
}
