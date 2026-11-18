import Foundation

/// Narrow honesty rule for recognized menu/adverts, not a claim that arbitrary
/// source text has been classified or recipe quantities verified.
enum NamedDishProvenance {
    static let notice = "Best-effort traditional version of the named dish. The menu or advert did not provide a source recipe; ingredients, quantities and method are suggestions to review."
    static func needsNotice(source raw: String) -> Bool {
        let source = CaptionAnalysis.stripInstagramPrefix(raw)
        return CaptionAnalysis.isPromo(source) && !CaptionAnalysis.hasRecipeSignals(source)
            && !CuisineGlossary.matches(in: source).isEmpty
    }
    static let descriptionNotice = "Best-effort traditional version, reconstructed from a dish name rather than a source recipe."
    static func isReconstructed(_ card: RecipeCard) -> Bool { (card.aiNote ?? "").contains(notice) }
    static func confidenceLabel(_ confidence: Double, card: RecipeCard) -> String {
        let percent = Int((confidence * 100).rounded())
        if isReconstructed(card) {
            return "Dish-name confidence \(percent)% - no source recipe; ingredients and method are suggestions"
        }
        return "AI confidence \(percent)%" + (confidence < RecipeQuality.threshold ? " - check this is the right dish" : "")
    }
    static func apply(_ original: RecipeCard) -> RecipeCard {
        var card = original
        if !(card.aiNote ?? "").contains(notice) {
            card.aiNote = [notice, card.aiNote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        if !(card.description ?? "").contains(descriptionNotice) {
            card.description = [descriptionNotice, card.description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return card
    }
}
