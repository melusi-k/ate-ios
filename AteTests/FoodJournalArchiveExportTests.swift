import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalArchiveExportTests: XCTestCase {
    private func fixture(_ run: (FoodJournalLocalOwner, FoodJournalArchiveExport, AccountWriterGate, UUID, URL) async throws -> Void) async throws {
        let suite = "OwnerExport-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        let journal = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
        let recipes = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("recipes.store")))
        let owner = try FoodJournalLocalOwner.bind(container: journal, openState: .ok, defaults: defaults,
            goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
            locations: .init(storeFileURL: root.appendingPathComponent("journal.store"),
                mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
                repairBackupDirectory: root.appendingPathComponent("repair"), preservationDirectory: root.appendingPathComponent("preservation")),
            gate: gate, admittedLease: lease, archive: ArchiveNestedGenerationBoundary(directory: root), afterRestoreCommit: {})
        let export = FoodJournalArchiveExport(owner: owner, recipes: recipes, gate: gate, admittedLease: lease,
            validateOwner: { try gate.validateWriter(lease) })
        try await run(owner, export, gate, lease, root)
    }
    func testExportContainsOwnedReflectionAndMediaBytesWithoutGlobalDomains() async throws {
        try await fixture { owner, export, _, _, _ in
            let row = try XCTUnwrap(owner.runtime.journal.saveFromIntent(title: nil, text: "Owned reflection", date: nil,
                state: .balanced, locationName: nil, latitude: nil, longitude: nil, media: [(Data([2, 4, 6]), "jpg")]))
            let data = try await export.export()
            let archive = try JSONDecoder().decode(AteUnifiedArchive.self, from: data)
            XCTAssertEqual(archive.version, 2)
            XCTAssertEqual(archive.journal?.entries.map(\.id), [row.id])
            XCTAssertEqual(archive.journal?.media[row.mediaFileNames[0]], Data([2, 4, 6]))
        }
    }
    func testWriterEpochRotatedDuringAsyncMediaPhasePreventsArchiveDelivery() async throws {
        try await fixture { _, export, gate, _, _ in
            do {
                _ = try await export.export(afterSnapshot: { try gate.invalidateWriters() })
                XCTFail("Stale archive must not escape")
            } catch { }
        }
    }
    func testArchiveGenerationChangedDuringAsyncMediaPhasePreventsDelivery() async throws {
        try await fixture { owner, export, _, _, _ in
            do {
                _ = try await export.export(afterSnapshot: { _ = try owner.runtime.journal.saveManual(text: "Newer reflection") })
                XCTFail("Mixed generation archive must not escape")
            } catch { }
            XCTAssertEqual(try owner.runtime.journal.readReflections().map(\.text), ["Newer reflection"])
        }
    }
    func testUnarchivedRecipeLinksRefuseBeforeMigrationOrExport() async throws {
        try await fixture { owner, export, _, _, _ in
            let raw = Data("retained unreadable links".utf8)
            owner.runtime.defaults.set(raw, forKey: NutritionRecipeAssociationStore.storageKey)
            let legacy = Data("retained unreadable diary".utf8)
            owner.runtime.defaults.set(legacy, forKey: NutritionDiaryRepository.storageKey)
            do { _ = try await export.export(); XCTFail("Incomplete personal archive must refuse") }
            catch { XCTAssertEqual(error as? FoodJournalArchiveExport.Failure, .recipeLinksNotArchived) }
            XCTAssertEqual(owner.runtime.defaults.data(forKey: NutritionRecipeAssociationStore.storageKey), raw)
            XCTAssertEqual(owner.runtime.defaults.data(forKey: NutritionDiaryRepository.storageKey), legacy)
        }
    }
}
