import Combine
import Actomaton

// MARK: - toEffect / toResultEffect

extension Publisher where Failure == Never
{
    public func toEffect(
        id: EffectID? = nil
    ) -> Effect<Output>
    {
        Effect(id: id, sequence: self.toAsyncStream())
    }
}

extension Publisher
{
    public func toResultEffect(
        id: EffectID? = nil
    ) -> Effect<Result<Output, Failure>>
    {
        self.map(Result.success)
            .catch { Just(.failure($0)) }
            .toEffect(id: id)
    }
}

// MARK: - toAsyncStream

extension Publisher
{
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
}
