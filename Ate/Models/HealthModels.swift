import Foundation
import SwiftData

/// One day of read-only Health signals (nil = not available / not shared).
struct HealthDay: Codable, Hashable {
    var date: Date
    var sleepHours: Double?
    var steps: Int?
    var activeEnergyKcal: Double?
    var workoutMinutes: Double?
    var workoutTypes: [String] = []
}

/// Last 1–7 days of Health signals, newest last.
struct HealthSummary: Codable, Hashable {
    var days: [HealthDay]
    var today: HealthDay? { days.last }
    var hasAnyData: Bool {
        days.contains { $0.sleepHours != nil || $0.steps != nil || $0.activeEnergyKcal != nil || ($0.workoutMinutes ?? 0) > 0 }
    }
    var averageSteps: Int? {
        let s = days.compactMap(\.steps); return s.isEmpty ? nil : s.reduce(0, +) / s.count
    }
    var lastWorkoutMinutes: Double? {
        let d = days.suffix(2).compactMap(\.workoutMinutes); return d.isEmpty ? nil : d.reduce(0, +)
    }
}

/// App-specific body state inferred from Health. Deliberately simple and explainable.
enum HealthState: String, Codable, CaseIterable {
    case recovery      // hard workout recently → protein, recovery-friendly
    case lowEnergy     // short sleep and/or low activity → lighter, comforting
    case performance   // well rested, active → energising / meal prep
    case underactive   // low steps for several days → lighter dinner + walk
    case balanced      // nothing stands out

    var title: String {
        switch self {
        case .recovery: return "Recovery day"
        case .lowEnergy: return "Low-energy day"
        case .performance: return "Good-energy day"
        case .underactive: return "Quiet week"
        case .balanced: return "Balanced day"
        }
    }
    var symbol: String {
        switch self {
        case .recovery: return "figure.cooldown"
        case .lowEnergy: return "moon.zzz"
        case .performance: return "bolt.heart"
        case .underactive: return "figure.walk"
        case .balanced: return "leaf"
        }
    }
    var mealFocus: String {
        switch self {
        case .recovery: return "High-protein meal suggestions"
        case .lowEnergy: return "Lighter, comforting meals"
        case .performance: return "Energising and meal-prep ideas"
        case .underactive: return "Lighter dinner ideas"
        case .balanced: return "Meals for today"
        }
    }
}

/// What the engine concluded, with human-readable reasons.
struct HealthInsight: Hashable {
    var state: HealthState
    var reasons: [String]
    var headline: String
}

/// Everything the Insights screen needs.
struct HealthContext {
    var summary: HealthSummary
    var insight: HealthInsight
    var suggestions: [NutritionFitSuggestion]
    var prompts: [JournalPrompt]
}

struct NutritionFitSuggestion: Hashable, Identifiable {
    var recipeID: String
    var title: String
    var why: String
    var score: Double
    var id: String { recipeID }
}

struct JournalPrompt: Hashable, Identifiable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var state: HealthState
    var generated: Bool = false
}

/// Local-only journal entry (SwiftData). Never synced or sent anywhere.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: String
    var createdAt: Date
    var prompt: String
    var text: String
    var stateRaw: String
    var recipeIDs: [String]
    init(id: String = UUID().uuidString, createdAt: Date = .now, prompt: String, text: String, state: HealthState, recipeIDs: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.prompt = prompt; self.text = text; self.stateRaw = state.rawValue; self.recipeIDs = recipeIDs
    }
    var state: HealthState { HealthState(rawValue: stateRaw) ?? .balanced }
}

/// Recipes seeded for Health UI tests (`-qaHealthRecipes`) so meal ranking is observable.
enum HealthFixtures {
    static var library: [RecipeCard] {
        func r(_ id: String, _ t: String, _ ings: [String], mins: Int = 40, servings: Int = 2) -> RecipeCard {
            var c = RecipeCard(); c.id = id; c.title = t; c.timeMinutes = mins; c.servings = servings
            c.ingredients = ings.map { Ingredient(name: $0, quantity: 1, unit: "") }; return c
        }
        return [r("qa-h1", "Grilled chicken bowl", ["chicken", "rice", "spinach"]),
                r("qa-h2", "Lentil soup", ["lentils", "tomato", "onion"], mins: 25),
                r("qa-h3", "Greek salad", ["cucumber", "tomato", "feta"], mins: 10),
                r("qa-h4", "Overnight oats", ["oats", "banana", "yogurt"], servings: 4),
                r("qa-h5", "Beef potjie", ["beef", "potato", "carrot"], mins: 120, servings: 6)]
    }
}
