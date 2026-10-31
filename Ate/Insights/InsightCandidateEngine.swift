import Foundation
import CryptoKit

/// A deterministic, evidence-backed insight candidate. Candidate generation never performs I/O
/// and never relies on generated language to establish facts.
enum InsightActionDestination: Equatable {
    case recipes
    case cookingHistory
    case shoppingList
    case foodDiary
}

enum InsightEvidenceConfidence: String, Equatable {
    /// The displayed fact is a direct count or state from a local source.
    case high = "High"
    /// The insight combines or interprets multiple locally recorded facts.
    case moderate = "Moderate"
}

struct InsightEvidenceMetadata: Equatable {
    let source: String
    let period: String
    let confidence: InsightEvidenceConfidence
}

struct RankedRecipeInsightCandidate: Equatable {
    let id: String
    let priority: Int
    let evidenceFingerprint: String
    let evidenceMetadata: InsightEvidenceMetadata
    let action: InsightActionDestination
    let insight: RecipeProgressInsight
}

/// Produces a small ranked set rather than forcing the UI to choose between unrelated rules.
/// Stable IDs and fingerprints let lifecycle handling evolve to candidate-level controls safely.
enum InsightCandidateEngine {
    static let maximumCandidates = 3

    static func candidates(
        for input: RecipeProgressInsightInput,
        shoppingItems: [ShoppingItem] = [],
        nutritionEntries: [NutritionDiaryEntry]? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        isEligible: (RankedRecipeInsightCandidate) -> Bool = { _ in true }
    ) -> [RankedRecipeInsightCandidate] {
        // Weekly evidence is scoped to the calendar week it was measured in, so the same count
        // in a later week is new evidence rather than a previously dismissed insight.
        let weekKey = calendar.dateInterval(of: .weekOfYear, for: now)
            .map { NutritionDiaryDayKey.make($0.start, calendar: calendar) } ?? "unknown-week"
        var result: [RankedRecipeInsightCandidate] = []
        func append(_ id: String, priority: Int, evidence: String, metadata: InsightEvidenceMetadata, action: InsightActionDestination, insight: RecipeProgressInsight) {
            let fingerprint = RecipeProgressInsightFingerprint.makeEvidence(
                candidateID: id,
                evidence: evidence
            )
            result.append(RankedRecipeInsightCandidate(
                id: id,
                priority: priority,
                evidenceFingerprint: fingerprint,
                evidenceMetadata: metadata,
                action: action,
                insight: insight
            ))
        }

        if let group = input.duplicateTitleGroups.first {
            let titles = group.joined(separator: "” and “")
            append(
                "recipe-duplicates",
                priority: 100,
                evidence: group.sorted().joined(separator: "|"),
                metadata: InsightEvidenceMetadata(source: "Saved recipe titles", period: "Current collection", confidence: .moderate),
                action: .recipes,
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
                evidence: "\(weekKey)|\(count)",
                metadata: InsightEvidenceMetadata(source: "Cooking history", period: "This week", confidence: .high),
                action: .cookingHistory,
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
                evidence: "\(weekKey)|\(count)",
                metadata: InsightEvidenceMetadata(source: "Saved recipes and cooking history", period: "This week", confidence: .moderate),
                action: .recipes,
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
                metadata: InsightEvidenceMetadata(source: "Cooking history", period: "Current streak", confidence: .high),
                action: .cookingHistory,
                insight: RecipeProgressInsight(
                    title: "A cooking streak is taking shape",
                    detail: "Your recorded cooking streak is \(streak) days. Keep it flexible—cook when it works for you.",
                    evidence: "Based on your recorded cooking history.",
                    generated: false
                )
            )
        }

        let pendingItems = shoppingItems.filter { !$0.done }
        let recipeSources = Set(pendingItems.flatMap { $0.sources ?? ($0.from.map { [$0] } ?? []) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
        if pendingItems.count >= 3, recipeSources.count >= 2 {
            append(
                "shopping-multi-recipe",
                priority: 75,
                evidence: "\(pendingItems.count)|\(recipeSources.sorted().joined(separator: ","))",
                metadata: InsightEvidenceMetadata(source: "Shopping list and recipe sources", period: "Current pending items", confidence: .moderate),
                action: .shoppingList,
                insight: RecipeProgressInsight(
                    title: "Your shopping list brings recipes together",
                    detail: "\(pendingItems.count) items are still to buy across \(recipeSources.count) saved recipes. Your list is grouped by aisle to make the shop easier.",
                    evidence: "Based on pending shopping items and their saved-recipe sources.",
                    generated: false
                )
            )
        }

        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        // nil means the diary store was unreadable: skip diary-derived candidates rather
        // than fabricating an empty diary. An empty array means genuinely nothing logged.
        let nutritionWeek = (nutritionEntries ?? []).filter { entry in
            guard let day = NutritionDiaryDayKey.date(for: entry.dayKey, calendar: calendar) else { return false }
            let normalizedDay = calendar.startOfDay(for: day)
            return normalizedDay >= weekStart && normalizedDay <= today
        }
        let entriesWithNutrients = nutritionWeek.filter { entry in
            NutritionGoalField.allCases.contains { entry.nutrientsPerServing[$0] != nil }
        }.count
        if nutritionWeek.count >= 3, entriesWithNutrients < nutritionWeek.count {
            append(
                "nutrition-diary-coverage",
                priority: 58,
                evidence: "\(nutritionWeek.count)|\(entriesWithNutrients)|\(NutritionDiaryDayKey.make(weekStart, calendar: calendar))",
                metadata: InsightEvidenceMetadata(source: "Locally stored food diary", period: "Last 7 days", confidence: .high),
                action: .foodDiary,
                insight: RecipeProgressInsight(
                    title: "Add verified details to your food diary",
                    detail: "\(entriesWithNutrients) of \(nutritionWeek.count) foods logged in the last 7 days have at least one nutrient value. Add details only when you have a source you trust; Ate will leave unknown values blank.",
                    evidence: "Based on locally stored food-diary entries from the last 7 days.",
                    generated: false
                )
            )
        }

        // Evaluate all evidence-backed candidates before deciding whether fallback guidance is
        // needed. A candidate can exist in the raw set but be hidden by its lifecycle state.
        var eligibleCandidates = result.filter(isEligible)
        if eligibleCandidates.isEmpty {
            let fallbackStart = result.count
            if input.cookedRecipeCount > 0 {
                let focus = input.mostCookedRecipe.map { " You could revisit “\($0)” or try another recipe from your collection." } ?? " Try another recipe from your collection."
                append(
                    "cooking-rhythm",
                    priority: 40,
                    evidence: "\(input.cookedRecipeCount)|\(input.cookingDayCount)|\(input.mostCookedRecipe ?? "")",
                    metadata: InsightEvidenceMetadata(source: "Saved recipes and cooking history", period: "Recorded history", confidence: .moderate),
                    action: .cookingHistory,
                    insight: RecipeProgressInsight(
                        title: "Your cooking rhythm",
                        detail: "You've cooked \(input.cookedRecipeCount) distinct saved recipe\(input.cookedRecipeCount == 1 ? "" : "s") across \(input.cookingDayCount) recorded day\(input.cookingDayCount == 1 ? "" : "s").\(focus)",
                        evidence: "Based on your saved recipes and recorded cooking history.",
                        generated: false
                    )
                )
            }

            if input.savedRecipeCount >= 3 {
                append(
                    "recipe-collection",
                    priority: 20,
                    evidence: String(input.savedRecipeCount),
                    metadata: InsightEvidenceMetadata(source: "Saved recipe collection", period: "Current collection", confidence: .high),
                    action: .recipes,
                    insight: RecipeProgressInsight(
                        title: "Your recipe collection is taking shape",
                        detail: "You have \(input.savedRecipeCount) saved recipes. As you cook and record a few, Ate can surface patterns and ideas to revisit.",
                        evidence: "Based on your saved recipe collection.",
                        generated: false
                    )
                )
            }
            eligibleCandidates.append(contentsOf: result.dropFirst(fallbackStart).filter(isEligible))
        }

        // Lifecycle eligibility is applied before the cap so suppressed cards cannot crowd out
        // lower-ranked cards that are still eligible.
        return eligibleCandidates
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.id < $1.id
            }
            .prefix(maximumCandidates)
            .map { $0 }
    }
}

private extension RecipeProgressInsightFingerprint {
    static func makeEvidence(candidateID: String, evidence: String) -> String {
        let payload = [candidateID, evidence].joined(separator: "|")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
