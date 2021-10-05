/// Effect type to run `async`, `AsyncSequence`, or cancellation.
public struct Effect<Action>
{
    internal let kinds: [Kind]
}

// MARK: - Public Initializers

extension Effect
{
    /// Single-`async` side-effect.
    /// - Parameter id: Cancellation identifier.
    public init(id: EffectID? = nil, run: @escaping () async -> Action?)
    {
        self.init(kinds: [.single(Single(id: id, queue: nil, run: run))])
    }

    /// Single-`async` side-effect.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<Queue>(id: EffectID? = nil, queue: Queue? = nil, run: @escaping () async -> Action?)
        where Queue: EffectQueueProtocol
    {
        self.init(kinds: [.single(Single(id: id, queue: queue.map(AnyEffectQueue.init), run: run))])
    }

    /// `AsyncSequence` side-effect.
    /// - Parameter id: Cancellation identifier.
    public init<S>(id: EffectID? = nil, sequence: S)
        where S: AsyncSequence, S.Element == Action
    {
        self.init(kinds: [.sequence(_Sequence(id: id, queue: nil, sequence: sequence.typeErased))])
    }

    /// `AsyncSequence` side-effect.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public init<S, Queue>(id: EffectID? = nil, queue: Queue? = nil, sequence: S)
        where S: AsyncSequence, S.Element == Action, Queue: EffectQueueProtocol
    {
        self.init(kinds: [.sequence(_Sequence(id: id, queue: queue.map(AnyEffectQueue.init), sequence: sequence.typeErased))])
    }

    /// Single-`async` side-effect without returning next action.
    /// - Parameter id: Cancellation identifier.
    public static func fireAndForget(
        id: EffectID? = nil,
        run: @escaping () async -> ()
    ) -> Effect<Action>
    {
        self.init(id: id, run: {
            await run()
            return nil
        })
    }

    /// Single-`async` side-effect without returning next action.
    /// - Parameter id: Cancellation identifier.
    /// - Parameter queue: Effect management queue to discard or suspend existing or new tasks.
    public static func fireAndForget<Queue>(
        id: EffectID? = nil,
        queue: Queue? = nil,
        run: @escaping () async -> ()
    ) -> Effect<Action>
        where Queue: EffectQueueProtocol
    {
        self.init(id: id, queue: queue, run: {
            await run()
            return nil
        })
    }

    /// No `async` side-effect, only returning next action.
    public static func nextAction(_ action: Action) -> Effect<Action>
    {
        self.init(kinds: [.single(Single { action })])
    }

    /// Cancels running `async`s by specifying `ids`.
    public static func cancel(ids: @escaping (EffectID) -> Bool) -> Effect<Action>
    {
        Effect(kinds: [.cancel(ids)])
    }

    /// Cancels running `async`s by specifying `identifier`.
    public static func cancel(id: EffectID) -> Effect<Action>
    {
        Effect(kinds: [.cancel { $0 == id }])
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
    public func map<Action2>(_ f: @escaping (Action) -> Action2) -> Effect<Action2>
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(action: f))

            case let .sequence(sequence):
                return .sequence(sequence.map(action: f))

            case let .cancel(predicate):
                return .cancel(predicate)
            }
        })
    }

    /// Changes `EffectID`.
    public func map(id f: @escaping (EffectID?) -> EffectID?) -> Effect
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(single):
                return .single(single.map(id: f))

            case let .sequence(sequence):
                return .sequence(sequence.map(id: f))

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
    internal enum Kind
    {
        case single(Single)
        case sequence(_Sequence)
        case cancel((EffectID) -> Bool)

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
            case .cancel:
                return nil
            }
        }
    }

    /// Wrapper of `async`.
    internal struct Single
    {
        internal let id: EffectID?
        internal let queue: AnyEffectQueue?
        internal let run: () async -> Action?

        internal init(id: EffectID? = nil, queue: AnyEffectQueue? = nil, run: @escaping () async -> Action?)
        {
            self.id = id
            self.queue = queue
            self.run = run
        }

        internal func map<Action2>(action f: @escaping (Action) -> Action2) -> Effect<Action2>.Single
        {
            .init(id: id, queue: queue) {
                (await run()).map(f)
            }
        }

        internal func map(id f: @escaping (EffectID?) -> EffectID?) -> Effect.Single
        {
            .init(id: f(id), queue: queue, run: run)
        }

        internal func map(queue f: @escaping (AnyEffectQueue?) -> AnyEffectQueue?) -> Effect.Single
        {
            .init(id: id, queue: f(queue), run: run)
        }
    }

    /// Wrapper of `AsyncSequence`.
    internal struct _Sequence
    {
        internal let id: EffectID?
        internal let queue: AnyEffectQueue?
        internal let sequence: AnyAsyncSequence<Action>

        internal init(id: EffectID? = nil, queue: AnyEffectQueue? = nil, sequence: AnyAsyncSequence<Action>)
        {
            self.id = id
            self.queue = queue
            self.sequence = sequence
        }

        internal func map<Action2>(action f: @escaping (Action) -> Action2) -> Effect<Action2>._Sequence
        {
            .init(id: id, queue: queue, sequence: sequence.map(f).typeErased)
        }

        internal func map(id f: @escaping (EffectID?) -> EffectID?) -> Effect._Sequence
        {
            .init(id: f(id), queue: queue, sequence: sequence)
        }

        internal func map<Queue>(queue f: @escaping (EffectQueue?) -> Queue?) -> Effect._Sequence
            where Queue: EffectQueueProtocol
        {
            .init(id: id, queue: f(queue).map(AnyEffectQueue.init), sequence: sequence)
        }
    }
}
