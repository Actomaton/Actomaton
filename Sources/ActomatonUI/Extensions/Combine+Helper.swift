import Combine

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
