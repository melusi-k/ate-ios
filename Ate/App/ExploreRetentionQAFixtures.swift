#if DEBUG
import Foundation

/// Separate preconditions for menu selection and Search retention. Never fills
/// the Search query or opens/dismisses Explore; those remain real UI actions.
enum ExploreRetentionQAFixtures {
    enum Mode: Equatable { case saved, favourites }
    static func mode(isUITesting: Bool, arguments: [String]) -> Mode? {
        guard isUITesting, arguments.contains("-qaExploreRetentionSaved") else { return nil }
        return arguments.contains("-qaExploreRetentionFavourites") ? .favourites : .saved
    }

    @MainActor static func prepare(_ store: AppStore) {
        guard let mode = mode(isUITesting: AppConfig.isUITesting,
                                           arguments: ProcessInfo.processInfo.arguments) else { return }
        store.filter.clear()
        store.layout = LibraryLayout()
        store.recipes = [RecipeCard(id: "qa-explore-retention-miso", title: "Miso salmon for two",
            servings: 2, timeMinutes: 25,
            ingredients: [.init(name: "salmon fillets", quantity: 2, unit: "pcs"),
                          .init(name: "white miso", quantity: 2, unit: "tbsp")],
            steps: [.init(order: 1, instruction: "Roast the salmon until flaky.", timeSeconds: 600)])]
        if mode == .favourites { store.filter.collection = .favourites }
    }
}
#endif
