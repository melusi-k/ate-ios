import XCTest
import SwiftData
@testable import Ate

/// #245 phase 3: journal store open path - corrupt-store recovery (R-DATA-01) and the honest
/// open state the timeline presents. Fixtures follow StoreRecoveryTests: corrupt bytes in the
/// main file plus -wal/-shm sidecars. The module-local legacy JournalEntry shadows the app type
/// target-wide (LegacyJournalStoreUpgradeTests), so app refs are qualified as Ate.JournalEntry.
@MainActor
final class JournalStoreRecoveryTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ate-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    private func makeJournal(_ cfg: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self, configurations: cfg)
    }

    @discardableResult
    private func seedEntryAndPayload(in container: ModelContainer, entryID: String = "entry-1") throws -> Int {
        let ctx = ModelContext(container)
        ctx.insert(Ate.JournalEntry(id: entryID, prompt: "Reflect", text: "Sunday lunch", state: .balanced, recipeIDs: []))
        ctx.insert(JournalMealPayload(entryID: entryID, meal: .lunch, foodName: "Mogodu", quantity: 1, quantityUnit: "serving",
                                      servings: 1, source: .userProvided, sourceName: "Me",
                                      nutrients: NutritionSnapshot(energyKcal: 450, proteinGrams: 30, carbohydratesGrams: 20, fatGrams: 25, fibreGrams: 4)))
        try ctx.save()
        return 2
    }

    func testHealthyJournalStoreOpensWithoutRecovery() throws {
        let url = dir.appendingPathComponent("journal.store")
        let out = StoreRecovery.open(url: url, make: makeJournal)
        XCTAssertNotNil(out.container)
        XCTAssertFalse(out.recovered)
        XCTAssertNil(out.backupURL)
        XCTAssertEqual(try seedEntryAndPayload(in: try XCTUnwrap(out.container)), 2)
        XCTAssertEqual(JournalStore.openState(for: out), .ok)
    }

    func testCorruptJournalStoreIsMovedAsideWithSidecarsAndReopensFresh() throws {
        let url = dir.appendingPathComponent("journal.store")
        try Data(repeating: 0x5A, count: 4096).write(to: url)
        try Data("junk".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("junk".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))

        let out = StoreRecovery.open(url: url, now: Date(timeIntervalSince1970: 1_760_000_000), make: makeJournal)
        XCTAssertNotNil(out.container, "never crashes, always gets a store")
        XCTAssertTrue(out.recovered)
        XCTAssertNotNil(out.error)
        let backup = try XCTUnwrap(out.backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "backup-before-retire: the damaged store is kept")
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("ate-2025"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path + "-shm"))
        XCTAssertEqual(JournalStore.openState(for: out), .recovered(backupName: backup.lastPathComponent))
        // The fresh store works and holds both models.
        XCTAssertEqual(try seedEntryAndPayload(in: try XCTUnwrap(out.container)), 2)
    }

    func testJournalStoreFallsBackToInMemoryWhenEvenAFreshStoreFails() {
        struct Boom: Error {}
        var calls = 0
        let out = StoreRecovery.open(url: dir.appendingPathComponent("x.store")) { cfg in
            calls += 1
            if !cfg.isStoredInMemoryOnly { throw Boom() }
            return try self.makeJournal(cfg)
        }
        XCTAssertTrue(out.inMemoryFallback)
        XCTAssertNotNil(out.container)
        XCTAssertEqual(calls, 3)
        guard case .inMemoryFallback = JournalStore.openState(for: out) else {
            return XCTFail("expected inMemoryFallback, got \(JournalStore.openState(for: out))")
        }
    }

    /// The production open path changed from a named configuration to a URL for the same file
    /// ("AteJournal" resolves to this URL in the default directory). Entries written through the
    /// named configuration must read back through the recovery path's URL open, payload included.
    func testEntriesWrittenViaNamedConfigurationSurviveTheURLOpenPath() throws {
        let name = "AteJournalTest-\(UUID().uuidString)"
        let namedURL = ModelConfiguration(name).url
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: namedURL.path + suffix)) }
        }
        let written = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                         configurations: ModelConfiguration(name))
        XCTAssertEqual(try seedEntryAndPayload(in: written), 2)

        let out = StoreRecovery.open(url: namedURL, make: makeJournal)
        XCTAssertNotNil(out.container)
        XCTAssertFalse(out.recovered, "a healthy store opens cleanly, no backup, no data moved")
        let ctx = ModelContext(try XCTUnwrap(out.container))
        let entries = try ctx.fetch(FetchDescriptor<Ate.JournalEntry>())
        let payloads = try ctx.fetch(FetchDescriptor<JournalMealPayload>())
        XCTAssertEqual(entries.map(\.id), ["entry-1"])
        XCTAssertEqual(payloads.map(\.entryID), ["entry-1"])
        XCTAssertEqual(payloads.first?.foodName, "Mogodu")
    }

    func testOpenStateMappingCoversEveryOutcome() {
        XCTAssertEqual(JournalStore.openState(for: StoreRecovery.Outcome(container: nil, error: "boom")), .unavailable(error: "boom"))
        var recovered = StoreRecovery.Outcome()
        recovered.recovered = true; recovered.backupURL = URL(fileURLWithPath: "/tmp/Backups/ate-20250101.store")
        XCTAssertEqual(JournalStore.openState(for: recovered), .recovered(backupName: "ate-20250101.store"))
        var memory = StoreRecovery.Outcome(); memory.inMemoryFallback = true; memory.error = "e"
        XCTAssertEqual(JournalStore.openState(for: memory), .inMemoryFallback(error: "e"))
        XCTAssertEqual(JournalStore(inMemory: true).openState, .ok)
    }
}
