@testable import ActomatonTesting
import XCTest

final class AsyncSignalTests: XCTestCase
{
    /// A signal raised while no one is waiting is banked, so a later `wait()`
    /// returns immediately.
    func test_signalBeforeWait_returnsTrueWithoutSuspending() async
    {
        let signal = AsyncSignal()

        signal.signal()

        let result = await signal.wait()
        XCTAssertTrue(result)
    }

    func test_waitThenSignal_returnsTrue() async
    {
        let signal = AsyncSignal()

        let waiter = Task {
            await signal.wait()
        }

        // Let the waiter suspend before signalling.
        await Task.yield()
        signal.signal()

        let result = await waiter.value
        XCTAssertTrue(result)
    }

    /// The regression this type exists for: cancelling one waiter must resume
    /// only that waiter (returning `false`) and must NOT invalidate the signal
    /// for later waits.
    func test_cancelWaiter_returnsFalse_andSignalStillWorksAfterwards() async
    {
        let signal = AsyncSignal()

        let cancelledWaiter = Task {
            await signal.wait()
        }

        // Let the waiter suspend, then cancel it.
        await Task.yield()
        cancelledWaiter.cancel()

        let cancelledResult = await cancelledWaiter.value
        XCTAssertFalse(cancelledResult, "Cancelled waiter should return false.")

        // A subsequent wait/signal pair must still work.
        let secondWaiter = Task {
            await signal.wait()
        }

        await Task.yield()
        signal.signal()

        let secondResult = await secondWaiter.value
        XCTAssertTrue(secondResult, "Signal must survive a cancelled waiter.")
    }

    func test_twoPendingSignals_twoSequentialWaits_bothReturnTrue() async
    {
        let signal = AsyncSignal()

        signal.signal()
        signal.signal()

        let first = await signal.wait()
        let second = await signal.wait()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
    }

    /// Cancellation that lands before the waiter registers must not hang.
    func test_waitOnAlreadyCancelledTask_returnsFalse() async
    {
        let signal = AsyncSignal()

        let waiter = Task {
            // Busy-wait until this task is marked cancelled, then wait.
            while !Task.isCancelled {
                await Task.yield()
            }
            return await signal.wait()
        }

        waiter.cancel()

        let result = await waiter.value
        XCTAssertFalse(result)
    }
}
