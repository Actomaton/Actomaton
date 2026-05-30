import ActomatonEffect

// MARK: - SendResult helper

extension EffectManager
{
    /// Process the reducer output and wrap its emitted side-channel values in ``SendResult``.
    ///
    /// This convenience helper is for top-level `send` entry points. Recursive feedback paths
    /// should continue to call the primitive `emit`-threading overload so all downstream
    /// emissions flow into the original caller's single ``SendResult`` stream.
    package func processOutput(
        _ output: Output,
        priority: TaskPriority?,
        tracksFeedbacks: Bool
    ) -> SendResult<Output.Emission>
        where Output.Emission: Sendable
    {
        let (stream, continuation) = AsyncStream<Result<Output.Emission, any Error>>.makeStream()
        let emit: @Sendable (Result<Output.Emission, any Error>) -> Void = { continuation.yield($0) }

        let task = self.processOutput(
            output,
            priority: priority,
            tracksFeedbacks: tracksFeedbacks,
            emit: emit
        )

        // Stream-finishing supervisor.
        //
        // Effect errors are surfaced in-band as `.failure` elements by each effect task itself
        // (see `EffectQueueManager.makeTask`), so `task` only ever throws `CancellationError`
        // (on explicit `SendResult.cancel()`). The supervisor therefore just awaits the chain
        // and finishes the stream:
        //
        // - `task` completes (success or in-band failures already delivered) -> finish cleanly.
        // - `task` is cancelled via `SendResult.cancel()` -> propagate cancellation to `task`
        //   so the effect chain unwinds, then finish cleanly.
        // - Any unexpected non-cancellation error (defensive) -> deliver as a final `.failure`.
        let supervisor = Task<Void, Never>(priority: priority) { @concurrent in
            await withTaskCancellationHandler {
                do {
                    try await task?.value
                }
                catch is CancellationError {
                    // Cancellation finishes cleanly; it is not an in-band failure.
                }
                catch {
                    continuation.yield(.failure(error))
                }

                // Call `finish` regardless of successful / failure completions.
                continuation.finish()
            } onCancel: {
                task?.cancel()
            }
        }

        return SendResult(
            stream: stream,
            supervisor: supervisor
        )
    }
}
