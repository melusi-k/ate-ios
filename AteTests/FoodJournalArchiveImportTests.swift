import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalArchiveImportTests: XCTestCase {
    private enum Injected: Error { case refuse }
    private func fixture(_ run: (FoodJournalLocalOwner, FoodJournalConsumerLifecycle, ModelContainer, AccountWriterGate, URL) async throws -> Void) async throws {
        let suite = "OwnedImport-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: lease, session: nil, currentSession: { nil })
        let journal = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
        let recipes = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("recipes.store")))
        let owner = try FoodJournalLocalOwner.bind(container: journal, openState: .ok, defaults: defaults,
            goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
            locations: .init(storeFileURL: root.appendingPathComponent("journal.store"),
                mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
                repairBackupDirectory: root.appendingPathComponent("repair"), preservationDirectory: root.appendingPathComponent("preservation")),
            gate: gate, admittedLease: lease, archive: ArchiveNestedGenerationBoundary(directory: root),
            afterRestoreCommit: {}, validateConsumers: lifecycle.validate)
        try await run(owner, lifecycle, recipes, gate, root)
    }
    private func data(reflection: Bool = false) throws -> Data {
        let entries: [JournalArchiveEntry] = reflection ? [.init(id: "imported-reflection", createdAt: .now,
            prompt: "", text: "Imported intact", stateRaw: "balanced", recipeIDs: [],
            journalingSuggestionTitle: nil, momentDate: nil, sourceRaw: "ate", locationName: nil,
            latitude: nil, longitude: nil, mediaFileNames: [], editedAt: nil,
            kindRaw: "reflection", dayKey: nil, recipeSnapshotsRaw: nil, meal: nil)] : []
        return try JSONEncoder().encode(AteUnifiedArchive(recipes: [], shoppingItems: [],
            nutritionDiaryEntries: [], nutritionGoals: DailyNutritionGoals(), appSettings: AppSettings(),
            timerPreferences: TimerPrefs(), journal: JournalArchive(entries: entries, media: [:])))
    }
    func testMalformedFileRefusesBeforeClosingOwnerOrDrainingConsumers() async throws {
        try await fixture { owner, lifecycle, recipes, _, _ in
            var cancelled = false
            try lifecycle.register(cancel: { cancelled = true }, drain: {})
            let importer = try FoodJournalArchiveImport(owner: owner, recipes: recipes, lifecycle: lifecycle,
                ownerIdentity: "local", authorizeOperation: {})
            do { _ = try await importer.importData(Data("bad file".utf8)); XCTFail("Must refuse") } catch { }
            XCTAssertFalse(cancelled)
            XCTAssertEqual(lifecycle.state, .active)
            try owner.validate()
        }
    }
    func testImportDrainsBeforeMutationCommitsOnceAndLeavesOldOwnerClosed() async throws {
        try await fixture { owner, lifecycle, recipes, gate, root in
            var drained = false
            try lifecycle.register(cancel: {}, drain: { await Task.yield(); drained = true })
            let importer = try FoodJournalArchiveImport(owner: owner, recipes: recipes, lifecycle: lifecycle,
                ownerIdentity: "local", authorizeOperation: { XCTAssertTrue(drained) })
            let before = try POSIXArchiveWriterLease(nestedDirectory: root)
            let generation = before.generation; before.release()
            let result = try await importer.importData(self.data(reflection: true))
            XCTAssertEqual(result.journalEntriesAdded, 1)
            XCTAssertTrue(drained); XCTAssertEqual(lifecycle.state, .quiesced)
            XCTAssertEqual(try owner.runtime.journal.readReflections().map(\.text), ["Imported intact"])
            XCTAssertThrowsError(try owner.runtime.journal.saveManual(text: "Closed graph"))
            let current = try gate.captureWriter()
            try gate.withArchiveRecoveryLease(current) { lease in
                XCTAssertEqual(lease.generation, generation + 1)
                XCTAssertFalse(try DiskArchiveRecoveryJournal(lease: lease).hasUnresolvedTransactions())
            }
            do { _ = try await importer.importData(self.data()); XCTFail("Old graph cannot import again") } catch { }
        }
    }
    func testPostDrainAuthorizationFailurePreservesPersonalDataAndClosedGraph() async throws {
        try await fixture { owner, lifecycle, recipes, _, _ in
            _ = try owner.runtime.journal.saveManual(text: "Original")
            let importer = try FoodJournalArchiveImport(owner: owner, recipes: recipes, lifecycle: lifecycle,
                ownerIdentity: "local", authorizeOperation: { throw Injected.refuse })
            do { _ = try await importer.importData(self.data(reflection: true)); XCTFail("Proof must refuse") } catch { }
            XCTAssertEqual(try owner.runtime.journal.readReflections().map(\.text), ["Original"])
            XCTAssertEqual(lifecycle.state, .quiesced)
            XCTAssertThrowsError(try owner.validate())
        }
    }
    func testForeignLifecycleRefusedBeforeAnyQuiescenceOrImport() async throws {
        try await fixture { owner, _, recipes, gate, _ in
            let foreign = FoodJournalConsumerLifecycle(gate: gate, admittedLease: UUID(), session: nil, currentSession: { nil })
            XCTAssertThrowsError(try FoodJournalArchiveImport(owner: owner, recipes: recipes, lifecycle: foreign,
                ownerIdentity: "local", authorizeOperation: {}))
            XCTAssertEqual(foreign.state, .active)
            try owner.validate()
        }
    }
    func testInterruptedImportRetainsRecoveryWithoutGenerationAdvanceOrReopeningOwner() async throws {
        try await fixture { owner, lifecycle, recipes, gate, root in
            let importer = try FoodJournalArchiveImport(owner: owner, recipes: recipes, lifecycle: lifecycle,
                ownerIdentity: "local", authorizeOperation: {})
            let before = try POSIXArchiveWriterLease(nestedDirectory: root)
            let generation = before.generation; before.release()
            do {
                _ = try await importer.importData(self.data(reflection: true), checkpoint: { boundary in
                    if boundary == .afterDatabase { throw Injected.refuse }
                })
                XCTFail("Interrupted import cannot return success")
            } catch { }
            let lease = try gate.captureWriter()
            try gate.withArchiveRecoveryLease(lease) { archive in
                XCTAssertEqual(archive.generation, generation)
                XCTAssertTrue(try DiskArchiveRecoveryJournal(lease: archive).hasUnresolvedTransactions())
            }
            XCTAssertEqual(lifecycle.state, .quiesced)
            XCTAssertThrowsError(try owner.validate())
            XCTAssertEqual(try owner.runtime.journal.readReflections().count, 0)
        }
    }

}
