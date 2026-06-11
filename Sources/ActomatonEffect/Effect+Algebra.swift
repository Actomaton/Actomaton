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
