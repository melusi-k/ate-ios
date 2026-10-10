import Foundation

struct Ingredient: Codable, Hashable {
    var name: String
    var quantity: Double
    var unit: String
    var notes: String?
}

struct Step: Codable, Hashable {
    var order: Int
    var instruction: String
    var timeSeconds: Int?
}

/// Where a recipe card came from (provenance). Unknown raw values (and pre-v1.3 recipes) decode as `.unknown`.
enum RecipeSource: String, Codable, Hashable, CaseIterable {
    case appleIntelligence, jsonLD, mock, manual, shared, imported, unknown
    init(from decoder: Decoder) throws {
        self = RecipeSource(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .unknown
    }
    /// Badge text; nil when no badge should be shown.
    var badge: String? {
        switch self {
        case .appleIntelligence: return "Made with Apple Intelligence"
        case .jsonLD: return "Imported from page data"
        case .mock: return "Demo"
        case .shared: return "Shared with you"
        case .imported: return "Imported"
        case .manual, .unknown: return nil
        }
    }
    var symbol: String {
        switch self {
        case .appleIntelligence: return "apple.intelligence"
        case .jsonLD: return "curlybraces"
        case .mock: return "theatermasks"
        case .shared: return "person.2"
        case .imported: return "square.and.arrow.down"
        case .manual, .unknown: return "pencil"
        }
    }
}

struct RecipeCard: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = "Untitled recipe"
    var description: String?
    var servings: Int = 2
    var timeMinutes: Int?
    var tags: [String] = []
    var ingredients: [Ingredient] = []
    var steps: [Step] = []
    var imageURL: String?
    var sourceURL: String?
    var createdAt: Double = Date().timeIntervalSince1970 * 1000
    var source: RecipeSource = .manual
    /// ms since epoch when the card was generated/parsed (nil for manual/legacy).
    var generatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, description, servings, timeMinutes, tags, ingredients, steps, imageURL, sourceURL, createdAt, source, generatedAt
    }

    init(id: String = UUID().uuidString, title: String = "Untitled recipe", description: String? = nil,
         servings: Int = 2, timeMinutes: Int? = nil, tags: [String] = [], ingredients: [Ingredient] = [],
         steps: [Step] = [], imageURL: String? = nil, sourceURL: String? = nil,
         createdAt: Double = Date().timeIntervalSince1970 * 1000, source: RecipeSource = .manual, generatedAt: Double? = nil) {
        self.source = source; self.generatedAt = generatedAt
        self.id = id; self.title = title; self.description = description; self.servings = servings
        self.timeMinutes = timeMinutes; self.tags = tags; self.ingredients = ingredients; self.steps = steps
        self.imageURL = imageURL; self.sourceURL = sourceURL; self.createdAt = createdAt
    }

    /// Lenient decoding so web exports / AI output with missing fields still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled recipe"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        if let i = try? c.decode(Int.self, forKey: .servings) { servings = i }
        else if let d = try? c.decode(Double.self, forKey: .servings) { servings = Int(d) } else { servings = 2 }
        if let i = try? c.decode(Int.self, forKey: .timeMinutes) { timeMinutes = i }
        else if let d = try? c.decode(Double.self, forKey: .timeMinutes) { timeMinutes = Int(d) } else { timeMinutes = nil }
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        ingredients = (try? c.decode([Ingredient].self, forKey: .ingredients)) ?? []
        steps = (try? c.decode([Step].self, forKey: .steps)) ?? []
        imageURL = try? c.decodeIfPresent(String.self, forKey: .imageURL)
        sourceURL = try? c.decodeIfPresent(String.self, forKey: .sourceURL)
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? Date().timeIntervalSince1970 * 1000
        source = (try? c.decodeIfPresent(RecipeSource.self, forKey: .source)) ?? .unknown
        generatedAt = try? c.decodeIfPresent(Double.self, forKey: .generatedAt)
    }
}

enum Aisle: String, Codable, CaseIterable {
    case produce = "Produce", dairy = "Dairy", meatFish = "Meat & Fish", pantry = "Pantry",
         bakery = "Bakery", frozen = "Frozen", other = "Other"
}

struct ShoppingItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var quantity: Double
    var unit: String
    var done: Bool = false
    var from: String?
    var sources: [String]?
    var notes: String?
    var aisle: Aisle?
}

enum UnitSystem: String, Codable, CaseIterable { case metric, imperial }

struct AppSettings: Codable, Equatable {
    var onDeviceOnly = false
    var units: UnitSystem = .metric
}

struct TimerPrefs: Codable, Equatable {
    var sound = true
    var vibration = true
    var stepAlerts = true
    var quietHours = false
    var quietStart = "22:00"
    var quietEnd = "07:00"
}

enum AppTab: Hashable { case library, shopping, settings }

enum Route: Hashable {
    case recipe(String)
    case cook(String)
    case shopping
    case settings
    case shared(String)
    case notFound
}
