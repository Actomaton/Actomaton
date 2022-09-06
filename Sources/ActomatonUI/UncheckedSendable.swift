#if os(WASI)
import OpenCombineShim
#else
import Combine
#endif

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.

extension PassthroughSubject: @unchecked Sendable {}

extension Published.Publisher: @unchecked Sendable {}

extension AnyPublisher: @unchecked Sendable {}

extension AnyCancellable: @unchecked Sendable {}
