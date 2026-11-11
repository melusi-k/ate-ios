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
    /// The diary still holds pre-migration records (no dayKey): reading them through the
    /// repository would persist a migration. A writer effect must run the migrating load
    /// first; capture never writes.
    case diaryMigrationPending
    /// Goals exist only under the legacy UserDefaults key: reading them through the
    /// repository would migrate them to file storage. A writer effect must run the
    /// migrating load first; capture never writes.
    case goalsMigrationPending
    /// The goals store could not be read or decoded (including an undecodable legacy copy).
    case goalsUnreadable

    var errorDescription: String? {
        switch self {
        case .recipeStoreUnreadable: "The saved recipe library could not be read for export."
        case .shoppingStoreUnreadable: "The saved shopping list could not be read for export."
        case .diaryMigrationPending: "The food diary needs its one-time upgrade before it can be exported."
        case .goalsMigrationPending: "The nutrition goals need their one-time upgrade before they can be exported."
        case .goalsUnreadable: "The saved nutrition goals could not be read for export."
        }
    }
}

/// Production capture binding for the unified archive (#245 slice A). Two phases, matching the
/// approved bounded protocol: `snapshot()` is synchronous and strictly no-write (raw bytes
/// only, no migrating repository load; it refuses visibly when a migration would be needed),
/// `finish(_:stillCurrent:)` does the async media work off the gate and then runs the caller's
/// post-await validation (account epoch + generation unchanged) before the archive is
/// accepted. Central calls snapshot() inside the composed writer boundary (account-gate
/// effect WITHOUT a generation advance), releases the gate, awaits finish, and only accepts
/// the returned archive when stillCurrent() did not throw. Every section fails visibly
/// instead of fabricating empty data.
@MainActor
struct UnifiedArchiveCapture {
    /// Immutable value data copied during the synchronous no-write phase. Media bytes are
    /// intentionally absent; `finish` loads them outside the gate.
    struct Snapshot: Equatable {
        var recipes: [RecipeCard]
        var shoppingItems: [ShoppingItem]
        var nutritionDiaryEntries: [NutritionDiaryEntry]
        var nutritionGoals: DailyNutritionGoals
        var appSettings: AppSettings
        var timerPreferences: TimerPrefs
        var journal: JournalArchive
    }

    let journal: JournalStore
    let recipeContainer: ModelContainer
    let diary: NutritionDiaryRepository
    let goals: NutritionGoalsRepository
    let defaults: UserDefaults
    let mediaDirectory: URL

    /// Synchronous, strictly no-write phase. Runs inside the composed writer boundary.
    /// Repository loads are NOT used where they would write: the diary is decoded from raw
    /// bytes and refuses when legacy (dayKey-less) records would be migrated, and goals
    /// refuse when only the legacy defaults key exists.
    func snapshot() throws -> Snapshot {
        let recipes = try Self.readRecipes(recipeContainer)
        let shopping = try Self.readShopping(recipeContainer)
        let diaryEntries = try readDiaryWithoutMigration()
        let goalValues = try readGoalsWithoutMigration()
        let settings = Self.readDefaults(AppSettings.self, defaults: defaults,
                                         key: ArchiveDefaultsParticipant.settingsKey) ?? AppSettings()
        let timers = Self.readDefaults(TimerPrefs.self, defaults: defaults,
                                       key: ArchiveDefaultsParticipant.timerKey) ?? TimerPrefs()
        let journalSnapshot = try readJournalRows()
        return Snapshot(recipes: recipes, shoppingItems: shopping,
                        nutritionDiaryEntries: diaryEntries, nutritionGoals: goalValues,
                        appSettings: settings, timerPreferences: timers, journal: journalSnapshot)
    }

    /// Async phase, outside the gate: loads and hashes media bytes on a utility queue, then
    /// runs the caller's post-await validation. If `stillCurrent` throws (account epoch or
    /// generation moved during the await), the archive is discarded and the export fails.
    func finish(_ snapshot: Snapshot, stillCurrent: () throws -> Void) async throws -> AteUnifiedArchive {
        let journalArchive = try await Self.loadMedia(snapshot.journal, directory: mediaDirectory)
        try stillCurrent()
        return AteUnifiedArchive(recipes: snapshot.recipes, shoppingItems: snapshot.shoppingItems,
                                 nutritionDiaryEntries: snapshot.nutritionDiaryEntries,
                                 nutritionGoals: snapshot.nutritionGoals,
                                 appSettings: snapshot.appSettings,
                                 timerPreferences: snapshot.timerPreferences,
                                 journal: journalArchive)
    }

    /// No-write mirror of NutritionDiaryRepository.loadState: same decode, same sort, but
    /// legacy (dayKey-less) records refuse instead of persisting a migration.
    private func readDiaryWithoutMigration() throws -> [NutritionDiaryEntry] {
        guard let data = diary.defaults.data(forKey: NutritionDiaryRepository.storageKey) else { return [] }
        guard let entries = try? JSONDecoder().decode([NutritionDiaryEntry].self, from: data) else {
            throw AteDataArchiveError.localDiaryUnreadableOnExport
        }
        let legacyRecords = ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]])?
            .contains { $0["dayKey"] == nil } ?? false
        guard !legacyRecords else { throw UnifiedArchiveCaptureError.diaryMigrationPending }
        return entries.sorted {
            $0.dayKey == $1.dayKey ? $0.date > $1.date : $0.dayKey > $1.dayKey
        }
    }

    /// No-write mirror of NutritionGoalsRepository.load(): a readable stored file decodes
    /// (the legacy key is then irrelevant, load() never touches it); a missing file with a
    /// legacy key would migrate on load, so capture refuses. Undecodable bytes fail
    /// visibly rather than falling back to empty goals.
    private func readGoalsWithoutMigration() throws -> DailyNutritionGoals {
        let storedData: Data?
        do { storedData = try goals.storage.read() }
        catch { throw UnifiedArchiveCaptureError.goalsUnreadable }
        if let storedData {
            do { return try JSONDecoder().decode(DailyNutritionGoals.self, from: storedData) }
            catch { throw UnifiedArchiveCaptureError.goalsUnreadable }
        }
        guard let legacyData = defaults.data(forKey: DailyNutritionGoals.defaultsKey) else {
            return DailyNutritionGoals()
        }
        guard (try? JSONDecoder().decode(DailyNutritionGoals.self, from: legacyData)) != nil else {
            throw UnifiedArchiveCaptureError.goalsUnreadable
        }
        throw UnifiedArchiveCaptureError.goalsMigrationPending
    }

    /// Synchronous row copy identical to JournalArchiveCapture.capture: complete-store
    /// requirement, every raw field verbatim, no media bytes.
    private func readJournalRows() throws -> JournalArchive {
        try JournalArchiveCapture.requireCompleteStore(journal.openState)
        guard let container = journal.container else { throw JournalArchiveError.unavailable }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<JournalEntry>())
        let meals = try FoodJournalStore(container: container).readMeals()
        let mealByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id.uuidString, $0) })
        var result = JournalArchive(entries: [], media: [:])
        for row in rows {
            result.entries.append(ArchiveJournalRowMapping.value(row, meal: mealByID[row.id]))
        }
        result.entries.sort { $0.createdAt < $1.createdAt }
        return result
    }

    /// Media bytes are loaded on a utility queue; only immutable value data and file URLs
    /// cross. Never blocks UI while reading a large JournalMedia folder.
    private static func loadMedia(_ snapshot: JournalArchive, directory: URL,
                                  maximumBytes: Int = 100 * 1024 * 1024) async throws -> JournalArchive {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try JournalArchiveMedia.load(snapshot,
                    directory: directory, maximumBytes: maximumBytes)) }
                catch { continuation.resume(throwing: error) }
            }
        }
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
