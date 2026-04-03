import Actomaton
import Clocks
import Foundation
import XCTest

#if canImport(ConcurrencyExtras)

import ConcurrencyExtras

#endif

/// This XCTestCase subclass ensures that all async code is executed in the same order that is enqueued.
/// [More information](https://www.pointfree.co/blog/posts/110-reliably-testing-async-code-in-swift)
open class MainTestCase: XCTestCase
{
#if TEST_CLOCK
    public let clock = TestClock<Duration>()
#else
    public let clock = ContinuousClock()
#endif

    public var effectContext: EffectContext
    {
        EffectContext(clock: self.clock)
    }

    open override func invokeTest()
    {
#if canImport(ConcurrencyExtras)
        withMainSerialExecutor {
            super.invokeTest()
        }
#else
        super.invokeTest()
#endif
    }
}
