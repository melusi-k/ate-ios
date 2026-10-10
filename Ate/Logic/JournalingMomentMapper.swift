import Foundation

/// Pure, framework-free mapping from a Journaling Suggestions moment to an Ate request.
/// The JournalingSuggestions framework is imported only in JournalingSuggestionsBridge (app target).
enum AteMomentRequest: Equatable {
    case recipeDraft(title: String, date: Date?)
    case journalEntry(prompt: String, title: String, date: Date?, state: HealthState)
}

enum JournalingMomentMapper {
    static let foodWords = ["dinner", "lunch", "breakfast", "brunch", "meal", "braai", "cook", "cooking", "restaurant", "cafe", "café",
                            "kitchen", "recipe", "eat", "ate", "food", "supper", "bake", "baking", "market"]

    static func map(title raw: String, date: DateInterval?, hasPhotos: Bool, isWorkout: Bool) -> AteMomentRequest {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A moment" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = date?.start
        if isWorkout {
            return .journalEntry(prompt: "After \(title): how does your body feel, and what would help you recover?", title: title, date: start, state: .recovery)
        }
        let lower = title.lowercased()
        let foodish = foodWords.contains { lower.range(of: "\\b" + $0 + "\\b", options: .regularExpression) != nil }
        if foodish && hasPhotos { return .recipeDraft(title: title, date: start) }
        return .journalEntry(prompt: "About \(title): what did you eat, and would you cook it again?", title: title, date: start, state: .balanced)
    }

    /// Recipe draft card (additive: source .journalMoment; nothing else in the schema changes).
    static func draft(title: String, date: Date?) -> RecipeCard {
        var c = RecipeCard(); c.title = title; c.source = .journalMoment; c.origin = nil
        c.description = "From a Journal moment" + (date.map { " on " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "") + ". Add ingredients and steps."
        return c
    }

    static func contextLine(title: String?, date: Date?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        return "From a Journal moment: " + title + (date.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
    }
}
