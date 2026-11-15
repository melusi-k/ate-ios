import Foundation

/// Counts explicit local cooking-history records, never eaten meals or servings.
/// Uses stored local-day components, not UTC timestamps, so changing time zones
/// does not move an already recorded event into another month.
struct CookingMonthSummary: Equatable {
    let cookingDays: Int
    let distinctRecipes: Int

    static func make(events: [String: Set<String>], month: Date,
                     calendar: Calendar = .autoupdatingCurrent) -> Self {
        let target = calendar.dateComponents([.year, .month], from: month)
        var days = 0, recipes = Set<String>()
        for (key, ids) in events {
            let parts = key.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
                  year == target.year, month == target.month,
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.year, from: date) == year,
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { continue }
            let recorded = ids.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !recorded.isEmpty else { continue }
            days += 1; recipes.formUnion(recorded)
        }
        return Self(cookingDays: days, distinctRecipes: recipes.count)
    }
    var text: String {
        let dayLabel = cookingDays == 1 ? "day" : "days"
        let recipeLabel = distinctRecipes == 1 ? "recipe" : "recipes"
        return "\(cookingDays) cooking \(dayLabel) · \(distinctRecipes) distinct \(recipeLabel)"
    }
}
