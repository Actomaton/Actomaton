import Combine

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.

extension PassthroughSubject: @unchecked Sendable {}

extension Published.Publisher: @unchecked Sendable {}
