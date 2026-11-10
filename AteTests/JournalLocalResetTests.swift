import XCTest
import SwiftData
@testable import Ate

/// #245 slice B: unified Journal local reset/writer lifecycle (JournalLocalReset).
@MainActor
final class JournalLocalResetTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "JournalLocalResetTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Resolve symlinks AFTER creation: NSTemporaryDirectory may traverse /var -> /private/var.
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        root = requested.resolvingSymlinksInPath().standardizedFileURL
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        super.tearDown()
    }

    private func goalsStorage() -> FileNutritionGoalsStorage {
        FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))
    }

    private func makeReset(journal: JournalStore, storeFileURL: URL? = nil) -> JournalLocalReset {
        JournalLocalReset(journal: journal, defaults: defaults, goalsStorage: goalsStorage(),
                          mediaDirectory: root.appendingPathComponent("JournalMedia", isDirectory: true),
                          migrationBackupDirectory: root.appendingPathComponent("NutritionDiaryLegacyBackups", isDirectory: true),
                          repairBackupDirectory: root.appendingPathComponent("NutritionDiaryCorruptBackups", isDirectory: true),
                          preservationDirectory: root.appendingPathComponent("AdoptionPreservation", isDirectory: true),
                          storeFileURL: storeFileURL ?? root.appendingPathComponent("AteJournal.store"))
    }

    private func sampleMeal(id: UUID = UUID()) -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: "Pap and wors",
                            date: Date(timeIntervalSince1970: 1_790_000_000), meal: .dinner,
                            quantity: 250, quantityUnit: "g", servings: 1.5, source: .userProvided,
                            sourceName: "Label", sourceIdentifier: "record-42", verificationNote: "cooked",
                            nutrientsPerServing: NutritionSnapshot(energyKcal: 320, proteinGrams: nil,
                                                                   carbohydratesGrams: 40, fatGrams: 8, fibreGrams: nil),
                            dayKey: nil)
    }

    private func rowCounts(_ journal: JournalStore) throws -> (entries: Int, payloads: Int) {
        let container = try XCTUnwrap(journal.container)
        let context = ModelContext(container)
        return (try context.fetch(FetchDescriptor<Ate.JournalEntry>()).count,
                try context.fetch(FetchDescriptor<JournalMealPayload>()).count)
    }

    func testEraseAllRemovesRowsMealsDefaultsGoalsMediaBackupsAndPreservation() throws {
        let journal = JournalStore(inMemory: true)
        XCTAssertTrue(journal.save(prompt: "p", text: "A real reflection", state: nil, recipeIDs: []))
        try FoodJournalStore(container: journal.container).saveMeal(sampleMeal())
        XCTAssertEqual(try rowCounts(journal).entries, 2)

        defaults.set(Data("legacy diary".utf8), forKey: "ate.nutritionDiary.v1")
        defaults.set(Data("legacy goals".utf8), forKey: "ate.nutritionGoals.v1")
        defaults.set(Data("cook outbox".utf8), forKey: "ate.cook.completionOutbox.v1")
        let unreadableKey = "ate.cook.completionOutbox.v1.unreadable.\(UUID().uuidString)"
        defaults.set(Data("unreadable".utf8), forKey: unreadableKey)
        defaults.set(Data("history".utf8), forKey: "ate.cooking.history.v1")
        defaults.set(Data("associations".utf8), forKey: "ate.nutritionRecipeAssociations.v1")
        defaults.set(true, forKey: "ate.foodJournal.diaryMigration.v1")   // lifecycle marker: PRESERVED
        try goalsStorage().write(Data("goals file".utf8))
        for name in ["JournalMedia", "NutritionDiaryLegacyBackups", "NutritionDiaryCorruptBackups", "AdoptionPreservation"] {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            try Data("personal bytes".utf8).write(to: dir.appendingPathComponent("blob-\(UUID().uuidString).json"))
        }

        let report = try makeReset(journal: journal).eraseAll(validateWriterGate: {})
        XCTAssertTrue(report.complete, "failures: \(report.failures)")

        let afterErase = try rowCounts(journal)
        XCTAssertEqual(afterErase.entries, 0)
        XCTAssertEqual(afterErase.payloads, 0)
        for key in JournalLocalReset.journalDefaultsKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) must be erased")
        }
        XCTAssertNil(defaults.object(forKey: unreadableKey))
        XCTAssertNotNil(defaults.object(forKey: "ate.foodJournal.diaryMigration.v1"),
                        "Migration markers are non-personal control state and must survive")
        XCTAssertNil(try goalsStorage().read())
        for name in ["JournalMedia", "NutritionDiaryLegacyBackups", "NutritionDiaryCorruptBackups", "AdoptionPreservation"] {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(name).path), [],
                           "\(name) must verify empty")
        }
    }

    func testUnavailableStoreDeletesDurableStoreFiles() throws {
        let journal = JournalStore(container: nil, openState: .unavailable(error: "simulated"))
        let storeURL = root.appendingPathComponent("AteJournal.store")
        for suffix in ["", "-wal", "-shm"] {
            try Data("durable bytes".utf8).write(to: URL(fileURLWithPath: storeURL.path + suffix))
        }
        let report = try makeReset(journal: journal, storeFileURL: storeURL).eraseAll(validateWriterGate: {})
        XCTAssertTrue(report.complete, "failures: \(report.failures)")
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path + suffix))
        }
    }

    func testInMemoryFallbackErasesSessionRowsAndDurableStoreFiles() throws {
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let journal = JournalStore(container: container, openState: .inMemoryFallback(error: "simulated"))
        try FoodJournalStore(container: container).saveMeal(sampleMeal())
        let storeURL = root.appendingPathComponent("AteJournal.store")
        try Data("durable bytes".utf8).write(to: storeURL)
        let report = try makeReset(journal: journal, storeFileURL: storeURL).eraseAll(validateWriterGate: {})
        XCTAssertTrue(report.complete, "failures: \(report.failures)")
        let afterErase = try rowCounts(journal)
        XCTAssertEqual(afterErase.entries, 0, "Session rows must not survive a wipe even in fallback state")
        XCTAssertEqual(afterErase.payloads, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path),
                       "Row erasure through an in-memory container proves nothing about disk bytes")
    }

    func testNilContainerInDurableStateIsAFailureNeverReportedEmpty() throws {
        let journal = JournalStore(container: nil, openState: .ok)
        let report = try makeReset(journal: journal).eraseAll(validateWriterGate: {})
        XCTAssertFalse(report.complete)
        XCTAssertTrue(report.failures.contains { $0.component == "journal-rows-payloads" && $0.operation == "erase" })
    }

    func testValidatorIsConsultedAroundEveryComponent() throws {
        let journal = JournalStore(inMemory: true)
        var calls = 0
        let report = try makeReset(journal: journal).eraseAll(validateWriterGate: { calls += 1 })
        XCTAssertTrue(report.complete, "failures: \(report.failures)")
        XCTAssertGreaterThanOrEqual(calls, report.verifiedEmpty.count,
                                    "Every component must re-prove the gate, not inherit entry-time proof")
    }

    func testComponentNamesAreStableAndUnique() throws {
        let journal = JournalStore(inMemory: true)
        let (components, required) = try makeReset(journal: journal).components(validateWriterGate: {})
        XCTAssertEqual(Set(components.map(\.name)).count, components.count)
        XCTAssertEqual(required, Set(components.map(\.name)))
        XCTAssertTrue(required.contains("journal-rows-payloads"))
        XCTAssertTrue(required.contains("journal-media"))
        XCTAssertTrue(required.contains("adoption-preservation"))
    }

    func testStoreFileComponentRefusesNonRegularEntries() throws {
        let journal = JournalStore(container: nil, openState: .unavailable(error: "simulated"))
        let storeURL = root.appendingPathComponent("AteJournal.store")
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: false)
        let report = try makeReset(journal: journal, storeFileURL: storeURL).eraseAll(validateWriterGate: {})
        XCTAssertFalse(report.complete, "A directory at the store path must refuse, not be recursed into")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
    }
}
