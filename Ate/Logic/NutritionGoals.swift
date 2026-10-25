import Foundation

/// Daily nutrition targets are user-defined and independently optional.
/// Values are stored in canonical units: kcal for energy and grams for nutrients.
struct DailyNutritionGoals: Codable, Equatable {
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?

    static let defaultsKey = "ate.nutritionGoals.v1"

    subscript(field: NutritionGoalField) -> Double? {
        get {
            switch field {
            case .energy: energyKcal
            case .protein: proteinGrams
            case .carbohydrates: carbohydratesGrams
            case .fat: fatGrams
            case .fibre: fibreGrams
            }
        }
        set {
            switch field {
            case .energy: energyKcal = newValue
            case .protein: proteinGrams = newValue
            case .carbohydrates: carbohydratesGrams = newValue
            case .fat: fatGrams = newValue
            case .fibre: fibreGrams = newValue
            }
        }
    }

    var isEmpty: Bool {
        energyKcal == nil && proteinGrams == nil && carbohydratesGrams == nil
            && fatGrams == nil && fibreGrams == nil
    }
}

enum NutritionGoalField: String, CaseIterable, Identifiable {
    case energy, protein, carbohydrates, fat, fibre

    var id: String { rawValue }
    var title: String {
        switch self {
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .fat: "Fat"
        case .fibre: "Fibre"
        }
    }
    var unit: String { self == .energy ? "kcal" : "g" }
    var maximum: Double { self == .energy ? 100_000 : 10_000 }
    var allowsFractionalValue: Bool { self != .energy }
    var accessibilityName: String { "\(title) daily goal, \(unit)" }
}

enum NutritionGoalValidation {
    /// Returns a field-specific error when an enabled goal is missing or invalid.
    static func error(for field: NutritionGoalField, text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a \(field.unit) target or turn this goal off." }

        // Accept the current locale's decimal separator as well as a dot.
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value.isFinite else {
            return "Enter a valid number."
        }
        guard value > 0 else { return "Enter a value greater than zero." }
        guard value <= field.maximum else {
            return "Enter a value no greater than \(Int(field.maximum)) \(field.unit)."
        }
        if !field.allowsFractionalValue, value.rounded() != value {
            return "Energy must be a whole number of kcal."
        }
        if field.allowsFractionalValue, (value * 10).rounded() != value * 10 {
            return "Use no more than one decimal place."
        }
        return nil
    }

    static func number(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// Small UserDefaults-backed local repository. The defaults instance is injectable for isolated tests.
struct NutritionGoalsRepository {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DailyNutritionGoals {
        guard let data = defaults.data(forKey: DailyNutritionGoals.defaultsKey),
              let goals = try? JSONDecoder().decode(DailyNutritionGoals.self, from: data) else {
            return DailyNutritionGoals(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        }
        return goals
    }

    func save(_ goals: DailyNutritionGoals) throws {
        if goals.isEmpty {
            defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
            return
        }
        let data = try JSONEncoder().encode(goals)
        defaults.set(data, forKey: DailyNutritionGoals.defaultsKey)
    }
}
