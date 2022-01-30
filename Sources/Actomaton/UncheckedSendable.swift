import CasePaths

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.

extension AsyncMapSequence: @unchecked Sendable {}
extension AsyncStream: @unchecked Sendable {}
extension AsyncThrowingStream: @unchecked Sendable {}

extension WritableKeyPath: @unchecked Sendable {}

extension CasePath: @unchecked Sendable {}
