import Foundation

/// Why a diary draft cannot be saved yet. Editing keeps the typed draft on every
/// failure; these only decide which honest message the form shows.
enum NutritionDiaryDraftError: Equatable {
    /// Quantity or servings is not a finite number greater than zero.
    case invalidAmounts
    /// A nutrient field holds text that is not a non-negative number.
    case invalidNutrient
    /// The assembled entry fails diary validation (name, unit, source name, strict calendar day).
    case invalidEntry

    var message: String {
        switch self {
        case .invalidAmounts:
            return "Enter a quantity and servings greater than zero."
        case .invalidNutrient:
            return "Enter a valid non-negative value for each nutrient, or leave it blank."
        case .invalidEntry:
            return "Check the food name, quantity unit, source name and day."
        }
    }
}

/// An editable diary draft. Numeric fields stay text so a failed save never loses what was
/// typed, and blank nutrients stay unknown (nil) rather than becoming zero.
struct NutritionDiaryEntryDraft: Equatable {
    var foodName = ""
    /// The calendar day the entry belongs to. Changing it is a deliberate move: an edit
    /// never rewrites the entry's original time instant.
    var dayKey: String
    var meal: NutritionMeal = .lunch
    var quantity = "1"
    var quantityUnit = "serving"
    var servings = "1"
    var source: NutritionEntrySource = .userProvided
    var sourceName = NutritionEntrySource.userProvided.suggestedSourceName
    var sourceIdentifier = ""
    var verificationNote = ""
    var nutrientText: [NutritionGoalField: String] = [:]

    /// A new entry draft for the given day.
    init(dayKey: String) {
        self.dayKey = dayKey
    }

    /// An edit draft prefilled from an existing entry. Unknown nutrients stay blank and
    /// provenance fields carry over verbatim.
    init(entry: NutritionDiaryEntry) {
        foodName = entry.foodName
        dayKey = entry.dayKey
        meal = entry.meal
        quantity = Self.text(for: entry.quantity)
        quantityUnit = entry.quantityUnit
        servings = Self.text(for: entry.servings)
        source = entry.source
        sourceName = entry.sourceName
        sourceIdentifier = entry.sourceIdentifier
        verificationNote = entry.verificationNote
        nutrientText = Dictionary(uniqueKeysWithValues: NutritionGoalField.allCases.map {
            ($0, entry.nutrientsPerServing[$0].map(Self.text(for:)) ?? "")
        })
    }

    /// Stable editable text for a stored value: 2 stays "2", 1.5 stays "1.5".
    static func text(for value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    /// Assembles the entry. With an `existing` entry, its identity and original time instant
    /// are preserved exactly; only the fields a person can see and edit change, and a changed
    /// dayKey is the deliberate, visible move the editor offers. Validation is the store's own
    /// strict rule set, so a draft can never smuggle in a day the canonical store would reject.
    /// MainActor-isolated because it applies the canonical store's own validity rule.
    @MainActor
    func parsedEntry(existing: NutritionDiaryEntry? = nil,
                     calendar: Calendar = .autoupdatingCurrent) -> Result<NutritionDiaryEntry, NutritionDiaryDraftError> {
        guard let quantityValue = NutritionDiaryNumber.parse(quantity),
              let servingCount = NutritionDiaryNumber.parse(servings),
              quantityValue > 0, servingCount > 0 else {
            return .failure(.invalidAmounts)
        }
        var values: [NutritionGoalField: Double] = [:]
        for field in NutritionGoalField.allCases {
            let text = (nutrientText[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let value = NutritionDiaryNumber.parse(text), value >= 0 else { return .failure(.invalidNutrient) }
            values[field] = value
        }
        let snapshot = NutritionSnapshot(energyKcal: values[.energy], proteinGrams: values[.protein],
                                         carbohydratesGrams: values[.carbohydrates], fatGrams: values[.fat],
                                         fibreGrams: values[.fibre])
        let entry = NutritionDiaryEntry(
            id: existing?.id ?? UUID(),
            foodName: foodName,
            date: existing?.date ?? NutritionDiaryDayKey.date(for: dayKey, calendar: calendar) ?? .now,
            meal: meal,
            quantity: quantityValue,
            quantityUnit: quantityUnit,
            servings: servingCount,
            source: source,
            sourceName: sourceName,
            sourceIdentifier: sourceIdentifier,
            verificationNote: verificationNote,
            nutrientsPerServing: snapshot,
            dayKey: dayKey)
        guard FoodJournalStore.validMeal(entry) else { return .failure(.invalidEntry) }
        return .success(entry)
    }
}
