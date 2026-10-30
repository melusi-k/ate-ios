import Foundation
import CryptoKit

/// A deterministic, evidence-backed insight candidate. Candidate generation never performs I/O
/// and never relies on generated language to establish facts.
struct RankedRecipeInsightCandidate: Equatable {
    let id: String
    let priority: Int
    let evidenceFingerprint: String
    let insight: RecipeProgressInsight
}

/// Produces a small ranked set rather than forcing the UI to choose between unrelated rules.
/// Stable IDs and fingerprints let lifecycle handling evolve to candidate-level controls safely.
enum InsightCandidateEngine {
    static let maximumCandidates = 3

    static func candidates(for input: RecipeProgressInsightInput) -> [RankedRecipeInsightCandidate] {
        var result: [RankedRecipeInsightCandidate] = []
        let baseFingerprint = RecipeProgressInsightFingerprint.make(input)

        func append(_ id: String, priority: Int, evidence: String, insight: RecipeProgressInsight) {
            let fingerprint = RecipeProgressInsightFingerprint.makeEvidence(
                candidateID: id,
                baseFingerprint: baseFingerprint,
                evidence: evidence
            )
            result.append(RankedRecipeInsightCandidate(
                id: id,
                priority: priority,
                evidenceFingerprint: fingerprint,
                insight: insight
            ))
        }

        if let group = input.duplicateTitleGroups.first {
            let titles = group.joined(separator: "” and “")
            append(
                "recipe-duplicates",
                priority: 100,
                evidence: group.sorted().joined(separator: "|"),
                insight: RecipeProgressInsight(
                    title: "Possible overlapping recipe entries",
                    detail: "You have saved recipes with the same title: “\(titles)”. They may be separate versions, so review them before making changes.",
                    evidence: "Based on titles in your saved recipe collection.",
                    generated: false
                )
            )
        }

        if input.recordedMealsThisWeek > 0 {
            let count = input.recordedMealsThisWeek
            append(
                "weekly-cooking",
                priority: 70 + min(count, 5),
                evidence: String(count),
                insight: RecipeProgressInsight(
                    title: "This week's cooking",
                    detail: "You've recorded \(count) cooked meal\(count == 1 ? "" : "s") this week. You can revisit a favourite or try something new from your saved recipes.",
                    evidence: "Based on your recorded cooking history this week.",
                    generated: false
                )
            )
        }

        if input.firstTimeRecipesThisWeek > 0 {
            let count = input.firstTimeRecipesThisWeek
            append(
                "recipe-discovery",
                priority: 65 + min(count, 5),
                evidence: String(count),
                insight: RecipeProgressInsight(
                    title: "New recipes in your rotation",
                    detail: "\(count) saved recipe\(count == 1 ? "" : "s") appear in this week's cooking history for the first time.",
                    evidence: "Based on your saved recipes and recorded cooking history.",
                    generated: false
                )
            )
        }

        if input.currentStreak > 1 {
            let streak = input.currentStreak
            append(
                "cooking-streak",
                priority: 60 + min(streak, 7),
                evidence: String(streak),
                insight: RecipeProgressInsight(
                    title: "A cooking streak is taking shape",
                    detail: "Your recorded cooking streak is \(streak) days. Keep it flexible—cook when it works for you.",
                    evidence: "Based on your recorded cooking history.",
                    generated: false
                )
            )
        }

        if result.isEmpty, input.cookedRecipeCount > 0 {
            let focus = input.mostCookedRecipe.map { " You could revisit “\($0)” or try another recipe from your collection." } ?? " Try another recipe from your collection."
            append(
                "cooking-rhythm",
                priority: 40,
                evidence: "\(input.cookedRecipeCount)|\(input.cookingDayCount)|\(input.mostCookedRecipe ?? "")",
                insight: RecipeProgressInsight(
                    title: "Your cooking rhythm",
                    detail: "You've cooked \(input.cookedRecipeCount) distinct saved recipe\(input.cookedRecipeCount == 1 ? "" : "s") across \(input.cookingDayCount) recorded day\(input.cookingDayCount == 1 ? "" : "s").\(focus)",
                    evidence: "Based on your saved recipes and recorded cooking history.",
                    generated: false
                )
            )
        }

        if result.isEmpty, input.savedRecipeCount >= 3 {
            append(
                "recipe-collection",
                priority: 20,
                evidence: String(input.savedRecipeCount),
                insight: RecipeProgressInsight(
                    title: "Your recipe collection is taking shape",
                    detail: "You have \(input.savedRecipeCount) saved recipes. As you cook and record a few, Ate can surface patterns and ideas to revisit.",
                    evidence: "Based on your saved recipe collection.",
                    generated: false
                )
            )
        }

        return result
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.id < $1.id
            }
            .prefix(maximumCandidates)
            .map { $0 }
    }
}

private extension RecipeProgressInsightFingerprint {
    static func makeEvidence(candidateID: String, baseFingerprint: String, evidence: String) -> String {
        let payload = [candidateID, baseFingerprint, evidence].joined(separator: "|")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
