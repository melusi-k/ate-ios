import XCTest
import SwiftData
import CryptoKit
@testable import Ate

@MainActor
final class ArchiveCaptureBindingTests: XCTestCase {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func suite() throws -> (UserDefaults, String) {
        let name = "ArchiveCapture-" + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func goals(_ defaults: UserDefaults, suite: String) -> NutritionGoalsRepository {
        NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suite).appendingPathComponent("goals.json")))
    }

    private func mediaDirectory(_ suite: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("media")
    }

    private func cleanup(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    }

    private func diaryEntry(_ id: UUID = UUID(), food: String = "Pap") -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: food, date: Date(timeIntervalSince1970: 1_700_000_000),
            meal: .lunch, quantity: 1, quantityUnit: "cup", servings: 1,
            source: .userProvided, sourceName: "Me",
            nutrientsPerServing: NutritionSnapshot(), dayKey: "2023-11-14")
    }

    private func card(_ id: String) -> RecipeCard {
        RecipeCard(id: id, title: "Recipe " + id,
                   ingredients: [Ingredient(name: "Pap", quantity: 1, unit: "cup")],
                   steps: [Step(order: 0, instruction: "Cook")], createdAt: 1234)
    }

    private func item(_ id: String) -> ShoppingItem { ShoppingItem(id: id, name: "Rice", quantity: 1, unit: "kg") }

    private func seedContainer(_ c: ModelContainer, recipes: [RecipeCard], shopping: [ShoppingItem]) throws {
        let ctx = ModelContext(c); ctx.autosaveEnabled = false
        let enc = JSONEncoder()
        for (i, r) in recipes.enumerated() {
            ctx.insert(RecipeEntity(id: r.id, createdAt: r.createdAt, position: i, json: try enc.encode(r)))
        }
        for (i, s) in shopping.enumerated() {
            ctx.insert(ShoppingEntity(id: s.id, position: i, json: try enc.encode(s)))
        }
        try ctx.save()
    }

    private func seedJournalReflection(_ store: JournalStore, id: String, mediaName: String?) throws {
        let ctx = ModelContext(try XCTUnwrap(store.container)); ctx.autosaveEnabled = false
        let row = JournalEntry(id: id, createdAt: Date(timeIntervalSince1970: 1234),
                               prompt: "Dinner?", text: "Dinner", state: .balanced)
        if let mediaName { row.mediaFileNames = [mediaName] }
        ctx.insert(row)
        try ctx.save()
    }

    private func capture(_ store: JournalStore, _ c: ModelContainer, _ d: UserDefaults,
                         _ suite: String) -> UnifiedArchiveCapture {
        UnifiedArchiveCapture(journal: store, recipeContainer: c,
                              diary: NutritionDiaryRepository(defaults: d),
                              goals: goals(d, suite: suite), defaults: d,
                              mediaDirectory: mediaDirectory(suite))
    }

    func testCaptureSectionsRoundTripWithMedia() async throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        let c = try container()
        let cards = [card("r-1"), card("r-2")]
        try seedContainer(c, recipes: cards, shopping: [item("s-1")])
        let diary = NutritionDiaryRepository(defaults: d)
        let entries = [diaryEntry()]
        try diary.savePrepared(diary.prepare(entries))
        var goalValues = DailyNutritionGoals()
        goalValues.energyKcal = 2345
        try goals(d, suite: name).save(goalValues)
        d.set(try JSONEncoder().encode(AppSettings(onDeviceOnly: true, units: .imperial)),
              forKey: ArchiveDefaultsParticipant.settingsKey)
        var timers = TimerPrefs(); timers.quietHours = true
        d.set(try JSONEncoder().encode(timers), forKey: ArchiveDefaultsParticipant.timerKey)
        let store = JournalStore(inMemory: true)
        let media = Data("jpeg-bytes".utf8)
        let dir = mediaDirectory(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try media.write(to: dir.appendingPathComponent("m-1.jpg"))
        try seedJournalReflection(store, id: "j-1", mediaName: "m-1.jpg")

        let binding = capture(store, c, d, name)
        let snapshot = try binding.snapshot()
        let archive = try await binding.finish(snapshot, stillCurrent: {})
        XCTAssertEqual(archive.format, AteUnifiedArchive.formatName)
        XCTAssertEqual(archive.version, 2)
        XCTAssertEqual(archive.recipes.map(\.id), ["r-1", "r-2"])
        XCTAssertEqual(archive.shoppingItems.map(\.id), ["s-1"])
        XCTAssertEqual(archive.nutritionDiaryEntries, entries)
        XCTAssertEqual(archive.nutritionGoals, goalValues)
        XCTAssertEqual(archive.appSettings, AppSettings(onDeviceOnly: true, units: .imperial))
        XCTAssertEqual(archive.timerPreferences, timers)
        let journal = try XCTUnwrap(archive.journal)
        XCTAssertEqual(journal.entries.map(\.id), ["j-1"])
        XCTAssertEqual(journal.media["m-1.jpg"], media)
        XCTAssertEqual(journal.mediaSHA256["m-1.jpg"],
                       SHA256.hash(data: media).map { String(format: "%02x", $0) }.joined())
    }

    func testCorruptDiaryRefusesExportRatherThanFabricatingEmpty() throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        d.set(Data("not a diary".utf8), forKey: NutritionDiaryRepository.storageKey)
        let store = JournalStore(inMemory: true)
        XCTAssertThrowsError(try capture(store, try container(), d, name).snapshot()) { error in
            guard case AteDataArchiveError.localDiaryUnreadableOnExport = error else {
                return XCTFail("expected localDiaryUnreadableOnExport, got \(error)")
            }
        }
    }

    func testUnavailableJournalRefusesCapture() throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        let store = JournalStore(container: nil, openState: .unavailable(error: "fixture"))
        XCTAssertThrowsError(try capture(store, try container(), d, name).snapshot()) { error in
            guard case JournalArchiveError.unavailable = error else {
                return XCTFail("expected unavailable, got \(error)")
            }
        }
    }

    func testUndecodableRecipeEntityFailsVisibly() throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        let c = try container()
        let ctx = ModelContext(c); ctx.autosaveEnabled = false
        ctx.insert(RecipeEntity(id: "r-bad", createdAt: 1, position: 0, json: Data("{broken".utf8)))
        try ctx.save()
        XCTAssertThrowsError(try capture(JournalStore(inMemory: true), c, d, name).snapshot()) { error in
            guard case UnifiedArchiveCaptureError.recipeStoreUnreadable = error else {
                return XCTFail("expected recipeStoreUnreadable, got \(error)")
            }
        }
    }

    /// Snapshot must never run the diary's dayKey migration: legacy (dayKey-less) records
    /// refuse visibly and the stored bytes stay untouched for the migrating writer effect.
    func testLegacyDiaryWithoutDayKeyRefusesRatherThanMigrating() throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        let diary = NutritionDiaryRepository(defaults: d)
        try diary.savePrepared(diary.prepare([diaryEntry()]))
        let encoded = try XCTUnwrap(d.data(forKey: NutritionDiaryRepository.storageKey))
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        objects[0].removeValue(forKey: "dayKey")
        let legacy = try JSONSerialization.data(withJSONObject: objects)
        d.set(legacy, forKey: NutritionDiaryRepository.storageKey)

        XCTAssertThrowsError(try capture(JournalStore(inMemory: true), try container(), d, name).snapshot()) { error in
            guard case UnifiedArchiveCaptureError.diaryMigrationPending = error else {
                return XCTFail("expected diaryMigrationPending, got \(error)")
            }
        }
        XCTAssertEqual(d.data(forKey: NutritionDiaryRepository.storageKey), legacy)
    }

    /// Snapshot must never run the goals legacy-key migration: a legacy-only copy refuses
    /// visibly and the legacy bytes stay untouched for the migrating writer effect.
    func testLegacyGoalsKeyRefusesRatherThanMigrating() throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        var goalValues = DailyNutritionGoals()
        goalValues.energyKcal = 2000
        let legacy = try JSONEncoder().encode(goalValues)
        d.set(legacy, forKey: DailyNutritionGoals.defaultsKey)

        XCTAssertThrowsError(try capture(JournalStore(inMemory: true), try container(), d, name).snapshot()) { error in
            guard case UnifiedArchiveCaptureError.goalsMigrationPending = error else {
                return XCTFail("expected goalsMigrationPending, got \(error)")
            }
        }
        XCTAssertEqual(d.data(forKey: DailyNutritionGoals.defaultsKey), legacy)
    }

    /// A readable stored goals file wins over any legacy key, exactly like load(): no
    /// migration refusal, no write.
    func testStoredGoalsFileDecodesEvenWithLegacyKeyPresent() throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        var stored = DailyNutritionGoals()
        stored.proteinGrams = 120
        try goals(d, suite: name).save(stored)
        var legacyGoals = DailyNutritionGoals()
        legacyGoals.energyKcal = 9999
        d.set(try JSONEncoder().encode(legacyGoals), forKey: DailyNutritionGoals.defaultsKey)

        let snapshot = try capture(JournalStore(inMemory: true), try container(), d, name).snapshot()
        XCTAssertEqual(snapshot.nutritionGoals, stored)
    }

    /// The post-await validation runs after media loading and before acceptance: when it
    /// throws (epoch or generation moved during the await), the export fails and the
    /// archive is discarded.
    func testStillCurrentFailureDiscardsTheArchive() async throws {
        let (d, name) = try suite(); defer { cleanup(name) }
        let store = JournalStore(inMemory: true)
        let binding = capture(store, try container(), d, name)
        let snapshot = try binding.snapshot()
        struct Injected: Error {}
        await XCTAssertAsyncThrowsError(try await binding.finish(snapshot, stillCurrent: { throw Injected() })) { error in
            XCTAssertTrue(error is Injected, "expected injected validation failure, got \(error)")
        }
    }

    func testV1ArchiveDecodesWithoutJournalSection() throws {
        let legacy = AteDataArchive(recipes: [card("r-1")], shoppingItems: [item("s-1")],
                                    nutritionDiaryEntries: [diaryEntry()],
                                    nutritionGoals: DailyNutritionGoals(),
                                    appSettings: AppSettings(), timerPreferences: TimerPrefs())
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(AteUnifiedArchive.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertNil(decoded.journal)
        XCTAssertEqual(decoded.recipes.map(\.id), ["r-1"])
        XCTAssertEqual(decoded.nutritionDiaryEntries.count, 1)
    }

    func testV2RoundTripPreservesJournalSection() throws {
        let entry = JournalArchiveEntry(id: "j-1", createdAt: Date(timeIntervalSince1970: 1234),
            prompt: "p", text: "t", stateRaw: "future-state", recipeIDs: ["r-1"],
            journalingSuggestionTitle: nil, momentDate: nil, sourceRaw: "future-source",
            locationName: nil, latitude: nil, longitude: nil, mediaFileNames: ["m.jpg"],
            editedAt: nil, kindRaw: "reflection", dayKey: nil, recipeSnapshotsRaw: "{future", meal: nil)
        let media = Data([1, 2, 3])
        let journal = JournalArchive(entries: [entry], media: ["m.jpg": media],
            mediaSHA256: ["m.jpg": SHA256.hash(data: media).map { String(format: "%02x", $0) }.joined()])
        let archive = AteUnifiedArchive(recipes: [card("r-1")], shoppingItems: [],
                                        nutritionDiaryEntries: [], nutritionGoals: DailyNutritionGoals(),
                                        appSettings: AppSettings(), timerPreferences: TimerPrefs(),
                                        journal: journal)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoded = try JSONDecoder().decode(AteUnifiedArchive.self, from: enc.encode(archive))
        XCTAssertEqual(decoded, archive)
    }
}

/// Minimal async throwing assertion (XCTAssertThrowsError is synchronous-only).
func XCTAssertAsyncThrowsError<T>(_ expression: @autoclosure () async throws -> T,
                                  _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ errorHandler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown. \(message)", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
