import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalLocalOwnerTests: XCTestCase {
    private func fixture(_ run: (URL, UserDefaults, ModelContainer, AccountWriterGate, UUID) throws -> Void) throws {
        let suite = "LocalOwner-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
        container.mainContext.autosaveEnabled = false
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try run(root, defaults, container, gate, lease)
    }
    private func locations(_ root: URL) -> FoodJournalLocalOwner.Locations {
        .init(storeFileURL: root.appendingPathComponent("journal.store"),
              mediaDirectory: root.appendingPathComponent("media", isDirectory: true),
              migrationBackupDirectory: root.appendingPathComponent("migration", isDirectory: true),
              repairBackupDirectory: root.appendingPathComponent("repair", isDirectory: true),
              preservationDirectory: root.appendingPathComponent("preservation", isDirectory: true))
    }
    private func bind(_ root: URL, _ defaults: UserDefaults, _ container: ModelContainer,
                      _ gate: AccountWriterGate, _ lease: UUID, _ archive: OwnerNestedBoundary) throws -> FoodJournalLocalOwner {
        try FoodJournalLocalOwner.bind(container: container, openState: .ok, defaults: defaults,
            goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
            locations: locations(root), gate: gate, admittedLease: lease, archive: archive, afterRestoreCommit: {})
    }
    func testOneOwnerRetainsExactMediaGoalsAndResetInventoryWithoutActivation() throws {
        try fixture { root, defaults, container, gate, lease in
            let archive = OwnerNestedBoundary()
            let owner = try bind(root, defaults, container, gate, lease, archive)
            XCTAssertTrue(owner.runtime.defaults === defaults)
            XCTAssertTrue(owner.runtime.journal.container === container)
            XCTAssertEqual(owner.runtime.journal.mediaDirectory, root.appendingPathComponent("media", isDirectory: true))
            XCTAssertEqual(owner.runtime.journal.boundMediaURL("retained.jpg"), root.appendingPathComponent("media/retained.jpg"))
            let inventory = owner.resetInventory
            XCTAssertTrue(inventory.journal === owner.runtime.journal)
            XCTAssertTrue(inventory.defaults === defaults)
            XCTAssertEqual(inventory.mediaDirectory, owner.locations.mediaDirectory)
            XCTAssertEqual(inventory.storeFileURL, owner.locations.storeFileURL)
            XCTAssertEqual(inventory.migrationBackupDirectory, owner.locations.migrationBackupDirectory)
            XCTAssertEqual(inventory.repairBackupDirectory, owner.locations.repairBackupDirectory)
            XCTAssertEqual(inventory.preservationDirectory, owner.locations.preservationDirectory)
            XCTAssertEqual((inventory.goalsStorage as? FileNutritionGoalsStorage)?.fileURL, root.appendingPathComponent("goals.json"))
            let generation = archive.commits
            try owner.validate()
            try owner.validate()
            XCTAssertEqual(archive.commits, generation, "Validation alone must not advance archive generation")
            XCTAssertFalse(FileManager.default.fileExists(atPath: owner.locations.mediaDirectory.path))
        }
    }
    func testOriginalLeaseRotationBlocksConstructionAndAllRetainedWriterEffects() throws {
        try fixture { root, defaults, container, gate, lease in
            let archive = OwnerNestedBoundary()
            let owner = try bind(root, defaults, container, gate, lease, archive)
            try gate.invalidateWriters()
            let before = defaults.dictionaryRepresentation() as NSDictionary
            let generation = archive.commits
            XCTAssertThrowsError(try owner.validate())
            XCTAssertThrowsError(try bind(root, defaults, container, gate, lease, archive))
            XCTAssertThrowsError(try owner.runtime.journal.saveManual(text: "stale"))
            owner.runtime.cookingHistory.record(recipeID: "stale")
            owner.runtime.cookingHistory.clear()
            XCTAssertThrowsError(try owner.runtime.goalsRepository.save(.init(energyKcal: 1900, proteinGrams: nil,
                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            XCTAssertEqual(archive.commits, generation)
            XCTAssertEqual(try owner.runtime.journal.readReflections().count, 0)
        }
    }
    func testArchiveRefusalBlocksOwnerAndSubsequentWritersWithoutCreatingMedia() throws {
        try fixture { root, defaults, container, gate, lease in
            let archive = OwnerNestedBoundary()
            archive.allowed = false
            XCTAssertThrowsError(try bind(root, defaults, container, gate, lease, archive))
            archive.allowed = true
            let owner = try bind(root, defaults, container, gate, lease, archive)
            archive.allowed = false
            let generation = archive.commits
            XCTAssertNil(owner.runtime.journal.saveFromIntent(title: nil, text: "blocked", date: nil, state: .balanced,
                locationName: nil, latitude: nil, longitude: nil, media: [(Data([1, 2, 3]), "jpg")]))
            XCTAssertThrowsError(try owner.runtime.journal.saveManual(text: "blocked"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: owner.locations.mediaDirectory.path))
            XCTAssertEqual(archive.commits, generation)
        }
    }
    func testAliasedDirectoriesAndWrongStoreConfigurationRefuseBeforeArchiveEntry() throws {
        try fixture { root, defaults, container, gate, lease in
            let archive = OwnerNestedBoundary()
            let standard = locations(root)
            let invalid = FoodJournalLocalOwner.Locations(storeFileURL: standard.storeFileURL,
                mediaDirectory: root, migrationBackupDirectory: standard.migrationBackupDirectory,
                repairBackupDirectory: standard.repairBackupDirectory, preservationDirectory: standard.preservationDirectory)
            XCTAssertThrowsError(try FoodJournalLocalOwner.bind(container: container, openState: .ok, defaults: defaults,
                goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
                locations: invalid, gate: gate, admittedLease: lease, archive: archive, afterRestoreCommit: {}))
            let wrong = FoodJournalLocalOwner.Locations(storeFileURL: root.appendingPathComponent("wrong.store"),
                mediaDirectory: standard.mediaDirectory, migrationBackupDirectory: standard.migrationBackupDirectory,
                repairBackupDirectory: standard.repairBackupDirectory, preservationDirectory: standard.preservationDirectory)
            XCTAssertThrowsError(try FoodJournalLocalOwner.bind(container: container, openState: .ok, defaults: defaults,
                goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
                locations: wrong, gate: gate, admittedLease: lease, archive: archive, afterRestoreCommit: {}))
            XCTAssertEqual(archive.commits, 0)
        }
    }
    func testIntentMediaWriteAndDeleteStayInsideTheBoundOwnerDirectory() throws {
        try fixture { root, defaults, container, gate, lease in
            let archive = OwnerNestedBoundary()
            let owner = try bind(root, defaults, container, gate, lease, archive)
            let media = Data([4, 5, 6])
            let row = try XCTUnwrap(owner.runtime.journal.saveFromIntent(title: nil, text: "owned media", date: nil,
                state: .balanced, locationName: nil, latitude: nil, longitude: nil, media: [(media, "jpg")]))
            let name = try XCTUnwrap(row.mediaFileNames.first)
            let url = owner.runtime.journal.boundMediaURL(name)
            XCTAssertEqual(try Data(contentsOf: url), media)
            XCTAssertEqual(url.deletingLastPathComponent(), owner.locations.mediaDirectory)
            XCTAssertTrue(owner.runtime.journal.delete(row))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(try owner.runtime.journal.readReflections().count, 0)
        }
    }
}

private final class OwnerNestedBoundary: ArchiveNestedLeaseBoundary {
    enum Refusal: Error { case archive }
    var allowed = true
    private(set) var commits = 0
    func withNestedLease<T>(_ work: () throws -> T) throws -> T {
        guard allowed else { throw Refusal.archive }
        let result = try work()
        commits += 1
        return result
    }
}
