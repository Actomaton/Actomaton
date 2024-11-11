#if !DISABLE_COMBINE && canImport(Combine)
import Combine

// TODO: Remove `@unchecked Sendable` when `Sendable` is supported by each module.

#if swift(>=6.0)

extension Published.Publisher: @retroactive @unchecked Sendable {}

#else

extension Published.Publisher: @unchecked Sendable {}

#endif
#endif
