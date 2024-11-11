#if !DISABLE_COMBINE && canImport(Combine)
import Combine

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.

#if swift(>=6.0)

extension PassthroughSubject: @retroactive @unchecked Sendable {}
extension Published.Publisher: @retroactive @unchecked Sendable {}
extension AnyPublisher: @retroactive @unchecked Sendable {}
extension AnyCancellable: @retroactive @unchecked Sendable {}

#else

extension PassthroughSubject: @unchecked Sendable {}
extension Published.Publisher: @unchecked Sendable {}
extension AnyPublisher: @unchecked Sendable {}
extension AnyCancellable: @unchecked Sendable {}

#endif
#endif
