import Foundation

/// View-local selection only. No filtering, ordering, persistence or scheduling effects.
struct LibrarySelection {
    private(set) var isSelecting = false
    private(set) var selectedIDs: Set<String> = []

    mutating func enter() { isSelecting = true; selectedIDs.removeAll() }
    mutating func cancel() { isSelecting = false; selectedIDs.removeAll() }
    mutating func deselectAll() { selectedIDs.removeAll() }
    mutating func toggle(_ id: String) {
        guard isSelecting else { return }
        if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
    }
    mutating func reconcile(savedIDs: Set<String>) { selectedIDs.formIntersection(savedIDs) }

    /// Stable regardless of the order in which cards were tapped or displayed.
    func selectedRecipes(in recipes: [RecipeCard]) -> [RecipeCard] {
        var seen: Set<String> = []
        return recipes.filter { selectedIDs.contains($0.id) && seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
    }

    struct Summary: Equatable {
        let count: Int
        let knownServings: Int?
        let unknownServingsCount: Int
        let unknownTimeCount: Int
    }
    func summary(in recipes: [RecipeCard]) -> Summary {
        let selected = selectedRecipes(in: recipes)
        var total = 0
        var overflow = false
        for recipe in selected where recipe.servings > 0 {
            let result = total.addingReportingOverflow(recipe.servings)
            total = result.partialValue; overflow = overflow || result.overflow
        }
        return Summary(count: selected.count, knownServings: overflow ? nil : total,
            unknownServingsCount: selected.filter { $0.servings <= 0 }.count,
            unknownTimeCount: selected.filter { ($0.timeMinutes ?? 0) <= 0 }.count)
    }
}

/// Independent screen flag. Missing configuration ships ON; production ignores QA args.
enum StitchFeatureFlags {
    static var stitchLibraryMultiSelectEnabled: Bool {
        libraryMultiSelectEnabled(configured: Bundle.main.object(forInfoDictionaryKey: "StitchLibraryMultiSelectEnabled") as? Bool,
            isUITesting: AppConfig.isUITesting, arguments: ProcessInfo.processInfo.arguments)
    }
    static func libraryMultiSelectEnabled(configured: Bool?, isUITesting: Bool, arguments: [String]) -> Bool {
        if isUITesting && arguments.contains("-qaStitchLibraryMultiSelectOff") { return false }
        return configured ?? true
    }
}
