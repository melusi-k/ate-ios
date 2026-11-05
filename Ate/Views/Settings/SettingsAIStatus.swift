import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Presentation only. Does not change backend selection or enable generation.
/// Read afresh when Settings appears/returns to foreground, not cached at app launch.
enum SettingsAIStatus: String, CaseIterable {
    case ready, unsupportedDevice, disabled, modelNotReady, needsOSUpdate, unavailable

    static var current: Self {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.deviceNotEligible): return .unsupportedDevice
            case .unavailable(.appleIntelligenceNotEnabled): return .disabled
            case .unavailable(.modelNotReady): return .modelNotReady
            case .unavailable: return .unavailable
            }
        }
        #endif
        return .needsOSUpdate
    }

    var title: String {
        switch self {
        case .ready: "Apple Intelligence ready"
        case .unsupportedDevice: "Apple Intelligence isn't supported on this iPhone"
        case .disabled: "Apple Intelligence is turned off"
        case .modelNotReady: "Apple Intelligence isn't ready yet"
        case .needsOSUpdate: "On-device AI needs iOS 26 or later"
        case .unavailable: "Apple Intelligence is unavailable"
        }
    }

    var guidance: String {
        switch self {
        case .ready: "New AI recipes use Apple's on-device model."
        case .unsupportedDevice: "Updating iOS alone won't add support to an incompatible device. Demo recipes are available instead and are marked Demo."
        case .disabled: "Check Apple Intelligence in the iPhone Settings app. Until it's available, generated recipes use the demo model and are marked Demo."
        case .modelNotReady: "Check Apple Intelligence in the iPhone Settings app while the model gets ready. For now, generated recipes use the demo model and are marked Demo."
        case .needsOSUpdate: "Check Software Update in the iPhone Settings app. A compatible Apple Intelligence device is also required. For now, generated recipes are marked Demo."
        case .unavailable: "Check Apple Intelligence availability in the iPhone Settings app. For now, generated recipes use the demo model and are marked Demo."
        }
    }
}
