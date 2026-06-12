import Synchronization

/// Counting async signal used by ``TestActomaton`` to wake `receive` waiters.
///
/// Unlike `AsyncStream`, cancelling a task suspended in ``wait()`` resumes only
/// that waiter (returning `false`) and does NOT invalidate the signal for later
/// waiters. Signals raised while no one is waiting are counted and wake the
/// next waiter immediately.
final class AsyncSignal: Sendable
{
    private struct State
    {
        var pendingSignals: Int = 0
        var waiters: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
        var cancelledIDs: Set<Int> = []
        var nextID: Int = 0
    }

    private let state = Mutex<State>(State())

    /// Wakes the oldest waiter, or banks the signal if no one is waiting.
    func signal()
    {
        let continuation: CheckedContinuation<Bool, Never>? = self.state.withLock { state in
            if state.waiters.isEmpty {
                state.pendingSignals += 1
                return nil
            }
            return state.waiters.removeFirst().continuation
        }
        continuation?.resume(returning: true)
    }

    /// Waits for the next signal. Returns `false` if the waiting task was cancelled.
    func wait() async -> Bool
    {
        let id: Int? = self.state.withLock { state in
            if state.pendingSignals > 0 {
                state.pendingSignals -= 1
                return nil
            }
            let id = state.nextID
            state.nextID += 1
            return id
        }

        // Fast path: a banked signal was consumed without suspending.
        guard let id else { return true }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let isCancelledBeforeRegistration: Bool = self.state.withLock { state in
                    if state.cancelledIDs.remove(id) != nil {
                        return true
                    }
                    state.waiters.append((id: id, continuation: continuation))
                    return false
                }
                if isCancelledBeforeRegistration {
                    continuation.resume(returning: false)
                }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Bool, Never>? = self.state.withLock { state in
                if let index = state.waiters.firstIndex(where: { $0.id == id }) {
                    return state.waiters.remove(at: index).continuation
                }
                // `onCancel` may fire before the waiter is registered; mark the ID
                // so registration resumes immediately instead of suspending forever.
                state.cancelledIDs.insert(id)
                return nil
            }
            continuation?.resume(returning: false)
        }
    }
}
