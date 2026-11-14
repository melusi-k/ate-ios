#if DEBUG
import Foundation

/// Saved mock-equivalent card only. Never seeds detent, scale, scroll or sheet
/// presentation; both portrait and rotation journeys drive the real Library UI.
enum RecipeSheetQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting,
              ProcessInfo.processInfo.arguments.contains("-qaSavedRecipeForSheet") else { return }
        store.filter.clear()
        store.layout = LibraryLayout()
        store.recipes = [RecipeCard(id: "qa-recipe-sheet", title: "Miso salmon for two",
            description: "Demo card \u{2014} on-device AI isn't available on this device.",
            servings: 2, timeMinutes: 21, tags: ["quick", "demo"],
            ingredients: [.init(name: "salmon fillets", quantity: 2, unit: "pcs"),
                          .init(name: "white miso", quantity: 2, unit: "tbsp"),
                          .init(name: "honey", quantity: 1, unit: "tbsp"),
                          .init(name: "garlic", quantity: 2, unit: "cloves", notes: "finely chopped"),
                          .init(name: "rice", quantity: 150, unit: "g")],
            steps: [.init(order: 1, instruction: "Heat the oven to 200°C and line a tray.", timeSeconds: nil),
                    .init(order: 2, instruction: "Mix miso, honey and garlic; brush over the salmon.", timeSeconds: nil),
                    .init(order: 3, instruction: "Roast the salmon until just flaky.", timeSeconds: 600),
                    .init(order: 4, instruction: "Rest for a minute, then serve over rice.", timeSeconds: 60)],
            source: .mock)]
    }
}
#endif
