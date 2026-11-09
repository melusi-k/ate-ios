import Foundation

/// Pure candidate policy. It does not erase, migrate or stamp any user bytes. The real
/// AppStore must execute and verify the complete local reset barrier before adopting an
/// advanced generation, then persist owner+generation before allowing captured writes.
enum AccountGenerationPolicy {
    struct Receipt: Codable, Equatable {
        let ownerID: String
        let generation: Int64
    }
    enum Decision: Equatable {
        case mergeCurrentGeneration
        case adoptForVerifiedEmptyLocalState
        case legacyLocalStateNeedsReconciliation
        case ownerChangeNeedsReconciliation
        case remoteResetNeedsLocalErase
        case refuseInvalidOrRegressedGeneration
    }
    static func decide(receipt: Receipt?, ownerID: String, remoteGeneration: Int64,
                       allPersonalLocalStateVerifiedEmpty: Bool) -> Decision {
        guard !ownerID.isEmpty, remoteGeneration >= 0 else {
            return .refuseInvalidOrRegressedGeneration
        }
        guard let receipt else {
            return allPersonalLocalStateVerifiedEmpty
                ? .adoptForVerifiedEmptyLocalState : .legacyLocalStateNeedsReconciliation
        }
        guard receipt.generation >= 0, !receipt.ownerID.isEmpty else {
            return .refuseInvalidOrRegressedGeneration
        }
        guard receipt.ownerID == ownerID else { return .ownerChangeNeedsReconciliation }
        if remoteGeneration < receipt.generation { return .refuseInvalidOrRegressedGeneration }
        if remoteGeneration > receipt.generation { return .remoteResetNeedsLocalErase }
        return .mergeCurrentGeneration
    }
}
