import Foundation

/// A weak visual guess cannot establish cuisine or descriptive metadata. Keep the
/// proposed recipe and existing confidence/confirmation flow, but omit those claims.
enum PhotoDraftHonesty {
    static let omittedMetadataNote = "Cuisine and tags were left out because this photo identification is uncertain."
    static func apply(_ original: RecipeCard) -> RecipeCard {
        guard original.source == .photoGuess,
              let confidence = original.aiConfidence,
              !confidence.isFinite || confidence < RecipeQuality.threshold else { return original }
        var card = original
        let omitted = card.cuisine?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || !card.tags.isEmpty
        card.cuisine = nil
        card.tags = []
        if omitted && !(card.aiNote ?? "").contains(omittedMetadataNote) {
            card.aiNote = [card.aiNote, omittedMetadataNote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return card
    }
}
