import Foundation
import SwiftData

/// Versioned unified user-data archive (#245 slice A). The version-1 sections are
/// byte-compatible with the legacy AteDataArchive decode contract; version 2 adds the
/// lossless Journal section. The legacy path in AppStore stays authoritative until
/// activation binds these routes; nothing here rebinds Settings or any AppStore action.
struct AteUnifiedArchive: Codable, Equatable {
    static let formatName = "ate-user-data"
    static let currentVersion = 2

    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var recipes: [RecipeCard]
    var shoppingItems: [ShoppingItem]
    var nutritionDiaryEntries: [NutritionDiaryEntry]
    var nutritionGoals: DailyNutritionGoals
    var appSettings: AppSettings
    var timerPreferences: TimerPrefs
    /// nil exactly when the value was decoded from a version-1 archive (no Journal section
    /// existed then). A version-2 value always carries it.
    var journal: JournalArchive?

    init(exportedAt: Date = .now, appVersion: String = AppConfig.appVersion, recipes: [RecipeCard],
         shoppingItems: [ShoppingItem], nutritionDiaryEntries: [NutritionDiaryEntry],
         nutritionGoals: DailyNutritionGoals, appSettings: AppSettings, timerPreferences: TimerPrefs,
         journal: JournalArchive?) {
        format = Self.formatName
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.recipes = recipes
        self.shoppingItems = shoppingItems
        self.nutritionDiaryEntries = nutritionDiaryEntries
        self.nutritionGoals = nutritionGoals
        self.appSettings = appSettings
        self.timerPreferences = timerPreferences
        self.journal = journal
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, appVersion, recipes, shoppingItems
        case nutritionDiaryEntries, nutritionGoals, appSettings, timerPreferences, journal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        recipes = try c.decode([RecipeCard].self, forKey: .recipes)
        shoppingItems = try c.decode([ShoppingItem].self, forKey: .shoppingItems)
        nutritionDiaryEntries = try c.decode([NutritionDiaryEntry].self, forKey: .nutritionDiaryEntries)
        nutritionGoals = try c.decode(DailyNutritionGoals.self, forKey: .nutritionGoals)
        appSettings = try c.decode(AppSettings.self, forKey: .appSettings)
        timerPreferences = try c.decode(TimerPrefs.self, forKey: .timerPreferences)
        journal = try c.decodeIfPresent(JournalArchive.self, forKey: .journal)
    }
}

enum UnifiedArchiveCaptureError: LocalizedError {
    /// A stored recipe/shopping entity row could not be decoded. Capture refuses rather
    /// than silently dropping user data from an export.
    case recipeStoreUnreadable
    case shoppingStoreUnreadable

    var errorDescription: String? {
        switch self {
        case .recipeStoreUnreadable: "The saved recipe library could not be read for export."
        case .shoppingStoreUnreadable: "The saved shopping list could not be read for export."
        }
    }
}

/// Production capture binding for the unified archive (#245 slice A). Read-only: it never
/// writes any store and holds no lease. Central must call it inside the composed writer
/// boundary (the account-gate effect WITHOUT a generation advance) so no writer can
/// interleave mid-capture. Every section fails visibly instead of fabricating empty data.
@MainActor
struct UnifiedArchiveCapture {
    let journal: JournalStore
    let recipeContainer: ModelContainer
    let diary: NutritionDiaryRepository
    let goals: NutritionGoalsRepository
    let defaults: UserDefaults
    let mediaDirectory: URL

    /// Outer raw sections first, then the Journal section with media bytes.
    func capture() async throws -> AteUnifiedArchive {
        let recipes = try Self.readRecipes(recipeContainer)
        let shopping = try Self.readShopping(recipeContainer)
        let diaryEntries: [NutritionDiaryEntry]
        switch diary.loadState() {
        case .loaded(let entries): diaryEntries = entries
        case .absent: diaryEntries = []
        case .corrupt: throw AteDataArchiveError.localDiaryUnreadableOnExport
        }
        let goalValues = try goals.load()
        let settings = Self.readDefaults(AppSettings.self, defaults: defaults,
                                         key: ArchiveDefaultsParticipant.settingsKey) ?? AppSettings()
        let timers = Self.readDefaults(TimerPrefs.self, defaults: defaults,
                                       key: ArchiveDefaultsParticipant.timerKey) ?? TimerPrefs()
        let journalArchive = try await JournalArchiveCapture.captureWithMedia(journal: journal,
                                                                              mediaDirectory: mediaDirectory)
        return AteUnifiedArchive(recipes: recipes, shoppingItems: shopping,
                                 nutritionDiaryEntries: diaryEntries, nutritionGoals: goalValues,
                                 appSettings: settings, timerPreferences: timers,
                                 journal: journalArchive)
    }

    /// Sorted by store position like AppStore.load, but a row that fails to decode fails the
    /// whole capture: an export must never silently omit a saved recipe or shopping item.
    private static func readRecipes(_ container: ModelContainer) throws -> [RecipeCard] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<RecipeEntity>(sortBy: [SortDescriptor(\.position)]))
        return try rows.map { row in
            do { return try JSONDecoder().decode(RecipeCard.self, from: row.json) }
            catch { throw UnifiedArchiveCaptureError.recipeStoreUnreadable }
        }
    }

    private static func readShopping(_ container: ModelContainer) throws -> [ShoppingItem] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<ShoppingEntity>(sortBy: [SortDescriptor(\.position)]))
        return try rows.map { row in
            do { return try JSONDecoder().decode(ShoppingItem.self, from: row.json) }
            catch { throw UnifiedArchiveCaptureError.shoppingStoreUnreadable }
        }
    }

    /// Mirrors AppStore.loadDefaults: absent or undecodable bytes yield the running default,
    /// which is exactly what the app presents in that state.
    private static func readDefaults<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
