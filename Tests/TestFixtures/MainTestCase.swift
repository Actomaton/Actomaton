import Foundation
import XCTest

#if canImport(ConcurrencyExtras)

import ConcurrencyExtras

/// This XCTestCase subclass ensures that all async code is executed in the same order that is enqueued.
/// [More information](https://www.pointfree.co/blog/posts/110-reliably-testing-async-code-in-swift)
open class MainTestCase: XCTestCase {
    open override func invokeTest() {
        withMainSerialExecutor {
            super.invokeTest()
        }
    }
}

#else

public typealias MainTestCase = XCTestCase

#endif
