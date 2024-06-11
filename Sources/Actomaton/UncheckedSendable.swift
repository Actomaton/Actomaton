import CasePaths

#if swift(>=6.0)

extension WritableKeyPath: @retroactive @unchecked Sendable {}
extension CasePath: @retroactive @unchecked Sendable {}

#if canImport(Combine)
import Combine
extension Published.Publisher: @retroactive @unchecked Sendable {}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension AsyncPublisher: @retroactive @unchecked Sendable {}
#endif

#else

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.
extension WritableKeyPath: @unchecked Sendable {}
extension CasePath: @unchecked Sendable {}

#endif
