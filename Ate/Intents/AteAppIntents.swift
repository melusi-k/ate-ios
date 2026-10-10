import AppIntents
import CoreLocation
import CoreSpotlight
import Foundation

// MARK: entities

/// A saved recipe for Siri, Shortcuts, Spotlight and Apple Intelligence. (The SwiftData model is `RecipeEntity`.)
struct RecipeAppEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Recipe", numericFormat: "\(placeholder: .int) recipes")
    static let defaultQuery = RecipeEntityQuery()

    var id: String
    @Property(title: "Title") var title: String
    @Property(title: "Minutes") var minutes: Int?
    @Property(title: "Cuisine") var cuisine: String?
    @Property(title: "Favourite") var favorite: Bool
    var ingredients: [String] = []

    init(_ r: RecipeCard) {
        id = r.id
        title = r.title
        minutes = r.timeMinutes
        cuisine = r.cuisine
        favorite = r.favorite
        ingredients = r.ingredients.prefix(8).map(\.name)
    }

    var displayRepresentation: DisplayRepresentation {
        var sub: [String] = []
        if let m = minutes { sub.append("\(m) min") }
        if let c = cuisine { sub.append(c) }
        return DisplayRepresentation(title: "\(title)", subtitle: sub.isEmpty ? nil : "\(sub.joined(separator: " · "))",
                                     image: .init(systemName: "fork.knife"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let a = CSSearchableItemAttributeSet(contentType: .content)
        a.title = title
        a.displayName = title
        a.contentDescription = ([cuisine, minutes.map { "\($0) min" }].compactMap { $0 } + ingredients).joined(separator: " · ")
        a.keywords = ingredients + [cuisine].compactMap { $0 }
        return a
    }
}

@MainActor
enum IntentStore {
    static var recipes: [RecipeCard] { AppStore.current?.recipes ?? [] }
}

struct RecipeEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RecipeAppEntity] {
        let all = await IntentStore.recipes
        return identifiers.compactMap { id in all.first { $0.id == id }.map(RecipeAppEntity.init) }
    }
    func entities(matching string: String) async throws -> [RecipeAppEntity] {
        let all = await IntentStore.recipes
        return RecipeFilter().apply(all, query: string).prefix(20).map(RecipeAppEntity.init)
    }
    func suggestedEntities() async throws -> [RecipeAppEntity] {
        let all = await IntentStore.recipes
        let favs = all.filter(\.favorite)
        return (favs + all.filter { !$0.favorite }).prefix(15).map(RecipeAppEntity.init)
    }
}

/// A shopping item name. Its suggestions make "Add milk to my ate list" work as one Siri phrase.
struct GroceryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shopping item"
    static let defaultQuery = GroceryQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
    init(_ name: String) { id = name }

    static let common = ["milk", "eggs", "bread", "butter", "onions", "tomatoes", "garlic", "potatoes", "rice", "maize meal",
                         "flour", "sugar", "salt", "oil", "chicken", "beef", "mince", "cheese", "yoghurt", "carrots",
                         "spinach", "cabbage", "peppers", "lemons", "bananas", "apples", "tea", "coffee", "beans", "pasta"]
}

struct GroceryQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GroceryEntity] { identifiers.map(GroceryEntity.init) }
    func entities(matching string: String) async throws -> [GroceryEntity] {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        let hits = GroceryEntity.common.filter { $0.localizedCaseInsensitiveContains(s) }
        return ([s.lowercased()] + hits.filter { $0 != s.lowercased() }).map(GroceryEntity.init)
    }
    func suggestedEntities() async throws -> [GroceryEntity] {
        let recent = await MainActor.run { AppStore.current?.shopping.map { $0.name.lowercased() } ?? [] }
        var seen = Set<String>(); var out: [String] = []
        for n in recent + GroceryEntity.common where seen.insert(n).inserted { out.append(n) }
        return out.prefix(60).map(GroceryEntity.init)
    }
}

// MARK: intents

struct OpenRecipeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open recipe"
    @Parameter(title: "Recipe") var target: RecipeAppEntity
    init() {}
    init(target: RecipeAppEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        AppStore.current?.handle(url: WidgetLinks.recipe(target.id))
        QAProbe.shared.lastIntent = "open"
        return .result()
    }
}

struct StartCookModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start cook mode"
    static let description = IntentDescription("Opens a recipe in ate's hands-free cook mode. Without a recipe, uses tonight's pick.")
    static let openAppWhenRun = true
    @Parameter(title: "Recipe") var recipe: RecipeAppEntity?
    init() {}
    init(recipe: RecipeAppEntity?) { self.recipe = recipe }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = AppStore.current else { return .result(dialog: "Open ate first.") }
        let id = recipe?.id ?? WidgetSnapshotBuilder.pick(recipes: store.recipes, health: WidgetBridge.lastHealthState)?.recipeID
        guard let id, let r = store.recipe(id) else {
            return .result(dialog: store.recipes.isEmpty ? "Your ate library is empty. Add a recipe first." : "I couldn't find that recipe.")
        }
        store.handle(url: WidgetLinks.cook(id))
        QAProbe.shared.lastIntent = "cook"
        return .result(dialog: "Starting cook mode for \(r.title).")
    }
}

struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to shopping list"
    static let description = IntentDescription("Adds an item to your ate shopping list.")
    @Parameter(title: "Item", requestValueDialog: "What should I add to your ate list?") var item: GroceryEntity
    init() {}
    init(item: String) { self.item = GroceryEntity(item) }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .result(dialog: "Nothing to add.") }
        let pretty = name.prefix(1).uppercased() + name.dropFirst()
        if let a = IntentRelay.addShopping { a(pretty) } else { WidgetInbox.addItem(pretty) }
        QAProbe.shared.lastIntent = "add:\(pretty)"
        BetaQA.shared.pass("A-INTENT-02", note: "Added \(pretty) via Siri/Shortcuts")
        return .result(dialog: "Added \(pretty) to your ate list.")
    }
}

struct TonightsPickIntent: AppIntent {
    static let title: LocalizedStringResource = "Tonight's pick"
    static let description = IntentDescription("Suggests one recipe from your library that fits your day.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<RecipeAppEntity?> & ProvidesDialog {
        let recipes = AppStore.current?.recipes ?? []
        guard let p = WidgetSnapshotBuilder.pick(recipes: recipes, health: WidgetBridge.lastHealthState),
              let r = recipes.first(where: { $0.id == p.recipeID }) else {
            return .result(value: nil, dialog: "Save a recipe to ate first, then I can pick one for tonight.")
        }
        QAProbe.shared.lastIntent = "pick:\(r.title)"
        BetaQA.shared.pass("A-INTENT-03", note: "Tonight's pick: \(r.title)")
        let lead = p.healthTitle.map { "It's a \($0.lowercased()), so " } ?? ""
        return .result(value: RecipeAppEntity(r), dialog: "\(lead)tonight's pick is \(r.title). \(p.why).")
    }
}

struct ImportRecipeFromURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Add recipe from link"
    static let description = IntentDescription("Turns a recipe page, reel or video link into an ate recipe card.")
    static let openAppWhenRun = true
    @Parameter(title: "Link") var url: URL
    init() {}
    init(url: URL) { self.url = url }
    @MainActor func perform() async throws -> some IntentResult {
        SharedInbox.push(.init(url: url.absoluteString))
        AppStore.current?.checkInbox()
        QAProbe.shared.lastIntent = "import"
        return .result()
    }
}

/// System search schema: "Search ate for tripe" from Siri / Spotlight opens Library results.
@available(iOS 18.0, *)
@AssistantIntent(schema: .system.search)
struct SearchRecipesIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria
    @MainActor func perform() async throws -> some IntentResult {
        AppStore.current?.search(criteria.term)
        QAProbe.shared.lastIntent = "search:\(criteria.term)"
        BetaQA.shared.pass("A-INTENT-04", note: "Searched for \(criteria.term)")
        return .result()
    }
}

// MARK: Journal schema (ate's own journal in Insights)

@available(iOS 18.0, *)
@AssistantEntity(schema: .journal.entry)
struct AteJournalEntryEntity {
    struct Query: EntityStringQuery {
        func entities(for identifiers: [AteJournalEntryEntity.ID]) async throws -> [AteJournalEntryEntity] {
            await MainActor.run { JournalStore.shared.entries().filter { identifiers.contains($0.id) }.map(AteJournalEntryEntity.init) }
        }
        func entities(matching string: String) async throws -> [AteJournalEntryEntity] {
            await MainActor.run {
                JournalStore.shared.entries().filter { $0.text.localizedCaseInsensitiveContains(string) || $0.prompt.localizedCaseInsensitiveContains(string) }
                    .prefix(20).map(AteJournalEntryEntity.init)
            }
        }
        func suggestedEntities() async throws -> [AteJournalEntryEntity] {
            await MainActor.run { JournalStore.shared.entries().prefix(10).map(AteJournalEntryEntity.init) }
        }
    }
    static let defaultQuery = Query()

    var displayRepresentation: AppIntents.DisplayRepresentation {
        DisplayRepresentation(title: "\(title ?? "Journal entry")", subtitle: "\(entryDate?.formatted(date: .abbreviated, time: .omitted) ?? "")")
    }

    let id: String
    var title: String?
    var message: AttributedString?
    var mediaItems: [IntentFile]
    var entryDate: Date?
    var location: CLPlacemark?

    init(id: String, title: String?, message: AttributedString?, entryDate: Date?) {
        self.id = id; self.title = title; self.message = message; self.mediaItems = []; self.entryDate = entryDate; self.location = nil
    }
    @MainActor init(_ e: JournalEntry) {
        self.init(id: e.id, title: e.prompt, message: AttributedString(e.text), entryDate: e.createdAt)
    }
}

/// "Save a journal entry in ate": writes to ate's Insights journal (never Apple's Journal app).
@available(iOS 18.0, *)
@AssistantIntent(schema: .journal.createEntry)
struct CreateAteJournalEntryIntent {
    var message: AttributedString
    var title: String?
    var entryDate: Date?
    var location: CLPlacemark?
    var mediaItems: [IntentFile]

    @MainActor func perform() async throws -> some ReturnsValue<AteJournalEntryEntity> {
        let text = String(message.characters)
        let state = WidgetBridge.lastHealthState ?? .balanced
        _ = JournalStore.shared.save(prompt: title ?? "Note from Siri", text: text, state: state, recipeIDs: [])
        QAProbe.shared.lastIntent = "journal"
        BetaQA.shared.pass("A-INTENT-05", note: "Journal entry saved from Siri/Shortcuts")
        if let e = JournalStore.shared.entries().first { return .result(value: AteJournalEntryEntity(e)) }
        return .result(value: AteJournalEntryEntity(id: UUID().uuidString, title: title, message: message, entryDate: entryDate ?? Date()))
    }
}

// MARK: App Shortcuts (Siri phrases; available with no setup)

struct AteShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCookModeIntent(), phrases: [
            "Start cook mode in \(.applicationName)",
            "Start cook mode for \(\.$recipe) in \(.applicationName)",
            "Cook \(\.$recipe) with \(.applicationName)",
        ], shortTitle: "Cook mode", systemImageName: "frying.pan")
        AppShortcut(intent: AddToShoppingListIntent(), phrases: [
            "Add \(\.$item) to my \(.applicationName) list",
            "Add \(\.$item) to my \(.applicationName) shopping list",
            "Add to my \(.applicationName) list",
        ], shortTitle: "Add to list", systemImageName: "basket")
        AppShortcut(intent: TonightsPickIntent(), phrases: [
            "What's tonight's pick in \(.applicationName)",
            "What should I cook tonight with \(.applicationName)",
        ], shortTitle: "Tonight's pick", systemImageName: "sparkles")
        AppShortcut(intent: KitchenTimerIntent(), phrases: [
            "Start a kitchen timer in \(.applicationName)",
        ], shortTitle: "Kitchen timer", systemImageName: "timer")
        AppShortcut(intent: PauseTimersIntent(), phrases: [
            "Pause my \(.applicationName) timer",
        ], shortTitle: "Pause timer", systemImageName: "pause.circle")
        AppShortcut(intent: ResumeTimersIntent(), phrases: [
            "Resume my \(.applicationName) timer",
        ], shortTitle: "Resume timer", systemImageName: "play.circle")
        AppShortcut(intent: StopTimersIntent(), phrases: [
            "Stop my \(.applicationName) timer",
        ], shortTitle: "Stop timer", systemImageName: "stop.circle")
        AppShortcut(intent: ImportRecipeFromURLIntent(), phrases: [
            "Add a recipe link to \(.applicationName)",
        ], shortTitle: "Add from link", systemImageName: "link")
        AppShortcut(intent: QuickAddIntent(), phrases: [
            "Add a recipe in \(.applicationName)",
        ], shortTitle: "Add recipe", systemImageName: "plus.circle")
    }
}
