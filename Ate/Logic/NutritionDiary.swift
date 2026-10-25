import Foundation

enum NutritionMeal: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum NutritionEntrySource: String, CaseIterable, Codable, Identifiable {
    case userProvided, recipeSnapshot, externalFoodRecord
    var id: String { rawValue }
    var title: String {
        switch self {
        case .userProvided: "Entered by you"
        case .recipeSnapshot: "Recipe snapshot"
        case .externalFoodRecord: "External record (not verified by Ate)"
        }
    }

    /// Safe initial provenance text for a newly selected source. External sources
    /// must be named by the person logging the food so we never invent a provider.
    var suggestedSourceName: String {
        switch self {
        case .userProvided: "You"
        case .recipeSnapshot: "Recipe snapshot"
        case .externalFoodRecord: ""
        }
    }

    func accepts(sourceName: String) -> Bool {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if self != .userProvided && name.caseInsensitiveCompare("You") == .orderedSame { return false }
        return true
    }
}

/// Per-serving nutrient snapshot captured at the time the food was explicitly logged.
/// Nil means unknown and must never be replaced with an estimate.
struct NutritionSnapshot: Codable, Equatable {
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?

    subscript(_ field: NutritionGoalField) -> Double? {
        switch field {
        case .energy: energyKcal
        case .protein: proteinGrams
        case .carbohydrates: carbohydratesGrams
        case .fat: fatGrams
        case .fibre: fibreGrams
        }
    }
}

struct NutritionDiaryEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var foodName: String
    var date: Date
    var meal: NutritionMeal
    var quantity: Double
    var quantityUnit: String
    var servings: Double
    var source: NutritionEntrySource
    var sourceName: String
    var sourceIdentifier: String
    var verificationNote: String
    var nutrientsPerServing: NutritionSnapshot

    init(id: UUID = UUID(), foodName: String, date: Date, meal: NutritionMeal, quantity: Double,
         quantityUnit: String, servings: Double, source: NutritionEntrySource, sourceName: String,
         sourceIdentifier: String = "", verificationNote: String = "", nutrientsPerServing: NutritionSnapshot) {
        self.id = id
        self.foodName = foodName
        self.date = date
        self.meal = meal
        self.quantity = quantity
        self.quantityUnit = quantityUnit
        self.servings = servings
        self.source = source
        self.sourceName = sourceName
        self.sourceIdentifier = sourceIdentifier
        self.verificationNote = verificationNote
        self.nutrientsPerServing = nutrientsPerServing
    }
}

struct NutritionDayTotals: Equatable {
    let values: [NutritionGoalField: Double?]

    func value(for field: NutritionGoalField) -> Double? {
        values[field] ?? nil
    }

    static func calculate(entries: [NutritionDiaryEntry]) -> NutritionDayTotals {
        var totals: [NutritionGoalField: Double?] = [:]
        for field in NutritionGoalField.allCases {
            guard !entries.isEmpty else { totals[field] = nil; continue }
            var sum = 0.0
            var complete = true
            for entry in entries {
                guard let value = entry.nutrientsPerServing[field], value.isFinite else { complete = false; break }
                sum += value * entry.servings
            }
            totals[field] = complete && sum.isFinite ? (sum * 10).rounded() / 10 : nil
        }
        return NutritionDayTotals(values: totals)
    }
}

enum NutritionDiaryValidation {
    static func isValid(_ entry: NutritionDiaryEntry) -> Bool {
        !entry.foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !entry.quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.quantity.isFinite && entry.quantity > 0
            && entry.servings.isFinite && entry.servings > 0
            && entry.source.accepts(sourceName: entry.sourceName)
            && NutritionGoalField.allCases.allSatisfy { field in
                guard let value = entry.nutrientsPerServing[field] else { return true }
                return value.isFinite && value >= 0
            }
    }
}

struct NutritionDiaryRepository {
    let defaults: UserDefaults
    static let storageKey = "ate.nutritionDiary.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [NutritionDiaryEntry] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([NutritionDiaryEntry].self, from: data) else { return [] }
        return entries.sorted { $0.date > $1.date }
    }

    func save(_ entries: [NutritionDiaryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: Self.storageKey)
    }
}
