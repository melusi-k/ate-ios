import XCTest
@testable import Ate

@MainActor
final class FoodJournalResetInventoryTests: XCTestCase {
    private func fixture(_ run: (URL, UserDefaults, FoodJournalResetInventory) throws -> Void) throws {
        let suite = "ResetInventory-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let p = FoodJournalResetInventory.Paths(media: root.appendingPathComponent("media", isDirectory: true),
            legacyDiaryBackups: root.appendingPathComponent("legacy", isDirectory: true), repairDiaryBackups: root.appendingPathComponent("repair", isDirectory: true),
            adoptionPreservation: root.appendingPathComponent("preservation", isDirectory: true), covers: root.appendingPathComponent("covers", isDirectory: true),
            inboxMedia: root.appendingPathComponent("inbox", isDirectory: true), recipeBackups: root.appendingPathComponent("backups", isDirectory: true),
            recoveredExports: root.appendingPathComponent("exports", isDirectory: true), goalsDirectory: root.appendingPathComponent("goals", isDirectory: true),
            control: root.appendingPathComponent("control", isDirectory: true))
        let inventory = FoodJournalResetInventory(stores: .unopened(recipeURL: root.appendingPathComponent("recipes.store"),
            journalURL: root.appendingPathComponent("journal.store")), defaults: defaults, sharedDefaults: defaults,
            goals: FileNutritionGoalsStorage(fileURL: p.goalsDirectory.appendingPathComponent("nutrition-goals-v1.json")), paths: p)
        try run(root, defaults, inventory)
    }
    private func put(_ path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("personal".utf8).write(to: path)
    }

    func testUnopenedResetErasesPersonalBytesIncludingRetiredRecoveryAndKeepsControl() throws {
        try fixture { root, defaults, inventory in
            let p = inventory.paths
            let id = UUID().uuidString
            let personal = [root.appendingPathComponent("recipes.store"), root.appendingPathComponent("recipes.store-wal"),
                root.appendingPathComponent("journal.store"), p.media.appendingPathComponent("photo.jpg"),
                p.legacyDiaryBackups.appendingPathComponent("legacy.json"), p.repairDiaryBackups.appendingPathComponent("corrupt.json"),
                p.adoptionPreservation.appendingPathComponent("before.json"), p.covers.appendingPathComponent("cover.jpg"),
                p.inboxMedia.appendingPathComponent("shared.jpg"), p.recipeBackups.appendingPathComponent("ate-20261113-123456.store"),
                p.recoveredExports.appendingPathComponent("Ate-recovered-20261113-123456.json"),
                p.goalsDirectory.appendingPathComponent("nutrition-goals-v1.json"),
                p.goalsDirectory.appendingPathComponent("nutrition-goals-corrupt-\(id).json"),
                p.control.appendingPathComponent("txn-\(id)/record.json"), p.control.appendingPathComponent(".resolved-\(id)/record.json")]
            for file in personal { try self.put(file) }
            let retained = [p.control.appendingPathComponent("account-generation-v1.json"),
                p.control.appendingPathComponent("writer-gate-v1.lock"), p.control.appendingPathComponent("reset-control.json"),
                p.control.appendingPathComponent(".generation-00000000000000000001"),
                p.recoveredExports.appendingPathComponent("unrelated.json")]
            for file in retained { try self.put(file) }
            for key in ClearAllDataKeys.standard.union(ClearAllDataKeys.shared).union(["ate.sync.v1"]) { defaults.set("personal", forKey: key) }
            defaults.set(true, forKey: "ate.onboarded.v1")
            for key in ClearAllDataKeys.lifecycleMarkers { defaults.set(true, forKey: key) }
            let (components, required) = try inventory.components(validate: {})
            let result = try ClearAllLocalData.execute(components, requiredNames: required, validateWriterGate: {})
            XCTAssertTrue(result.complete, "\(result.failures)")
            for file in personal { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent) }
            for file in retained { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent) }
            XCTAssertNil(defaults.object(forKey: "ate.sync.v1"))
            XCTAssertTrue(defaults.bool(forKey: "ate.onboarded.v1"))
            for key in ClearAllDataKeys.lifecycleMarkers { XCTAssertTrue(defaults.bool(forKey: key)) }
        }
    }

    func testGateFailurePrecedesEraseAndMalformedRecoveryNameFailsClosed() throws {
        try fixture { root, _, inventory in
            let recipe = root.appendingPathComponent("recipes.store")
            try self.put(recipe)
            enum Closed: Error { case gate }
            XCTAssertThrowsError(try inventory.components(validate: { throw Closed.gate }))
            XCTAssertTrue(FileManager.default.fileExists(atPath: recipe.path))
            try self.put(inventory.paths.control.appendingPathComponent("txn-not-a-uuid/record.json"))
            let (components, required) = try inventory.components(validate: {})
            let result = try ClearAllLocalData.execute(components, requiredNames: required, validateWriterGate: {})
            XCTAssertFalse(result.complete)
            XCTAssertTrue(result.failures.contains { $0.component == "archive-personal-recovery-records" })
            XCTAssertTrue(FileManager.default.fileExists(atPath: inventory.paths.control.appendingPathComponent("txn-not-a-uuid/record.json").path))
        }
    }
}
