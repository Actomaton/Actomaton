/// Effect type to run `async`, `AsyncSequence`, or cancellation.
public struct Effect<Action>
{
    internal let kinds: [Kind]
}

/// Effect identifier for manual cancellation via `Effect.cancel`
/// or automatic cancellation by sending another effect with same identifier.
public typealias EffectID = AnyHashable

public protocol EffectIDProtocol: Hashable {}

// MARK: - Public Initializers

extension Effect
{
    /// Single-`async` side-effect.
    /// - Parameter id: Cancellation identifier.
    public init(id: EffectID? = nil, run: @escaping () async -> Action?)
    {
        self.init(kinds: [.single(Single(id: id, run: run))])
    }

    /// `AsyncSequence` side-effect.
    /// - Parameter id: Cancellation identifier.
    public init<S>(id: EffectID? = nil, sequence: S)
        where S: AsyncSequence, S.Element == Action
    {
        self.init(kinds: [.sequence(_Sequence(id: id, sequence: sequence.typeErased))])
    }

    /// Single-`async` side-effect without returning next action.
    public static func fireAndForget(id: EffectID? = nil, run: @escaping () async -> ()) -> Effect<Action>
    {
        self.init(kinds: [.single(Single(id: id, run: { 
            await run()
            return nil
        }))])
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
}

// MARK: - Functor

extension Effect
{
    /// Changes `Action`.
    public func map<Action2>(_ f: @escaping (Action) -> Action2) -> Effect<Action2>
    {
        .init(kinds: self.kinds.map { kind in
            switch kind {
            case let .single(runner):
                return .single(runner.map(action: f))

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
            case let .single(runner):
                return .single(runner.map(id: f))

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
        self.kinds.compactMap { $0.runner }
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

        internal var runner: Single?
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
    }

    /// Wrapper of `async`.
    internal struct Single
    {
        internal let id: EffectID?
        internal let run: () async -> Action?

        internal init(id: EffectID? = nil, run: @escaping () async -> Action?)
        {
            self.id = id
            self.run = run
        }

        internal func map<Action2>(action f: @escaping (Action) -> Action2) -> Effect<Action2>.Single
        {
            .init(id: id) {
                (await run()).map(f)
            }
        }

        internal func map(id f: @escaping (EffectID?) -> EffectID?) -> Effect.Single
        {
            .init(id: f(id), run: run)
        }
    }

    /// Wrapper of `AsyncSequence`.
    internal struct _Sequence
    {
        internal let id: EffectID?
        internal let sequence: AnyAsyncSequence<Action>

        internal init(id: EffectID? = nil, sequence: AnyAsyncSequence<Action>)
        {
            self.id = id
            self.sequence = sequence
        }

        internal func map<Action2>(action f: @escaping (Action) -> Action2) -> Effect<Action2>._Sequence
        {
            .init(id: id, sequence: sequence.map(f).typeErased)
        }

        internal func map(id f: @escaping (EffectID?) -> EffectID?) -> Effect._Sequence
        {
            .init(id: f(id), sequence: sequence)
        }
    }
}
