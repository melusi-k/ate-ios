import AppIntents
import Foundation

/// Shared, side-effect-free matching rules for the Siri recipe tools.
/// A close match is never treated as a selection; the skill must ask the person to choose.
enum RecipeToolSearch {
    static func matchingTitles(in recipes: [RecipeCard], query: String, limit: Int = 5) -> [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let hits = RecipeMatcher.rank(recipes, query: query)
        let candidates = RecipeMatcher.isConfident(hits) ? Array(hits.prefix(1)) : Array(RecipeMatcher.nearTop(hits).prefix(limit))
        return candidates.map { $0.recipe.title }
    }

    static func confidentMatch(in recipes: [RecipeCard], query: String) -> RecipeCard? {
        let hits = RecipeMatcher.rank(recipes, query: query)
        guard RecipeMatcher.isConfident(hits) else { return nil }
        return hits.first?.recipe
    }

    static func ambiguousTitles(in recipes: [RecipeCard], query: String, limit: Int = 5) -> [String] {
        let hits = RecipeMatcher.rank(recipes, query: query)
        guard !hits.isEmpty, !RecipeMatcher.isConfident(hits) else { return [] }
        return RecipeMatcher.nearTop(hits).prefix(limit).map { $0.recipe.title }
    }
}

/// Read-only tool for finding saved Ate recipes. Recipe titles are private library content,
/// so the device must be authenticated before Siri can retrieve them.
@available(iOS 27.3, *)
@AppIntent(.tool)
struct FindSavedRecipesToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Find saved recipes"
    static let description = IntentDescription("Searches the recipes saved in Ate and returns matching recipe titles for the person to choose from.")
    static let openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(
        title: "Search terms",
        description: "Words from the saved recipe title, ingredients, or cuisine",
        requestValueDialog: "What recipe would you like to find in Ate?"
    )
    var query: String

    init() {}

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        guard let store = AppStore.current else {
            return .result(value: [], dialog: "Open Ate first so I can search your saved recipes.")
        }

        let titles = RecipeToolSearch.matchingTitles(in: store.recipes, query: query)
        guard !titles.isEmpty else {
            return .result(value: [], dialog: "I couldn't find a saved recipe matching \(query) in Ate.")
        }

        let summary = ListFormatter.localizedString(byJoining: titles)
        let dialog = titles.count == 1
            ? "I found one saved recipe: \(titles[0])."
            : "I found these saved recipes: \(summary). Which one do you mean?"
        return .result(value: titles, dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// Starts cook mode only for a recipe the person has identified by name.
/// Unlike the existing Shortcuts intent, this tool never falls back to a health-informed dinner pick.
@available(iOS 27.3, *)
@AppIntent(.tool)
struct StartCookModeForRecipeToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Start cook mode for a saved recipe"
    static let description = IntentDescription("Starts Ate cook mode for one specific saved recipe selected by the person.")
    static let openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(
        title: "Recipe",
        description: "The exact saved Ate recipe the person selected",
        requestValueDialog: "Which saved recipe would you like to cook?"
    )
    var recipeName: String

    init() {}

    init(recipeName: String) {
        self.recipeName = recipeName
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = AppStore.current else {
            return .result(dialog: "Open Ate first so I can start cook mode.")
        }

        guard !recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "Tell me which saved recipe you want to cook.")
        }

        let hits = RecipeMatcher.rank(store.recipes, query: recipeName)
        guard !hits.isEmpty else {
            return .result(dialog: "I couldn't find a saved recipe called \(recipeName) in Ate. I haven't started cook mode.")
        }

        guard RecipeMatcher.isConfident(hits), let selected = store.recipe(hits[0].recipe.id) else {
            let options = RecipeToolSearch.ambiguousTitles(in: store.recipes, query: recipeName)
            let choices = ListFormatter.localizedString(byJoining: options)
            return .result(dialog: options.isEmpty
                ? "I couldn't confidently identify \(recipeName). Which saved recipe did you mean?"
                : "I found several possible matches: \(choices). Which one did you mean? I haven't started cook mode.")
        }

        store.handle(url: WidgetLinks.cook(selected.id))
        QAProbe.shared.lastIntent = "cookTool"
        return .result(dialog: "Starting cook mode for \(selected.title).")
    }
}
