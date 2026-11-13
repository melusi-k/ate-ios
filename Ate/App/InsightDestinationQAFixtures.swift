#if DEBUG
import Foundation

/// Synthetic records only, behind both DEBUG and the UI-testing launch gate.
/// The diary lives in its own suite, never replacing the ordinary user's diary.
enum InsightDestinationQAFixtures {
    static let flag = "-qaInsightDestinations"
    static var requested: Bool {
        AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains(flag)
    }
    static func shopping() -> [ShoppingItem] {
        [ShoppingItem(id: "qa-insight-tomatoes", name: "QA insight tomatoes", quantity: 2, unit: "pcs", sources: ["QA soup"]),
         ShoppingItem(id: "qa-insight-onions", name: "QA insight onions", quantity: 1, unit: "pcs", sources: ["QA soup"]),
         ShoppingItem(id: "qa-insight-rice", name: "QA insight rice", quantity: 1, unit: "kg", sources: ["QA curry"])]
    }
    static func entries(now: Date = Date()) -> [NutritionDiaryEntry] {
        (1...3).map { index in
            NutritionDiaryEntry(foodName: "QA insight food \(index)", date: now, meal: .lunch,
                                quantity: 1, quantityUnit: "serving", servings: 1, source: .userProvided,
                                sourceName: "Synthetic UI fixture", nutrientsPerServing: .init(
                                    energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil,
                                    fatGrams: nil, fibreGrams: nil))
        }
    }
    static func repository(prepare: Bool = true) -> NutritionDiaryRepository {
        guard requested else { return NutritionDiaryRepository() }
        let name = "ate.qa.insight-destinations"
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Synthetic Insights QA suite unavailable")
        }
        let repository = NutritionDiaryRepository(defaults: defaults)
        if prepare {
            defaults.removePersistentDomain(forName: name)
            do { try repository.save(entries()) }
            catch { preconditionFailure("Synthetic Insights QA diary could not be prepared") }
        }
        return repository
    }
}
#endif
