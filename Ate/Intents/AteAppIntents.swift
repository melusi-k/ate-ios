import Intents
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
    /// Local cover file (App Group / app container) for real thumbnails in Spotlight and Shortcuts (C-FIX-05).
    var coverURL: URL?

    init(_ r: RecipeCard) {
        coverURL = RecipeAppEntity.coverURL(r)
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
                                     image: coverURL.map { .init(url: $0) } ?? .init(systemName: "fork.knife"),
                                     synonyms: Self.synonyms(title: title).map { "\($0)" })
    }

    /// Key words from the title ("rice", "chicken", "chicken and rice") so a partial spoken name resolves.
    static func synonyms(title: String) -> [String] {
        let words = RecipeMatcher.tokens(title).filter { $0.count >= 3 }
        var out = words
        if words.count >= 2 { out.append(words.suffix(2).joined(separator: " ")); out.append(words.suffix(2).joined(separator: " and ")) }
        let full = RecipeMatcher.norm(title).lowercased()
        var seen = Set<String>()
        return out.filter { $0 != full && seen.insert($0).inserted }
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let a = CSSearchableItemAttributeSet(contentType: .content)
        a.title = title
        a.displayName = title
        a.contentDescription = ([cuisine, minutes.map { "\($0) min" }].compactMap { $0 } + ingredients).joined(separator: " · ")
        a.keywords = ingredients + [cuisine].compactMap { $0 }
        a.thumbnailURL = coverURL
        return a
    }

    static func coverURL(_ r: RecipeCard) -> URL? {
        guard let f = WidgetSnapshotBuilder.coverFile(r) else { return nil }
        for u in [WidgetCovers.url(f), CoverStore.url(f)].compactMap({ $0 }) where FileManager.default.fileExists(atPath: u.path) { return u }
        return nil
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
        // Ranked fuzzy match; several near matches come back together so Siri asks which one.
        let hits = RecipeMatcher.rank(all, query: string)
        let pool = RecipeMatcher.isConfident(hits) ? Array(hits.prefix(1)) : Array(RecipeMatcher.nearTop(hits).prefix(5))
        return pool.map { RecipeAppEntity($0.recipe) }
    }
    func suggestedEntities() async throws -> [RecipeAppEntity] {
        RecipeEntityQuery.suggestions(await IntentStore.recipes).map(RecipeAppEntity.init)
    }

    /// C-FIX-05: suggested entities expand the parameterised "Cook \(recipe)" App Shortcut into one Spotlight
    /// action PER recipe (the "every recipe as a fork-and-knife action" clutter). Cap at the top 3 favourites
    /// (falling back to most recently cooked). Trade-off: Siri voice only knows these 3 names for "Cook X in ate";
    /// "Start cook mode in ate" still asks which recipe and resolves any name through entities(matching:).
    static func suggestions(_ all: [RecipeCard], limit: Int = 3) -> [RecipeCard] {
        let favs = all.filter(\.favorite).sorted { ($0.lastCookedAt ?? 0) > ($1.lastCookedAt ?? 0) }
        let rest = all.filter { !$0.favorite }.sorted { ($0.lastCookedAt ?? 0, $0.createdAt) > ($1.lastCookedAt ?? 0, $1.createdAt) }
        return Array((favs + rest).prefix(limit))
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
}

// MARK: intents

struct OpenRecipeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open recipe"
    @Parameter(title: "Recipe") var target: RecipeAppEntity
    init() {}
    init(target: RecipeAppEntity) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppStore.current?.handle(url: WidgetLinks.recipe(target.id))
        QAProbe.shared.lastIntent = "open"
        return .result(dialog: "Opening \(target.title).")
    }
}

struct StartCookModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start cook mode"
    static let description = IntentDescription("Opens a recipe in ate's hands-free cook mode. Without a recipe, uses tonight's pick.")
    static let openAppWhenRun = true
    @Parameter(title: "Recipe") var recipe: RecipeAppEntity?
    /// Typed name (Shortcuts/tests). Resolved with RecipeMatcher; never falls back to an unrelated recipe.
    var recipeName: String?
    init() {}
    init(recipe: RecipeAppEntity?) { self.recipe = recipe }
    init(name: String) { self.recipeName = name }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = AppStore.current else { return .result(dialog: "Open ate first.") }
        var chosen = recipe
        if chosen == nil, let n = recipeName, !n.trimmingCharacters(in: .whitespaces).isEmpty {
            let hits = RecipeMatcher.rank(store.recipes, query: n)
            if hits.isEmpty { return .result(dialog: "I couldn't find a recipe called \(n) in ate.") }
            if RecipeMatcher.isConfident(hits) || RecipeMatcher.nearTop(hits).count == 1 {
                chosen = RecipeAppEntity(hits[0].recipe)
            } else {
                chosen = try await $recipe.requestDisambiguation(among: RecipeMatcher.nearTop(hits).prefix(5).map { RecipeAppEntity($0.recipe) },
                                                                dialog: "Which recipe did you mean?")
            }
        }
        let id = chosen?.id ?? WidgetSnapshotBuilder.pick(recipes: store.recipes, health: WidgetBridge.lastHealthState)?.recipeID
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
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<RecipeAppEntity?> & ProvidesDialog & ShowsSnippetView {
        let recipes = AppStore.current?.recipes ?? []
        guard let p = WidgetSnapshotBuilder.pick(recipes: recipes, health: WidgetBridge.lastHealthState),
              var r = recipes.first(where: { $0.id == p.recipeID }) else {
            return .result(value: nil, dialog: "Save a recipe to ate first, then I can pick one for tonight.", view: SnippetEmpty(text: "No recipes yet"))
        }
        await SnippetCovers.prepare([r]); r = SnippetCovers.fresh(r)
        QAProbe.shared.lastIntent = "pick:\(r.title)"
        BetaQA.shared.pass("A-INTENT-03", note: "Tonight's pick: \(r.title)")
        return .result(value: RecipeAppEntity(r), dialog: "\(SiriAnswers.pickLine(title: r.title, health: p.healthTitle, why: p.why))",
                       view: PickSnippet(recipe: r, why: p.why))
    }
}

struct ImportRecipeFromURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Add recipe from link"
    static let description = IntentDescription("Turns a recipe page, reel or video link into an ate recipe card.")
    static let openAppWhenRun = true
    @Parameter(title: "Link") var url: URL
    init() {}
    init(url: URL) { self.url = url }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedInbox.push(.init(url: url.absoluteString))
        AppStore.current?.checkInbox()
        QAProbe.shared.lastIntent = "import"
        return .result(dialog: "Adding that link to ate.")
    }
}

/// System search schema: "Search ate for tripe" from Siri / Spotlight opens Library results.
@available(iOS 18.0, *)
@AppIntent(schema: .system.search)
struct SearchRecipesIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]
    var criteria: StringSearchCriteria
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        // Siri sometimes routes "Cook Rice in ate" here with the whole sentence as the term.
        let (verb, q) = RecipeMatcher.cleanQuery(criteria.term)
        guard let store = AppStore.current else { return .result(dialog: "Open ate first.") }
        let hits = RecipeMatcher.rank(store.recipes, query: q)
        if let v = verb, [.cook, .make, .start, .open].contains(v), RecipeMatcher.isConfident(hits) {
            let r = hits[0].recipe
            if v == .open { store.handle(url: WidgetLinks.recipe(r.id)); QAProbe.shared.lastIntent = "open"; return .result(dialog: "Opening \(r.title).") }
            store.handle(url: WidgetLinks.cook(r.id)); QAProbe.shared.lastIntent = "cook"
            return .result(dialog: "Starting cook mode for \(r.title).")
        }
        store.search(q)
        QAProbe.shared.lastIntent = "search:\(q)"
        BetaQA.shared.pass("A-INTENT-04", note: "Searched for \(q)")
        let n = store.recipes.filter { RecipeLogic.matches($0, query: q) }.count
        if q.isEmpty { return .result(dialog: "Here's your ate library.") }
        return .result(dialog: n == 0 ? "No ate recipes match \(q)." : "Found \(n) ate recipe\(n == 1 ? "" : "s") for \(q).")
    }
}

// MARK: Journal schema (ate's own journal in Insights)

@available(iOS 18.0, *)
@AppEntity(schema: .journal.entry)
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
        self.mediaItems = e.mediaFileNames.map { IntentFile(fileURL: JournalStore.mediaURL($0)) }
    }
}

/// "Save a journal entry in ate": writes to ate's Insights journal (never Apple's Journal app).
@available(iOS 18.0, *)
@AppIntent(schema: .journal.createEntry)
struct CreateAteJournalEntryIntent {
    static let title: LocalizedStringResource = "New journal entry"
    var message: AttributedString
    var title: String?
    var entryDate: Date?
    var location: CLPlacemark?
    var mediaItems: [IntentFile]

    @MainActor func perform() async throws -> some ReturnsValue<AteJournalEntryEntity> {
        let text = String(message.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw JournalIntentError.empty }
        if JournalTextGuard.looksLikeImagePrompt(text) { throw JournalIntentError.imagePrompt }
        let state = WidgetBridge.lastHealthState ?? .balanced
        let place = location.map { [$0.name, $0.locality].compactMap { $0 }.removingDuplicates().joined(separator: ", ") }
        var media: [(data: Data, ext: String)] = []
        for f in mediaItems { media.append((f.data, f.filename.split(separator: ".").last.map(String.init) ?? "jpg")) }
        let saved = JournalStore.shared.saveFromIntent(title: title, text: text, date: entryDate, state: state,
                                                       locationName: place?.isEmpty == false ? place : nil,
                                                       latitude: location?.location?.coordinate.latitude, longitude: location?.location?.coordinate.longitude,
                                                       media: media)
        QAProbe.shared.lastIntent = "journal"
        BetaQA.shared.pass("A-INTENT-05", note: "Journal entry saved from Siri/Shortcuts")
        if let e = saved { return .result(value: AteJournalEntryEntity(e)) }
        return .result(value: AteJournalEntryEntity(id: UUID().uuidString, title: title, message: message, entryDate: entryDate ?? Date()))
    }
}

enum JournalIntentError: Error, CustomLocalizedStringResourceConvertible {
    case empty, imagePrompt, notFound
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .empty: return "There's nothing to save. Say or type what you'd like in your Ate journal."
        case .imagePrompt: return "That looks like an image prompt, not a journal entry, so Ate didn't save it."
        case .notFound: return "That journal entry isn't in Ate any more."
        }
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

/// Shortcuts: "Open journal entry" opens one entry's detail view from the journal navigation flow.
@available(iOS 18.0, *)
struct OpenJournalEntryIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open journal entry"
    static let description = IntentDescription("Opens an entry from your Ate journal.")
    @Parameter(title: "Entry") var target: AteJournalEntryEntity
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        guard JournalStore.shared.entry(target.id) != nil else { throw JournalIntentError.notFound }
        AppStore.current?.openJournalEntry(target.id)
        QAProbe.shared.lastIntent = "openJournal"
        BetaQA.shared.pass("C-JRN-06", note: "Opened a journal entry from Shortcuts")
        return .result()
    }
}

// MARK: App Shortcuts (Siri phrases; available with no setup)

struct AteShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCookModeIntent(), phrases: [
            "Start cook mode in \(.applicationName)",
            "Start cook mode for \(\.$recipe) in \(.applicationName)",
            "Cook \(\.$recipe) in \(.applicationName)",
            "Cook \(\.$recipe) with \(.applicationName)",
            "Make \(\.$recipe) with \(.applicationName)",
            "Open \(\.$recipe) in \(.applicationName)",
            "Start cook mode for \(\.$recipe) with \(.applicationName)",
            "Make \(\.$recipe) in \(.applicationName)",
        ], shortTitle: "Cook mode", systemImageName: "frying.pan")
        AppShortcut(intent: AddToShoppingListIntent(), phrases: [
            "Add to my \(.applicationName) list",
        ], shortTitle: "Add to list", systemImageName: "basket")
        AppShortcut(intent: TonightsPickIntent(), phrases: [
            "What's tonight's pick in \(.applicationName)",
            "What should I cook tonight with \(.applicationName)",
            "Tonight's pick in \(.applicationName)",
            "What's for dinner in \(.applicationName)",
            "What's for dinner with \(.applicationName)",
            "What should I cook tonight in \(.applicationName)",
            "\(.applicationName) tonight's pick",
        ], shortTitle: "Tonight's pick", systemImageName: "sparkles")
        AppShortcut(intent: ShoppingListSnippetIntent(), phrases: [
            "What's on my \(.applicationName) shopping list",
            "What's on my \(.applicationName) list",
        ], shortTitle: "Shopping list", systemImageName: "checklist")
        AppShortcut(intent: TimerStatusIntent(), phrases: [
            "How long left on my \(.applicationName) timer",
            "How long is left on my \(.applicationName) timer",
        ], shortTitle: "Time left", systemImageName: "hourglass")
        AppShortcut(intent: QuickRecipesIntent(), phrases: [
            "What can I cook in under 30 minutes with \(.applicationName)",
            "Quick recipes in \(.applicationName)",
        ], shortTitle: "Quick recipes", systemImageName: "bolt")
        AppShortcut(intent: KitchenTimerIntent(), phrases: [
            "Start a kitchen timer in \(.applicationName)",
        ], shortTitle: "Kitchen timer", systemImageName: "timer")
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

extension AteShortcuts {
    /// Mirror of the registered phrases (AppShortcut doesn't expose them) for the Beta page's Siri row. Keep in sync; a test checks counts.
    static let phraseCatalog: [(title: String, phrases: [String])] = [
        ("Cook mode", ["Start cook mode in ate", "Start cook mode for <recipe> in ate", "Cook <recipe> in ate", "Cook <recipe> with ate",
                       "Make <recipe> with ate", "Open <recipe> in ate", "Start cook mode for <recipe> with ate", "Make <recipe> in ate"]),
        ("Add to list", ["Add to my ate list"]),
        ("Tonight's pick", ["What's tonight's pick in ate", "What should I cook tonight with ate", "Tonight's pick in ate",
                            "What's for dinner in ate", "What's for dinner with ate", "What should I cook tonight in ate", "ate tonight's pick"]),
        ("Shopping list", ["What's on my ate shopping list", "What's on my ate list"]),
        ("Time left", ["How long left on my ate timer", "How long is left on my ate timer"]),
        ("Quick recipes", ["What can I cook in under 30 minutes with ate", "Quick recipes in ate"]),
        ("Kitchen timer", ["Start a kitchen timer in ate"]),
        ("Stop timer", ["Stop my ate timer"]),
        ("Add from link", ["Add a recipe link to ate"]),
        ("Add recipe", ["Add a recipe in ate"]),
    ]
    @MainActor static var diagnostics: String {
        let meta = Bundle.main.url(forResource: "Metadata", withExtension: "appintents") != nil
        let alt = (Bundle.main.object(forInfoDictionaryKey: "INAlternativeAppNames") as? [[String: Any]])?
            .compactMap { $0["INAlternativeAppName"] as? String } ?? []
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "?"
        let bundle = Bundle.main.bundleIdentifier ?? "?"
        // INPreferences.siriLanguageCode() requires the Siri entitlement and can terminate
        // unsigned/sideloaded builds. Keep diagnostics safe when that capability is absent.
        let siriLang = "Not queried (requires Siri entitlement)"
        var lines = ["Siri: \(phraseCatalog.count)/10 shortcuts · \(phraseCatalog.map(\.phrases.count).reduce(0, +)) phrases",
                     "App Intents metadata: \(meta ? "OK" : "MISSING (re-sign dropped Metadata.appintents)")",
                     "App name: \(name) · alternatives: \(alt.isEmpty ? "none" : alt.joined(separator: ", "))",
                     "Recipes for Siri: \(IntentStoreSnapshot.count) (voice names: top \(RecipeEntityQuery.suggestions(AppStore.current?.recipes ?? []).count))",
                     "Bundle ID: \(bundle)\(bundle == "com.melusik.ate" ? "" : " (re-signed; Siri registers phrases per bundle ID, so this is a new app to Siri)")",
                     "Siri language: \(siriLang)\(siriLang.hasPrefix("en") ? "" : " (phrases are English only; set Siri to English)")",
                     "If voice still fails while Shortcuts works: open Ate once, wait a minute, then try. Sideloadly/free-team installs often never get their App Shortcut phrases indexed by Siri; install via SideStore or Xcode (or TestFlight/App Store) for voice."]
        lines += phraseCatalog.map { "\($0.title): " + $0.phrases.joined(separator: " | ") }
        return lines.joined(separator: "\n")
    }
}

@MainActor enum IntentStoreSnapshot { static var count: Int { AppStore.current?.recipes.count ?? 0 } }
