import Foundation

/// Only the unbound idea branch calls this. A confirmed name conditions a new
/// generation; it never renames a returned card or raises its confidence.
enum RecipeIdeaPrompt {
    static func build(_ text: String, confirmedDish: String?) -> String {
        let original = RecipePrompt.prompt(text)
        guard let name = confirmedDish?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return original }
        return original + "\nThe cook confirmed the dish: \(name). Generate that dish using the original idea above. Do not substitute a different dish. If you cannot make it, explain the uncertainty rather than inventing another dish."
    }
}
