import XCTest
import SwiftData
@testable import Ate

/// Native UNRUN. Local erase primitives only, never sends a cloud Clear all.
@MainActor
final class RecipeShoppingResetInventoryTests: XCTestCase {
    private func root() throws -> URL {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        return requested.resolvingSymlinksInPath().standardizedFileURL
    }
    func testCompleteLocalListErasesPersonalRedoBackupInboxCoverAndSyncBytesKeepsControl() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ResetInventory-\(UUID().uuidString)"
        // Use the exact suite name for cleanup; independent defaults, never standard.
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let c = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        c.mainContext.insert(RecipeEntity(id: "r", createdAt: 1, position: 0, json: Data("raw".utf8))); try c.mainContext.save()
        let journal = JournalStore(container: nil, openState: .unavailable(error: "fixture"))
        let journalReset = JournalLocalReset(journal: journal, defaults: store,
            goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
            mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
            repairBackupDirectory: root.appendingPathComponent("repair"), preservationDirectory: root.appendingPathComponent("journal-adoption"),
            storeFileURL: root.appendingPathComponent("journal.store"))
        let paths = RecipeShoppingResetInventory.Paths(commitDirectory: root.appendingPathComponent("RecipeShoppingSyncCommit"),
            legacyPreservationDirectory: root.appendingPathComponent("legacy-adoption"), recipeBackupDirectory: root.appendingPathComponent("recipe/Backups"),
            journalBackupDirectory: root.appendingPathComponent("journal/Backups"), recoveredExportDirectory: root.appendingPathComponent("documents"),
            temporaryExportDirectory: root.appendingPathComponent("temporary"), sharedInboxDirectory: root.appendingPathComponent("Inbox"),
            sharedCoverDirectory: root.appendingPathComponent("shared/Covers"), appOnlyCoverDirectory: root.appendingPathComponent("local/Covers"),
            archiveControlDirectory: root.appendingPathComponent("control"), cacheDirectory: root.appendingPathComponent("cache"))
        let personalDirectories = [paths.commitDirectory, paths.legacyPreservationDirectory, paths.recipeBackupDirectory,
            paths.journalBackupDirectory, paths.sharedInboxDirectory, paths.sharedCoverDirectory, paths.appOnlyCoverDirectory]
        for dir in personalDirectories {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("personal".utf8).write(to: dir.appendingPathComponent("unreadable-orphan"))
        }
        for dir in [paths.recoveredExportDirectory, paths.temporaryExportDirectory, paths.archiveControlDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: dir.appendingPathComponent("unrelated"))
        }
        try Data("personal export".utf8).write(to: paths.recoveredExportDirectory.appendingPathComponent("Ate-recovered-fixture.json"))
        try Data("personal export".utf8).write(to: paths.temporaryExportDirectory.appendingPathComponent("ate-data.json"))
        try FileManager.default.createDirectory(at: paths.archiveControlDirectory.appendingPathComponent("txn-malformed"), withIntermediateDirectories: false)
        let control = paths.archiveControlDirectory.appendingPathComponent("writer-epoch-v1")
        let receipt = paths.archiveControlDirectory.appendingPathComponent("account-generation-v1.json")
        try Data("control epoch".utf8).write(to: control); try Data("control receipt".utf8).write(to: receipt)
        store.set(Data("tombstones".utf8), forKey: "ate.sync.v1"); store.set(Data("cook".utf8), forKey: "ate.cookSession.v1")
        store.set(true, forKey: "ate.foodJournal.diaryMigration.v1")
        let inventory = RecipeShoppingResetInventory(recipes: c, journal: journalReset, authorityDefaults: store,
            legacyStandardDefaults: store, sharedDefaults: store, paths: paths)
        let (components, required) = try inventory.components(validateResetGate: {})
        let report = try ClearAllLocalData.execute(components, requiredNames: required, validateWriterGate: {})
        XCTAssertTrue(report.complete, "\(report.failures)")
        XCTAssertTrue(try UnifiedArchiveImportBinding.snapshotRecipeShopping(c).recipes.isEmpty)
        for dir in personalDirectories { XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty) }
        XCTAssertNil(store.object(forKey: "ate.sync.v1")); XCTAssertNil(store.object(forKey: "ate.cookSession.v1"))
        XCTAssertTrue(store.bool(forKey: "ate.foodJournal.diaryMigration.v1"))
        XCTAssertEqual(try Data(contentsOf: control), Data("control epoch".utf8))
        XCTAssertEqual(try Data(contentsOf: receipt), Data("control receipt".utf8))
        for dir in [paths.recoveredExportDirectory, paths.temporaryExportDirectory, paths.archiveControlDirectory] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("unrelated").path))
        }
    }
    func testSelectiveCleanupRejectsSymlinkRootAndDoesNotFollowChildSymlinks() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside"), selection = root.appendingPathComponent("selection")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: selection, withIntermediateDirectories: false)
        let bytes = Data("keep".utf8), target = outside.appendingPathComponent("keep")
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: selection.appendingPathComponent("txn-child"), withDestinationURL: outside)
        let component = RecipeShoppingResetInventory.selectedEntries(name: "fixture", directory: selection, selected: { $0.hasPrefix("txn-") }, validateResetGate: {})
        try component.erase(); try component.verifyEmpty(); XCTAssertEqual(try Data(contentsOf: target), bytes)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: selection)
        let refused = RecipeShoppingResetInventory.selectedEntries(name: "refused", directory: link, selected: { _ in true }, validateResetGate: {})
        XCTAssertThrowsError(try refused.erase()); XCTAssertThrowsError(try refused.verifyEmpty())
    }
}
