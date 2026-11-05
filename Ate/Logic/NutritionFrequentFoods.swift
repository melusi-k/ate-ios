import Foundation

/// A food the person has actually logged before, offered for one-tap reuse (#179 easier
/// selection of commonly logged foods). Built only from the diary's own local entries: nothing
/// is looked up, fetched or collected anywhere else, and a repeated entry is never presented as
/// a verified food - prefilling keeps the source as the person and leaves verification blank.
struct NutritionFrequentFood: Equatable {
    /// Display name from the most recent entry for this food.
    var foodName: String
    var lastQuantity: Double
    var quantityUnit: String
    var lastServings: Double
    /// The person's own last logged values; an unknown nutrient stays nil, never zero.
    var nutrientsPerServing: NutritionSnapshot
    var timesLogged: Int
    var lastDayKey: String
}

enum NutritionFrequentFoods {
    /// Groups entries by normalized name (trimmed, case-folded). Most frequently logged first;
    /// ties break to the most recently logged. Values come from the most recent entry for each
    /// food, so the offer reflects what the person logged last time.
    static func topFoods(in entries: [NutritionDiaryEntry], limit: Int = 5) -> [NutritionFrequentFood] {
        var groups: [String: [NutritionDiaryEntry]] = [:]
        for entry in entries {
            let key = normalized(entry.foodName)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(entry)
        }
        let foods = groups.values.map { group -> NutritionFrequentFood in
            let sorted = group.sorted { $0.dayKey == $1.dayKey ? $0.date > $1.date : $0.dayKey > $1.dayKey }
            let latest = sorted[0]
            // The displayed/prefilled name is trimmed for presentation only; the logged entries
            // themselves keep exactly what the person typed.
            return NutritionFrequentFood(foodName: latest.foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                                         lastQuantity: latest.quantity,
                                         quantityUnit: latest.quantityUnit, lastServings: latest.servings,
                                         nutrientsPerServing: latest.nutrientsPerServing,
                                         timesLogged: group.count, lastDayKey: latest.dayKey)
        }
        return foods.sorted {
            $0.timesLogged == $1.timesLogged ? $0.lastDayKey > $1.lastDayKey : $0.timesLogged > $1.timesLogged
        }.prefix(limit).map { $0 }
    }

    /// A fresh add-draft prefilled from a prior entry. Name, amounts, unit and nutrients copy
    /// over as the person's own starting point; provenance does NOT - source stays
    /// `.userProvided`, source record and verification note stay blank, and the day and identity
    /// always belong to the new entry.
    static func draft(from food: NutritionFrequentFood, dayKey: String) -> NutritionDiaryEntryDraft {
        var draft = NutritionDiaryEntryDraft(dayKey: dayKey)
        draft.foodName = food.foodName
        draft.quantity = NutritionDiaryEntryDraft.text(for: food.lastQuantity)
        draft.quantityUnit = food.quantityUnit
        draft.servings = NutritionDiaryEntryDraft.text(for: food.lastServings)
        draft.source = .userProvided
        draft.sourceName = NutritionEntrySource.userProvided.suggestedSourceName
        draft.sourceIdentifier = ""
        draft.verificationNote = ""
        draft.nutrientText = Dictionary(uniqueKeysWithValues: NutritionGoalField.allCases.map {
            ($0, food.nutrientsPerServing[$0].map(NutritionDiaryEntryDraft.text(for:)) ?? "")
        })
        return draft
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
