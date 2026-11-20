import Foundation

/// Whether the "Suggest a new recipe" entry in Add recipe can start generation now.
/// Presentation only: computing this never calls the model, a remote service or a
/// demo fallback, and never fabricates context. The entry stays visible in every
/// state and explains why generation cannot start. RecipeDiscoverySession re-checks
/// every gate against live data before any real generation, so a stale ready answer
/// here can never produce a call on its own.
enum RecipeDiscoveryReadiness: Equatable {
    case ready
    case privateMode
    case modelUnavailable(reason: String)
    case nonOnDeviceBackend
    case emptyLibrary

    /// Gate order mirrors RecipeDiscoverySession.requestStreaming: Private mode and
    /// model/backend availability block before the saved-recipe minimum, so the
    /// first blocking reason is the one the entry explains.
    init(privateMode: Bool, onDeviceBackend: Bool, modelAvailable: Bool, modelUnavailableReason: String, savedRecipes: Int) {
        if privateMode { self = .privateMode }
        else if !onDeviceBackend { self = .nonOnDeviceBackend }
        else if !modelAvailable { self = .modelUnavailable(reason: modelUnavailableReason) }
        else if savedRecipes < 1 { self = .emptyLibrary }
        else { self = .ready }
    }

    var canGenerate: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Honest reason shown under the always-visible entry. The Private mode and
    /// empty-library copies match the messages RecipeDiscovery.context and
    /// RecipeDiscoverySession show for the same states, so the entry and the
    /// suggestions flow never disagree.
    var explanation: String? {
        switch self {
        case .ready:
            return nil
        case .privateMode:
            return "Private mode is on. Turn it off in Settings to use AI suggestions."
        case .modelUnavailable(let reason):
            return "Suggestions need on-device Apple Intelligence: \(reason). No suggestion can start yet."
        case .nonOnDeviceBackend:
            return "Suggestions need on-device Apple Intelligence, which is not the active backend. No suggestion can start yet."
        case .emptyLibrary:
            return "Save a recipe first so Ate can suggest something based on your tastes."
        }
    }
}
