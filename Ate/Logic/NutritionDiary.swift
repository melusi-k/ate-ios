import Foundation

enum NutritionMeal: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// A local calendar date independent of the time zone used to view the diary later.
enum NutritionDiaryDayKey {
    static func make(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(for key: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }
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
    /// Calendar day selected when logged, persisted as YYYY-MM-DD local date.
    var dayKey: String
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
         sourceIdentifier: String = "", verificationNote: String = "", nutrientsPerServing: NutritionSnapshot,
         dayKey: String? = nil) {
        self.id = id
        self.foodName = foodName
        self.date = date
        self.dayKey = dayKey ?? NutritionDiaryDayKey.make(date)
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

    private enum CodingKeys: String, CodingKey {
        case id, foodName, date, dayKey, meal, quantity, quantityUnit, servings, source, sourceName
        case sourceIdentifier, verificationNote, nutrientsPerServing
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        foodName = try values.decode(String.self, forKey: .foodName)
        date = try values.decode(Date.self, forKey: .date)
        // Existing v1 entries have only an instant. Capture their best available
        // local day once when migrating; all new entries persist dayKey directly.
        dayKey = try values.decodeIfPresent(String.self, forKey: .dayKey) ?? NutritionDiaryDayKey.make(date)
        meal = try values.decode(NutritionMeal.self, forKey: .meal)
        quantity = try values.decode(Double.self, forKey: .quantity)
        quantityUnit = try values.decode(String.self, forKey: .quantityUnit)
        servings = try values.decode(Double.self, forKey: .servings)
        source = try values.decode(NutritionEntrySource.self, forKey: .source)
        sourceName = try values.decode(String.self, forKey: .sourceName)
        sourceIdentifier = try values.decode(String.self, forKey: .sourceIdentifier)
        verificationNote = try values.decode(String.self, forKey: .verificationNote)
        nutrientsPerServing = try values.decode(NutritionSnapshot.self, forKey: .nutrientsPerServing)
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
        let legacyRecords = ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]])?
            .contains { $0["dayKey"] == nil } ?? false
        let sorted = entries.sorted {
            $0.dayKey == $1.dayKey ? $0.date > $1.date : $0.dayKey > $1.dayKey
        }
        // Persist migrated keys immediately so a later time-zone change cannot
        // reinterpret legacy entries a second time.
        if legacyRecords { try? save(sorted) }
        return sorted
    }

    func save(_ entries: [NutritionDiaryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: Self.storageKey)
    }
}
