import Foundation

/// Report observable quality changes, not a model's self-rating of its own repair.
enum RepairFeedback {
    static let confidenceExplanation = "Confidence is how sure Ate is this is the right dish. Repairing doesn't change it."
    static let timedOut = "Repair took too long, your draft is unchanged, try again."

    static func accepted(original: RecipeCard, repaired: RecipeCard) -> String {
        let before = Set(RecipeQuality.issues(original))
        let after = Set(RecipeQuality.issues(repaired))
        let fixed = before.subtracting(after).sorted()
        let fixedCopy = fixed.isEmpty ? "The recipe was updated." :
            "Fixed \(fixed.count) gap\(fixed.count == 1 ? "" : "s"): " + fixed.joined(separator: " ")
        var remaining = after.sorted()
        if (repaired.aiConfidence ?? 1) < RecipeQuality.threshold {
            remaining.append("Confirm this is the right dish, or edit it, before saving. Repairing doesn't change dish confidence.")
        }
        return fixedCopy + (remaining.isEmpty ? " No listed gaps remain. You can save the recipe." :
            " Still needed: " + remaining.joined(separator: " "))
    }
}
