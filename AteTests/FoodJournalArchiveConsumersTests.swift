import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalArchiveConsumersTests: XCTestCase {
    private func fixture(_ body: (FoodJournalArchiveConsumers, AccountWriterGate, UUID, URL) async throws -> Void) async throws {
        let suite = "FoodJournalArchive-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        let archive = ArchiveNestedGenerationBoundary(directory: root)
        let boundary = FoodJournalWriterBoundary(perform: JournalWriterBoundaryComposition.makePerform(
            gate: gate, writerLease: lease, archive: archive))
        let runtime = FoodJournalRuntime(journal: JournalStore(inMemory: true, writerBoundary: boundary),
            goalsRepository: NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
            defaults: defaults, writerBoundary: boundary,
            migrationBackupDirectory: root.appendingPathComponent("migration"),
            repairBackupDirectory: root.appendingPathComponent("repair"))
        let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let consumers = FoodJournalArchiveConsumers(gate: gate, writerLease: lease,
            controlDirectory: root, runtime: runtime, recipeContainer: container,
            mediaDirectory: root.appendingPathComponent("media"),
            preservationDirectory: root.appendingPathComponent("preserved"),
            ownerIdentity: { "local-fixture" }, validateOwner: { try gate.validateWriter(lease) })
        try await body(consumers, gate, lease, root)
    }

    private func archive() -> AteUnifiedArchive {
        AteUnifiedArchive(recipes: [RecipeCard(id: "new-recipe", title: "Retained soup",
            ingredients: [Ingredient(name: "Water", quantity: 1, unit: "cup")])],
            shoppingItems: [], nutritionDiaryEntries: [], nutritionGoals: DailyNutritionGoals(),
            appSettings: AppSettings(), timerPreferences: TimerPrefs(),
            journal: JournalArchive(entries: [], media: [:]))
    }

    func testBoundImportExportUsesRealStoresAndAdditiveRetry() async throws {
        try await fixture { consumers, gate, lease, root in
            let data = try JSONEncoder().encode(self.archive())
            let first = try consumers.importArchive(data)
            XCTAssertEqual(first.recipesAdded, 1)
            let second = try consumers.importArchive(data)
            XCTAssertEqual(second.recipesAdded, 0)
            let exported = try await consumers.exportArchive()
            let decoded = try JSONDecoder().decode(AteUnifiedArchive.self, from: exported)
            XCTAssertEqual(decoded.recipes.map(\.id), ["new-recipe"])
            XCTAssertEqual(decoded.version, AteUnifiedArchive.currentVersion)
            XCTAssertNotNil(decoded.journal)
            try gate.withWriterEffect(lease) {
                let check = try POSIXArchiveWriterLease(nestedDirectory: root)
                defer { check.release() }
                XCTAssertFalse(try DiskArchiveRecoveryJournal(lease: check).hasUnresolvedTransactions())
            }
        }
    }

    func testInvalidFileAndStaleLeaseNeverStartAnImportTransaction() async throws {
        try await fixture { consumers, gate, lease, root in
            XCTAssertThrowsError(try consumers.importArchive(Data("not an archive".utf8)))
            try gate.withWriterEffect(lease) {
                let check = try POSIXArchiveWriterLease(nestedDirectory: root)
                defer { check.release() }
                XCTAssertTrue(try DiskArchiveRecoveryJournal(lease: check).transactions().isEmpty)
            }
            try gate.invalidateWriters()
            XCTAssertThrowsError(try consumers.importArchive(JSONEncoder().encode(self.archive())))
            do { _ = try await consumers.exportArchive(); XCTFail("stale export must fail") }
            catch { }
        }
    }

    func testContentlessRecipeIsNotReportedAsImported() async throws {
        try await fixture { consumers, _, _, _ in
            var input = self.archive()
            input.recipes = [RecipeCard(id: "contentless", title: "Only a title")]
            let summary = try consumers.importArchive(JSONEncoder().encode(input))
            XCTAssertEqual(summary.recipesAdded, 0)
            let exported = try await consumers.exportArchive()
            XCTAssertTrue(try JSONDecoder().decode(AteUnifiedArchive.self, from: exported).recipes.isEmpty)
        }
    }

}
