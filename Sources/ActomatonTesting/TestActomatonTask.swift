import Actomaton

/// A test task returned from ``TestActomaton/send(_:assert:timeout:fileID:file:line:)``.
///
/// Use this value to wait for all effects triggered by the sent action to finish, or to cancel
/// them explicitly.
public struct TestActomatonTask<Emission>: Sendable
    where Emission: Sendable
{
    /// Result returned by `EffectManager.processOutput`, preserving the same lifecycle semantics
    /// as production `send` entry points.
    ///
    /// `TestActomaton` does not expose emitted values as assertions yet, but owning the
    /// `SendResult` keeps completion and cancellation behavior aligned with `Actomaton.send`.
    private let sendResult: SendResult<Emission>?
    private let timeout: Duration

    init(
        sendResult: SendResult<Emission>?,
        timeout: Duration
    )
    {
        self.sendResult = sendResult
        self.timeout = timeout
    }

    /// Cancels the underlying send result and waits for it to settle.
    public func cancel() async
    {
        self.sendResult?.cancel()
        await self.sendResult?.completion()
    }

    /// Waits for the underlying send result to finish, throwing ``TimeoutError`` if it does not
    /// finish in time.
    ///
    /// - Important:
    /// This method only waits for send-result completion and enforces its timeout using wall-clock
    /// time. It does not advance an injected test clock. If the effect is sleeping on a
    /// ``TestClock`` or another manually-driven clock, advance that clock separately before
    /// awaiting `finish()`.
    public func finish(timeout: Duration? = nil) async throws
    {
        let duration = timeout ?? self.timeout

        guard let sendResult = self.sendResult else { return }

        try await _withTimeout(duration) {
            await sendResult.completion()
        }
    }

    /// Whether the underlying send result has been cancelled.
    public var isCancelled: Bool
    {
        self.sendResult?.isCancelled ?? true
    }
}

// MARK: - Private

private func _withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T
{
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)

        group.addTask {
            try await Task.sleep(for: duration)
            throw TestTimeoutError(duration: duration)
        }

        do {
            guard let result = try await group.next() else {
                throw TestTimeoutError(duration: duration)
            }

            group.cancelAll()
            return result
        }
        catch {
            group.cancelAll()
            throw error
        }
    }
}
