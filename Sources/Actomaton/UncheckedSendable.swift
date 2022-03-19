import CasePaths

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.

extension WritableKeyPath: @unchecked Sendable {}

extension CasePath: @unchecked Sendable {}
