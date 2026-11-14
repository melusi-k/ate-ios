import Foundation

/// Ingredient-derived tags ("chicken", "pasta", "vegetarian"…) used by filter chips and auto-collections.
enum IngredientTags {
    /// tag → keywords matched as whole words in ingredient names (and the title for dish-type tags).
    static let table: [(tag: String, words: [String])] = [
        ("chicken", ["chicken", "drumstick", "drumsticks", "thigh", "thighs", "wings"]),
        ("beef", ["beef", "steak", "mince", "brisket", "oxtail", "boerewors"]),
        ("pork", ["pork", "bacon", "ham", "chorizo", "pancetta", "sausage", "sausages", "prosciutto", "pork belly", "pork chops", "spareribs", "spare ribs", "baby back ribs", "gammon", "guanciale"]),
        ("lamb", ["lamb", "mutton"]),
        ("fish", ["fish", "salmon", "tuna", "cod", "hake", "snoek", "trout", "sardines", "anchovies", "mackerel"]),
        ("seafood", ["prawn", "prawns", "shrimp", "mussels", "calamari", "squid", "crab", "lobster", "scallops"]),
        ("eggs", ["egg", "eggs"]),
        ("tofu", ["tofu", "tempeh", "seitan"]),
        ("beans", ["beans", "lentils", "chickpeas", "chickpea", "lentil"]),
        ("pasta", ["pasta", "spaghetti", "penne", "fusilli", "linguine", "macaroni", "lasagne", "lasagna", "tagliatelle", "noodles", "noodle", "orzo", "gnocchi"]),
        ("rice", ["rice", "risotto", "arborio", "basmati"]),
        ("potato", ["potato", "potatoes", "sweet potato"]),
        ("mushroom", ["mushroom", "mushrooms"]),
        ("cheese", ["cheese", "cheddar", "parmesan", "mozzarella", "feta", "halloumi", "ricotta"]),
        ("chocolate", ["chocolate", "cocoa"]),
    ]
    static let meat: Set<String> = ["chicken", "beef", "pork", "lamb", "fish", "seafood"]
    static let animal: Set<String> = meat.union(["eggs", "cheese"])
    static let dairyWords = ["milk", "butter", "cream", "yoghurt", "yogurt", "honey", "ghee", "buttermilk"]
    /// Category display order and fallback for recipes without identified protein ingredients.
    /// Mixed-protein primary selection uses measured amounts, not this order.
    static let mainOrder = ["chicken", "beef", "pork", "lamb", "fish", "seafood", "tofu", "beans", "pasta", "rice", "eggs", "potato", "mushroom", "cheese", "chocolate"]

    static func words(_ s: String) -> Set<String> {
        let lower = s.lowercased()
        var w = Set(lower.split { !$0.isLetter }.map(String.init))
        // two-word keywords
        for (_, ks) in table { for k in ks where k.contains(" ") && lower.contains(k) { w.insert(k) } }
        return w
    }

    static func tags(for r: RecipeCard) -> Set<String> {
        let ing = r.ingredients.map(\.name).joined(separator: " ")
        let w = words(ing + " " + r.title)
        var out = Set<String>()
        for (tag, ks) in table where ks.contains(where: w.contains) { out.insert(tag) }
        // Ingredient species override ambiguous cut words (e.g. turkey bacon,
        // beef sausage). Keep secondary proteins available as filters.
        let proteins = r.ingredients.compactMap { protein(in: $0.name) }
        if !proteins.isEmpty {
            out.subtract(meat)
            out.formUnion(proteins)
        }
        // Plant-based labels only when there are ingredients to judge.
        if !r.ingredients.isEmpty, out.isDisjoint(with: meat) {
            out.insert("vegetarian")
            let ingWords = words(ing)
            if out.isDisjoint(with: animal), !dairyWords.contains(where: ingWords.contains) { out.insert("vegan") }
        }
        // Respect explicit recipe tags too.
        for t in r.tags.map({ $0.lowercased() }) where ["vegetarian", "vegan"].contains(t) { out.insert(t) }
        if r.tags.map({ $0.lowercased() }).contains("vegan") { out.insert("vegetarian") }
        return out
    }

    /// Explicit species win over generic cuts such as wings, bacon or sausage.
    /// Bare ribs have no universal species: only named pork cuts imply Pork.
    static func protein(in name: String) -> String? {
        let tokens = words(name)
        let explicit: [(String, Set<String>)] = [
            ("pork", ["pork", "pig"]), ("beef", ["beef", "veal"]),
            ("lamb", ["lamb", "mutton"]), ("chicken", ["chicken"])
        ]
        for (tag, names) in explicit where !tokens.isDisjoint(with: names) { return tag }
        for (tag, names) in table where meat.contains(tag) && names.contains(where: tokens.contains) { return tag }
        return nil
    }

    /// A quantity is comparable only within its real dimension. Do not pretend
    /// that one wing, one rack or a volume of bacon has a known weight.
    static func proteinAmount(_ ingredient: Ingredient) -> (dimension: String, amount: Double)? {
        guard ingredient.quantity.isFinite, ingredient.quantity > 0 else { return nil }
        let unit = Units.canonical(ingredient.unit)
        let mass: [String: Double] = ["g": 1, "kg": 1000, "oz": 28.349523125, "lb": 453.59237]
        if let factor = mass[unit] {
            let amount = ingredient.quantity * factor
            return amount.isFinite ? ("mass", amount) : nil
        }
        guard !unit.isEmpty else { return nil }
        // The same unit can be compared without guessing density or portion size.
        return (unit, ingredient.quantity)
    }

    static func main(for r: RecipeCard) -> String? {
        let proteins = r.ingredients.compactMap { ingredient -> (tag: String, ingredient: Ingredient)? in
            protein(in: ingredient.name).map { ($0, ingredient) }
        }
        if let first = proteins.first {
            let amounts = proteins.compactMap { item -> (tag: String, dimension: String, amount: Double)? in
                proteinAmount(item.ingredient).map { (item.tag, $0.dimension, $0.amount) }
            }
            if amounts.count == proteins.count, Set(amounts.map(\.dimension)).count == 1 {
                var totals: [String: Double] = [:]
                for item in amounts { totals[item.tag, default: 0] += item.amount }
                if totals.values.allSatisfy(\.isFinite) {
                    // Equal quantities keep source ingredient order, never the old
                    // chicken-first category table priority.
                    return proteins.map(\.tag).reduce(first.tag) { best, tag in
                        (totals[tag] ?? 0) > (totals[best] ?? 0) ? tag : best
                    }
                }
            }
            return first.tag
        }
        let t = tags(for: r)
        return mainOrder.first(where: t.contains)
    }

    /// Tags present in the library, most common first (ties alphabetical).
    static func available(in recipes: [RecipeCard]) -> [String] {
        var count: [String: Int] = [:]
        for r in recipes { for t in tags(for: r) { count[t, default: 0] += 1 } }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Auto-collections: main ingredients used by at least `min` recipes.
    static func collections(in recipes: [RecipeCard], min: Int = 1) -> [String] {
        var count: [String: Int] = [:]
        for r in recipes { if let m = main(for: r) { count[m, default: 0] += 1 } }
        return mainOrder.filter { (count[$0] ?? 0) >= min }
    }
}

/// Multi-select library filter (chip row + sidebar collections). Persisted between launches.
struct RecipeFilter: Codable, Equatable {
    enum Servings: String, Codable, CaseIterable, Hashable {
        case few = "1–2", some = "3–4", many = "5+"
        func matches(_ n: Int) -> Bool {
            switch self { case .few: return n <= 2; case .some: return (3...4).contains(n); case .many: return n >= 5 }
        }
    }
    static let timeOptions = [15, 30, 60]

    /// Max total minutes (one of `timeOptions`); recipes with no time never match.
    var maxMinutes: Int?
    var origins: Set<RecipeOrigin> = []
    var servings: Set<Servings> = []
    var tags: Set<String> = []
    var favouritesOnly = false
    var collection: RecipeCollection?

    var activeCount: Int {
        (maxMinutes == nil ? 0 : 1) + origins.count + servings.count + tags.count + (favouritesOnly ? 1 : 0) + (collection == nil ? 0 : 1)
    }
    var isActive: Bool { activeCount > 0 }
    mutating func clear() { self = RecipeFilter() }

    static func origin(of r: RecipeCard) -> RecipeOrigin? {
        if let o = r.origin { return o }
        switch r.source {
        case .shared: return .shared
        case .photoGuess: return .photo
        case .jsonLD: return .link
        default: return r.sourceURL != nil ? .link : nil
        }
    }

    /// Within a group values are OR'd (e.g. chicken OR beef); groups are AND'd.
    func matches(_ r: RecipeCard, history: CookingHistory = .shared) -> Bool {
        if let m = maxMinutes { guard let t = r.timeMinutes, t > 0, t <= m else { return false } }
        if !origins.isEmpty { guard let o = Self.origin(of: r), origins.contains(o) else { return false } }
        if !servings.isEmpty, !servings.contains(where: { $0.matches(r.servings) }) { return false }
        if !tags.isEmpty, IngredientTags.tags(for: r).isDisjoint(with: tags) { return false }
        if favouritesOnly, !r.favorite { return false }
        switch collection {
        case .quick?: guard let t = r.timeMinutes, t > 0, t < 30 else { return false }
        case .favourites?: if !r.favorite { return false }
        case .recentlyCooked?: if r.lastCookedAt == nil { return false }
        case .cookedMeals?: if !history.events.values.contains(where: { $0.contains(r.id) }) { return false }
        case .ingredient(let t)?: if IngredientTags.main(for: r) != t && !IngredientTags.tags(for: r).contains(t) { return false }
        case .recentlyAdded?, nil: break
        }
        return true
    }

    /// Filter + collection ordering + text search.
    func apply(_ recipes: [RecipeCard], query: String = "", history: CookingHistory = .shared) -> [RecipeCard] {
        let base = recipes.filter { matches($0, history: history) && RecipeLogic.matches($0, query: query) }
        switch collection {
        case .recentlyAdded?:
            return Array(base.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id < $1.id
            }.prefix(20))
        case .cookedMeals?:
            return base.sorted { lhs, rhs in
                let a = history.events.filter { $0.value.contains(lhs.id) }.keys.compactMap { history.date(for: $0) }.max() ?? .distantPast
                let b = history.events.filter { $0.value.contains(rhs.id) }.keys.compactMap { history.date(for: $0) }.max() ?? .distantPast
                if a != b { return a > b }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .recentlyCooked?:
            return base.sorted {
                let a = $0.lastCookedAt ?? 0, b = $1.lastCookedAt ?? 0
                if a != b { return a > b }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id < $1.id
            }
        default: return base
        }
    }

    static let key = "ate.libraryFilter.v1"
    static func load(_ d: UserDefaults = .standard) -> RecipeFilter {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(RecipeFilter.self, from: $0) } ?? RecipeFilter()
    }
    func save(_ d: UserDefaults = .standard) { d.set(try? JSONEncoder().encode(self), forKey: Self.key) }
}
