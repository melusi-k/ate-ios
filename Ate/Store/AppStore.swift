import Foundation
import SwiftData
import SwiftUI
import Observation

@Model
final class RecipeEntity {
    @Attribute(.unique) var id: String
    var createdAt: Double
    var position: Int
    var json: Data
    init(id: String, createdAt: Double, position: Int, json: Data) {
        self.id = id; self.createdAt = createdAt; self.position = position; self.json = json
    }
}

@Model
final class ShoppingEntity {
    @Attribute(.unique) var id: String
    var position: Int
    var json: Data
    init(id: String, position: Int, json: Data) { self.id = id; self.position = position; self.json = json }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@Observable
@MainActor
final class AppStore {
    var recipes: [RecipeCard] = []
    var shopping: [ShoppingItem] = []
    var path: [Route] = []
    var toast: Toast?
    var settings: AppSettings { didSet { saveDefaults(settings, key: "ate.settings.v1") } }
    var timerPrefs: TimerPrefs { didSet { saveDefaults(timerPrefs, key: "ate.timerprefs.v1") } }

    let backend: BackendService
    private let context: ModelContext?

    init(context: ModelContext?, backend: BackendService = AppConfig.makeBackend()) {
        self.context = context
        self.backend = backend
        settings = Self.loadDefaults(AppSettings.self, key: "ate.settings.v1") ?? AppSettings()
        timerPrefs = Self.loadDefaults(TimerPrefs.self, key: "ate.timerprefs.v1") ?? TimerPrefs()
        load()
    }

    // MARK: persistence
    private func load() {
        guard let context else { return }
        let dec = JSONDecoder()
        let r = (try? context.fetch(FetchDescriptor<RecipeEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        recipes = r.compactMap { try? dec.decode(RecipeCard.self, from: $0.json) }
        let s = (try? context.fetch(FetchDescriptor<ShoppingEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        shopping = s.compactMap { try? dec.decode(ShoppingItem.self, from: $0.json) }
    }

    private func persistRecipes() {
        guard let context else { return }
        try? context.delete(model: RecipeEntity.self)
        let enc = JSONEncoder()
        for (i, c) in recipes.enumerated() {
            if let d = try? enc.encode(c) { context.insert(RecipeEntity(id: c.id, createdAt: c.createdAt, position: i, json: d)) }
        }
        try? context.save()
    }

    private func persistShopping() {
        guard let context else { return }
        try? context.delete(model: ShoppingEntity.self)
        let enc = JSONEncoder()
        for (i, it) in shopping.enumerated() {
            if let d = try? enc.encode(it) { context.insert(ShoppingEntity(id: it.id, position: i, json: d)) }
        }
        try? context.save()
    }

    private func saveDefaults<T: Encodable>(_ v: T, key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func loadDefaults<T: Decodable>(_ t: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: toasts
    func show(_ message: String, error: Bool = false) {
        let t = Toast(message: message, isError: error)
        withAnimation { toast = t }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast?.id == t.id { withAnimation { toast = nil } }
        }
    }

    // MARK: recipes
    func recipe(_ id: String) -> RecipeCard? { recipes.first { $0.id == id } }

    func add(_ card: RecipeCard) {
        recipes.insert(RecipeLogic.normalize(card), at: 0)
        persistRecipes()
    }

    func update(_ card: RecipeCard) {
        guard let i = recipes.firstIndex(where: { $0.id == card.id }) else { return }
        recipes[i] = card
        persistRecipes()
    }

    func delete(_ id: String) {
        recipes.removeAll { $0.id == id }
        persistRecipes()
    }

    func clearLibrary() { recipes = []; persistRecipes() }

    func importJSON(_ data: Data) throws -> Int {
        let cards = try JSONDecoder().decode([RecipeCard].self, from: data)
        let res = RecipeLogic.importCards(cards, into: recipes)
        recipes = res.result
        persistRecipes()
        return res.added
    }

    func exportJSON() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(recipes)) ?? Data("[]".utf8)
    }

    // MARK: shopping
    func addToShopping(_ card: RecipeCard, factor: Double) {
        shopping = ShoppingLogic.merge(RecipeLogic.scaled(card, factor: factor).ingredients, source: card.title, into: shopping)
        persistShopping()
    }
    func addManual(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        shopping.append(ShoppingItem(name: n, quantity: 0, unit: "", aisle: ShoppingLogic.guessAisle(n)))
        persistShopping()
    }
    func toggle(_ id: String) {
        guard let i = shopping.firstIndex(where: { $0.id == id }) else { return }
        shopping[i].done.toggle(); persistShopping()
    }
    func removeItem(_ id: String) { shopping.removeAll { $0.id == id }; persistShopping() }
    func clearTicked() { shopping.removeAll { $0.done }; persistShopping() }
    func clearShopping() { shopping = []; persistShopping() }

    // MARK: deep links
    func handle(url: URL) {
        var slug: String?
        if url.scheme == "ate" {
            let parts = ([url.host ?? ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
            if parts.first == "r", parts.count > 1 { slug = parts[1] }
        } else if url.pathComponents.count >= 3, url.pathComponents[1] == "r" {
            slug = url.pathComponents[2]
        }
        if let slug { path = [.shared(slug)] } else { path = [.notFound] }
    }
}
