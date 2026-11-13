import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalDiskResourcesTests: XCTestCase {
    enum Refusal: Error { case identity }
    private func fixture(_ run: (URL, UserDefaults, AccountWriterGate, UUID) throws -> Void) throws {
        let suite = "DiskResources-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        try run(root, defaults, gate, gate.captureWriter())
    }
    private func resources(_ root: URL, _ defaults: UserDefaults) throws -> FoodJournalDiskResources {
        try FoodJournalDiskResources(defaults: defaults,
            goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
            locations: .init(storeFileURL: root.appendingPathComponent("journal.store"),
                mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
                repairBackupDirectory: root.appendingPathComponent("repair"), preservationDirectory: root.appendingPathComponent("preservation")),
            recipeConfiguration: ModelConfiguration(url: root.appendingPathComponent("recipes.store")),
            journalConfiguration: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
    }
    func testIdentityRefusalPrecedesPersonalStoreOpenAndBindingIsUnavailable() throws {
        try fixture { root, defaults, gate, lease in
            let resources = try resources(root, defaults)
            XCTAssertThrowsError(try resources.recover(gate: gate, admittedLease: lease, ownerIdentity: "owner",
                authorizeRecovery: { throw Refusal.identity }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("journal.store").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recipes.store").path))
            XCTAssertThrowsError(try resources.recipeContainer(gate: gate, admittedLease: lease))
            XCTAssertThrowsError(try resources.bindOwner(gate: gate, admittedLease: lease, ownerIdentity: "owner",
                archive: DiskResourcesArchive(), authorizeBinding: {}, afterRestoreCommit: {}))
        }
    }
    func testStrictOpenPreservesCommittedReflectionAndLegacyBytesWithoutMigration() throws {
        try fixture { root, defaults, gate, lease in
            let configuration = ModelConfiguration(url: root.appendingPathComponent("journal.store"))
            try autoreleasepool {
                let initial = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self, configurations: configuration)
                let writer = ModelContext(initial)
                writer.insert(Ate.JournalEntry(prompt: "", text: "Before strict open", state: nil))
                try writer.save()
            }
            let legacy = Data("unreadable retained diary".utf8)
            defaults.set(legacy, forKey: NutritionDiaryRepository.storageKey)
            let resources = try resources(root, defaults)
            try resources.recover(gate: gate, admittedLease: lease, ownerIdentity: "owner", authorizeRecovery: {})
            let recipes = try resources.recipeContainer(gate: gate, admittedLease: lease)
            XCTAssertFalse(recipes.mainContext.autosaveEnabled)
            let owner = try resources.bindOwner(gate: gate, admittedLease: lease, ownerIdentity: "owner",
                archive: DiskResourcesArchive(), authorizeBinding: {}, afterRestoreCommit: {})
            XCTAssertEqual(try owner.runtime.journal.readReflections().map(\.text), ["Before strict open"])
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), legacy)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("repair").path))
        }
    }
    func testCorruptStoreIsNotMovedAsideOrReplacedAndResourcesRemainUnavailable() throws {
        try fixture { root, defaults, gate, lease in
            let url = root.appendingPathComponent("journal.store")
            let corrupt = Data("not a sqlite database".utf8)
            try corrupt.write(to: url)
            let resources = try resources(root, defaults)
            XCTAssertThrowsError(try resources.recover(gate: gate, admittedLease: lease, ownerIdentity: "owner", authorizeRecovery: {}))
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
            XCTAssertThrowsError(try resources.recipeContainer(gate: gate, admittedLease: lease))
        }
    }
    func testRotatedOriginalLeaseAndDifferentOwnerCannotAccessRecoveredResources() throws {
        try fixture { root, defaults, gate, lease in
            let resources = try resources(root, defaults)
            try resources.recover(gate: gate, admittedLease: lease, ownerIdentity: "owner", authorizeRecovery: {})
            XCTAssertThrowsError(try resources.recover(gate: gate, admittedLease: lease, ownerIdentity: "foreign", authorizeRecovery: {}))
            XCTAssertThrowsError(try resources.bindOwner(gate: gate, admittedLease: lease, ownerIdentity: "foreign",
                archive: DiskResourcesArchive(), authorizeBinding: {}, afterRestoreCommit: {}))
            try gate.invalidateWriters()
            XCTAssertThrowsError(try resources.recipeContainer(gate: gate, admittedLease: lease))
            XCTAssertThrowsError(try resources.bindOwner(gate: gate, admittedLease: lease, ownerIdentity: "owner",
                archive: DiskResourcesArchive(), authorizeBinding: {}, afterRestoreCommit: {}))
        }
    }
    func testRecoveryUsesSameGateRootAndDoesNotRecaptureLease() throws {
        try fixture { root, _, gate, lease in
            var visited = false
            try gate.withArchiveRecoveryLease(lease) { archive in
                visited = true
                try archive.validate()
                XCTAssertFalse(try DiskArchiveRecoveryJournal(lease: archive).hasUnresolvedTransactions())
            }
            XCTAssertTrue(visited)
            try gate.validateWriter(lease)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("writer-gate-v1.lock").path))
        }
    }
}

private final class DiskResourcesArchive: ArchiveNestedLeaseBoundary {
    func withNestedLease<T>(_ work: () throws -> T) throws -> T { try work() }
}
