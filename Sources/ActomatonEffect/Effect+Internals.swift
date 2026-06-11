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
