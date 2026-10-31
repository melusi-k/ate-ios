import Foundation
import SwiftData

/// The kind of a unified Food Journal entry (#245).
/// Journal rows written before the unification predate this field and decode as `.reflection`
/// through the model default, so existing journals keep their meaning without a data rewrite.
enum JournalEntryKind: String, Codable, CaseIterable {
    case meal, reflection
}

/// Structured meal payload attached one-to-one to a Food Journal meal entry (#245).
///
/// Linked to the owning `JournalEntry` by `entryID` (the entry's stable identity). Nutrition
/// stays typed and queryable and is never flattened into prose. A nil nutrient means unknown
/// and must never be replaced with an estimate - the same contract as `NutritionSnapshot`.
@Model
final class JournalMealPayload {
    @Attribute(.unique) var entryID: String
    var mealRaw: String
    var foodName: String
    var quantity: Double
    var quantityUnit: String
    var servings: Double
    var sourceRaw: String
    var sourceName: String
    var sourceIdentifier: String
    var verificationNote: String
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?

    init(entryID: String, meal: NutritionMeal, foodName: String, quantity: Double, quantityUnit: String,
         servings: Double, source: NutritionEntrySource, sourceName: String, sourceIdentifier: String = "",
         verificationNote: String = "", nutrients: NutritionSnapshot) {
        self.entryID = entryID
        self.mealRaw = meal.rawValue
        self.foodName = foodName
        self.quantity = quantity
        self.quantityUnit = quantityUnit
        self.servings = servings
        self.sourceRaw = source.rawValue
        self.sourceName = sourceName
        self.sourceIdentifier = sourceIdentifier
        self.verificationNote = verificationNote
        self.energyKcal = nutrients.energyKcal
        self.proteinGrams = nutrients.proteinGrams
        self.carbohydratesGrams = nutrients.carbohydratesGrams
        self.fatGrams = nutrients.fatGrams
        self.fibreGrams = nutrients.fibreGrams
    }

    /// Raw values are always written from `NutritionMeal`; the fallback only guards future schema drift,
    /// mirroring how `JournalEntry.state` tolerates unknown persisted values.
    var meal: NutritionMeal { NutritionMeal(rawValue: mealRaw) ?? .snack }
    var source: NutritionEntrySource { NutritionEntrySource(rawValue: sourceRaw) ?? .userProvided }

    var nutrients: NutritionSnapshot {
        NutritionSnapshot(energyKcal: energyKcal, proteinGrams: proteinGrams,
                          carbohydratesGrams: carbohydratesGrams, fatGrams: fatGrams, fibreGrams: fibreGrams)
    }

    /// Rebuilds the value the diary stack works with today, so #179 calculations and totals
    /// keep operating on identical fields after the persistence switch (#245 phase 2).
    func diaryEntry(id: UUID, date: Date, dayKey: String) -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: foodName, date: date, meal: meal, quantity: quantity,
                            quantityUnit: quantityUnit, servings: servings, source: source,
                            sourceName: sourceName, sourceIdentifier: sourceIdentifier,
                            verificationNote: verificationNote, nutrientsPerServing: nutrients, dayKey: dayKey)
    }
}
