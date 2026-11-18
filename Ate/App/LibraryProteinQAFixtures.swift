#if DEBUG
import Foundation

/// Explicit synthetic Library fixture, never active in ordinary launches.
enum LibraryProteinQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-qaLibraryPorkGrouping") else { return }
        store.recipes = [RecipeCard(id: "qa-pork-ribs", title: "Sticky Ribs and wings",
            ingredients: [.init(name: "pork ribs", quantity: 1, unit: "kg"),
                          .init(name: "chicken wings", quantity: 800, unit: "g")]),
            RecipeCard(id: "qa-chicken-wings", title: "Lemon pepper wings",
                ingredients: [.init(name: "chicken wings", quantity: 800, unit: "g")])]
        store.filter.clear()
        store.layout.group = .mainIngredient
    }
}
#endif
