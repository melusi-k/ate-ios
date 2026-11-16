import Foundation

/// Explicit quality repair is different from transport Retry, dish re-identification
/// and a scoped user rewrite. It receives the exact failed draft, not just a dish
/// name, and cannot replace it with an unrelated card because a gap count fell.
enum RecipeDraftRepair {
    static func instruction(for card: RecipeCard) throws -> String {
        guard RecipeQuality.isGenerated(card), !RecipeQuality.shortfall(card).isEmpty else {
            throw BackendError(message: "This card has no generated quality gaps to repair.")
        }
        let data = try JSONEncoder().encode(card)
        guard let json = String(data: data, encoding: .utf8) else {
            throw BackendError(message: "Ate couldn't read this draft for repair. Your draft is unchanged.")
        }
        return "Repair this exact draft (JSON), not a new recipe:\n" + json + "\n" +
            RecipePrompt.retryInstruction(gaps: RecipeQuality.shortfall(card), visibleLabels: [])
    }

    static func automaticImproves(_ candidate: RecipeCard, over original: RecipeCard,
                                  labels: [String]) -> Bool {
        guard candidate.title.caseInsensitiveCompare(original.title) == .orderedSame,
              candidate.servings == original.servings else { return false }
        let before = Set(RecipeQuality.shortfall(RecipeLogic.normalize(original), labels: labels))
        let after = Set(RecipeQuality.shortfall(RecipeLogic.normalize(candidate), labels: labels))
        return after.isStrictSubset(of: before)
    }

    static func accept(_ candidate: RecipeCard, replacing original: RecipeCard) throws -> RecipeCard {
        guard candidate.title.caseInsensitiveCompare(original.title) == .orderedSame,
              candidate.servings == original.servings else {
            throw BackendError(message: "The repair changed the dish or servings. Your original draft is unchanged.")
        }
        var repaired = candidate
        // Preserve user identity/provenance/media, never accept a higher model
        // self-confidence as proof a missing ingredient was repaired.
        repaired.id = original.id
        repaired.createdAt = original.createdAt
        repaired.favorite = original.favorite
        repaired.sortIndex = original.sortIndex
        repaired.lastCookedAt = original.lastCookedAt
        repaired.coverImage = original.coverImage
        repaired.imageURL = original.imageURL
        repaired.sourceURL = original.sourceURL
        repaired.origin = original.origin
        repaired.source = original.source
        repaired.aiConfidence = original.aiConfidence
        repaired.aiAlternatives = original.aiAlternatives
        repaired = RecipeLogic.normalize(repaired)
        let oldGaps = Set(RecipeQuality.shortfall(original))
        let newGaps = Set(RecipeQuality.shortfall(repaired))
        // Do not trade a missing bread/quantity gap for a different failure. Every
        // remaining gap must already have existed and at least one must be fixed.
        guard newGaps.isStrictSubset(of: oldGaps) else {
            let added = newGaps.subtracting(oldGaps).sorted()
            if !added.isEmpty {
                throw BackendError(message: "The repair added a new problem: " + added.joined(separator: " ")
                    + " Your original draft is unchanged.")
            }
            throw BackendError(message: "The repair did not fix any of the listed gaps. Your original draft is unchanged; edit it or try repair again.")
        }
        return repaired
    }
}
