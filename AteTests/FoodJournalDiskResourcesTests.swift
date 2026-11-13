import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalDiskResourcesTests: XCTestCase {
    private func fixture(_ body: (FoodJournalDiskResources, AccountWriterGate, UUID) throws -> Void) throws {
        let suite = "FoodJournalDisk-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        let resources = FoodJournalDiskResources(controlDirectory: root, defaults: defaults,
            goals: NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
            mediaDirectory: root.appendingPathComponent("media"),
            migrationBackupDirectory: root.appendingPathComponent("migration"),
            repairBackupDirectory: root.appendingPathComponent("repair"),
            recipeConfiguration: ModelConfiguration(isStoredInMemoryOnly: true),
            journalConfiguration: ModelConfiguration("AteJournal", isStoredInMemoryOnly: true))
        try body(resources, gate, lease)
    }

    func testRawRecoveryMustCompleteBeforeOrdinaryResourcesAndRetainsContainers() throws {
        try fixture { disk, gate, lease in
            XCTAssertThrowsError(try disk.recipeContainer())
            XCTAssertThrowsError(try disk.makeResources(boundary: .legacy, afterRestoreCommit: {}))
            try disk.recover(gate: gate, lease: lease, ownerIdentity: "local-fixture")
            let first = try disk.recipeContainer()
            try disk.recover(gate: gate, lease: lease, ownerIdentity: "local-fixture")
            XCTAssertTrue(try disk.recipeContainer() === first)
            let resources = try disk.makeResources(boundary: .legacy, afterRestoreCommit: {})
            XCTAssertTrue(resources.recipeContext === first.mainContext)
            XCTAssertFalse(first.mainContext.autosaveEnabled)
            XCTAssertFalse(try XCTUnwrap(resources.journal.container).mainContext.autosaveEnabled)
            XCTAssertTrue(try resources.journal.readReflections().isEmpty)
            XCTAssertThrowsError(try disk.recover(gate: gate, lease: lease, ownerIdentity: "other-owner"))
        }
    }

    func testStaleLeaseCannotOpenRawStoresOrPublishOrdinaryResources() throws {
        try fixture { disk, gate, lease in
            try gate.invalidateWriters()
            XCTAssertThrowsError(try disk.recover(gate: gate, lease: lease, ownerIdentity: "local-fixture"))
            XCTAssertThrowsError(try disk.recipeContainer())
            XCTAssertThrowsError(try disk.makeResources(boundary: .legacy, afterRestoreCommit: {}))
        }
    }

    func testEpochInvalidationAfterSuccessfulRecoveryRefusesBothResourceAccessors() throws {
        try fixture { disk, gate, lease in
            try disk.recover(gate: gate, lease: lease, ownerIdentity: "local-fixture")
            _ = try disk.recipeContainer()
            _ = try disk.makeResources(boundary: .legacy, afterRestoreCommit: {})
            try gate.invalidateWriters()
            XCTAssertThrowsError(try disk.recipeContainer()) { error in
                guard case AccountWriterGate.Error.staleLease = error else {
                    return XCTFail("expected original recovered lease refusal, got \(error)")
                }
            }
            XCTAssertThrowsError(try disk.makeResources(boundary: .legacy, afterRestoreCommit: {})) { error in
                guard case AccountWriterGate.Error.staleLease = error else {
                    return XCTFail("expected original recovered lease refusal, got \(error)")
                }
            }
            let replacement = try gate.captureWriter()
            XCTAssertNotEqual(replacement, lease)
            XCTAssertThrowsError(try disk.recover(gate: gate, lease: replacement, ownerIdentity: "local-fixture"),
                                 "fresh lease must not bless already recovered old resources")
        }
    }

}
