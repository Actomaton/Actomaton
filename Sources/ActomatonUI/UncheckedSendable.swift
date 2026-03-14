#if !DISABLE_COMBINE && canImport(Combine)
import Combine

extension PassthroughSubject: @retroactive @unchecked Sendable {}
extension AnyPublisher: @retroactive @unchecked Sendable {}
extension AnyCancellable: @retroactive @unchecked Sendable {}

#endif
