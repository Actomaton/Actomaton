import Combine
import Actomaton

// MARK: - toEffect

extension Publisher
{
    public func toEffect() -> Effect<Output>
    {
        Effect(sequence: self.toAsyncThrowingStream())
    }

    public func toEffect<ID>(
        id: ID? = nil
    ) -> Effect<Output>
        where ID: EffectIDProtocol
    {
        Effect(id: id, sequence: self.toAsyncThrowingStream())
    }

    public func toEffect<Queue>(
        queue: Queue? = nil
    ) -> Effect<Output>
        where Queue: EffectQueueProtocol
    {
        Effect(queue: queue, sequence: self.toAsyncThrowingStream())
    }

    public func toEffect<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil
    ) -> Effect<Output>
        where ID: EffectIDProtocol, Queue: EffectQueueProtocol
    {
        Effect(id: id, queue: queue, sequence: self.toAsyncThrowingStream())
    }
}

// MARK: - toResultEffect

extension Publisher
{
    public func toResultEffect() -> Effect<Result<Output, Failure>>
    {
        self.map(Result.success)
            .catch { Just(.failure($0)) }
            .toEffect()
    }

    public func toResultEffect<ID>(
        id: ID? = nil
    ) -> Effect<Result<Output, Failure>>
        where ID: EffectIDProtocol
    {
        self.map(Result.success)
            .catch { Just(.failure($0)) }
            .toEffect(id: id)
    }

    public func toResultEffect<Queue>(
        queue: Queue? = nil
    ) -> Effect<Result<Output, Failure>>
        where Queue: EffectQueueProtocol
    {
        self.map(Result.success)
            .catch { Just(.failure($0)) }
            .toEffect(queue: queue)
    }
    public func toResultEffect<ID, Queue>(
        id: ID? = nil,
        queue: Queue? = nil
    ) -> Effect<Result<Output, Failure>>
        where ID: EffectIDProtocol, Queue: EffectQueueProtocol
    {
        self.map(Result.success)
            .catch { Just(.failure($0)) }
            .toEffect(id: id, queue: queue)
    }
}

// MARK: - toAsyncStream

extension Publisher
{
    /// `Publisher` to `AsyncThrowingStream`.
    public func toAsyncThrowingStream() -> AsyncThrowingStream<Output, Swift.Error>
    {
        AsyncThrowingStream<Output, Swift.Error>(Output.self) { continuation in
            let cancellable = self
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            continuation.finish()
                        case let .failure(error):
                            continuation.yield(with: .failure(error))
                        }
                    },
                    receiveValue: { output in
                        continuation.yield(output)
                    }
                )

            continuation.onTermination = { @Sendable _ in
                withExtendedLifetime(cancellable, {})
            }
        }
    }

    /// `Publisher` to `AsyncStream`.
    public func toAsyncStream() -> AsyncStream<Output> where Failure == Never
    {
        AsyncStream(Output.self) { continuation in
            let cancellable = self
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            continuation.finish()
                        }
                    },
                    receiveValue: { output in
                        continuation.yield(output)
                    }
                )

            continuation.onTermination = { @Sendable _ in
                withExtendedLifetime(cancellable, {})
            }
        }
    }
}
