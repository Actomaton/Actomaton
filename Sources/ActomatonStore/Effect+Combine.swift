import Combine
import Actomaton

// MARK: - toEffect / toResultEffect

extension Publisher where Failure == Never
{
    public func toEffect(
        id: EffectID? = nil
    ) -> Effect<Output>
    {
        Effect(id: id, sequence: self.toAsync())
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

// MARK: - Private

extension Publisher
{
    /// `Publisher` to `AsyncStream`.
    private func toAsync() -> AsyncStream<Output> where Failure == Never
    {
        AsyncStream(Output.self) { continuation in
            var subscriptions = [AnyCancellable]()

            self
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            continuation.finish()
                        case let .failure(error):
                            continuation.yield(with: .failure(error))
                        }
                    },
                    receiveValue: {
                        output in continuation.yield(output)
                    }
                )
                .store(in: &subscriptions)

            let subs = subscriptions

            continuation.onTermination = { @Sendable _ in
                _ = subs
            }
        }
    }
}
