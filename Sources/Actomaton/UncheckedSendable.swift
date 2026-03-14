import CasePaths

extension WritableKeyPath: @retroactive @unchecked Sendable {}
extension CasePath: @retroactive @unchecked Sendable {}

#if !DISABLE_COMBINE && canImport(Combine)
import Combine

extension Published.Publisher: @retroactive @unchecked Sendable {}

extension AsyncPublisher: @retroactive @unchecked Sendable {}
#endif
