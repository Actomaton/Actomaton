#if !DISABLE_COMBINE && canImport(Combine)
import Combine

extension Published.Publisher: @retroactive @unchecked Sendable {}

#endif
