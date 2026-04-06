/// A test task returned from ``TestMachine/send(_:assert:fileID:file:line:)``.
///
/// Use this value to wait for all effects triggered by the sent action to finish, or to cancel
/// them explicitly.
public struct TestMachineTask: Sendable
{
    private let task: Task<(), any Error>?
    private let timeout: Duration

    init(
        task: Task<(), any Error>?,
        timeout: Duration
    )
    {
        self.task = task
        self.timeout = timeout
    }

    /// Cancels the underlying task and waits for it to settle.
    public func cancel() async
    {
        self.task?.cancel()
        _ = await self.task?.result
    }

    /// Waits for the underlying task to finish, throwing ``TimeoutError`` if it does not finish in
    /// time.
    ///
    /// - Important:
    /// This method only waits for task completion and enforces its timeout using wall-clock time.
    /// It does not advance an injected test clock. If the effect is sleeping on a ``TestClock`` or
    /// another manually-driven clock, advance that clock separately before awaiting `finish()`.
    public func finish(timeout: Duration? = nil) async throws
    {
        let duration = timeout ?? self.timeout

        guard let rawValue = self.task else { return }

        let completion = _TaskCompletion()

        Task.detached {
            let result = await rawValue.result

            switch result {
            case .success:
                await completion.succeed()
            case let .failure(error):
                await completion.fail(error)
            }
        }

        try await _withTimeout(duration) {
            try await completion.wait()
        }
    }

    /// Whether the underlying task has been cancelled.
    public var isCancelled: Bool
    {
        self.task?.isCancelled ?? true
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

private actor _TaskCompletion
{
    private var result: Result<Void, any Error>?
    private var continuation: CheckedContinuation<Void, any Error>?

    func wait() async throws
    {
        if let result = self.result {
            return try result.get()
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let result = self.result {
                    continuation.resume(with: result)
                    return
                }

                precondition(self.continuation == nil, "Concurrent waits are not supported.")
                self.continuation = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWait()
            }
        }
    }

    func succeed()
    {
        self.resolve(.success(()))
    }

    func fail(_ error: any Error)
    {
        self.resolve(.failure(error))
    }

    private func resolve(
        _ result: Result<Void, any Error>
    )
    {
        guard self.result == nil else { return }

        self.result = result

        switch result {
        case .success:
            self.continuation?.resume()

        case let .failure(error):
            self.continuation?.resume(throwing: error)
        }

        self.continuation = nil
    }

    private func cancelWait()
    {
        self.continuation?.resume(throwing: CancellationError())
        self.continuation = nil
    }
}
