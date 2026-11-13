import XCTest
import SwiftData
@testable import Ate

/// Native UNRUN. Real on-disk SwiftData save, fresh container reopen and isolated
/// defaults. Snapshot admission is an explicit fixture proof, not a backend request.
@MainActor
final class RecipeShoppingSyncCommitJournalTests: XCTestCase {
    private enum Injected: Error { case crash, unauthorized, writersUnbound }
    private final class RejectingProjection: UserDefaults {
        override func data(forKey key: String) -> Data? {
            if key == "ate.sync.v1" { return nil }
            return super.data(forKey: key)
        }
    }
    @MainActor private final class Fixture {
        let root: URL, journalDirectory: URL, storeURL: URL
        let suite: String, defaults: UserDefaults, gate: AccountWriterGate, lease: UUID
        var receipt = AccountGenerationPolicy.Receipt(ownerID: "owner", generation: 3)
        var admitted: AccountGenerationPolicy.Receipt?
        var writersBound = true
        var container: ModelContainer?
        init() throws {
            suite = "SyncCommit-\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
            root = requested.resolvingSymlinksInPath().standardizedFileURL
            journalDirectory = root.appendingPathComponent(RecipeShoppingSyncCommitJournal.directoryName)
            try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: false)
            storeURL = root.appendingPathComponent("recipes.store")
            let g = try AccountWriterGate(directory: root, resetControlExists: { false })
            gate = g; lease = try g.captureWriter()
            let store = try AccountGenerationReceiptStore(directory: root)
            try g.withWriterEffect(lease) { try store.save(receipt) }
            admitted = receipt
            try reopen()
        }
        func reopen() throws {
            container = nil
            let reopened = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                configurations: ModelConfiguration(url: storeURL))
            reopened.mainContext.autosaveEnabled = false
            container = reopened
        }
        func close() { container = nil }
        func cleanup() {
            container = nil
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        func journal(checkpoint: @escaping (RecipeShoppingSyncCommitJournal.Boundary) throws -> Void = { _ in },
                     save: @escaping (ModelContext) throws -> Void = { try $0.save() },
                     projection: UserDefaults? = nil) throws -> RecipeShoppingSyncCommitJournal {
            try RecipeShoppingSyncCommitJournal(directory: journalDirectory, gate: gate, writerLease: lease, container: XCTUnwrap(container),
                defaults: projection ?? defaults, authorize: { [self] candidate in
                    guard admitted == candidate, receipt == candidate else { throw Injected.unauthorized }
                    guard try AccountGenerationReceiptStore(directory: root).read() == candidate else { throw Injected.unauthorized }
                    try gate.validateWriter(lease)
                }, validateWriterRouting: { [self] in
                    guard writersBound else { throw Injected.writersUnbound }
                }, save: save, checkpoint: checkpoint)
        }
        func stage(_ title: String) throws -> RecipeShoppingSyncStage {
            let recipe = RecipeCard(id: "r", title: title)
            let item = ShoppingItem(id: "s", name: title, quantity: 1, unit: "g")
            var meta = RecipeShoppingSyncStage.Metadata()
            meta.userID = "owner"; meta.recipeStamps = ["r": 10]; meta.shopStamps = ["s": 11]
            meta.recipeTombs = ["old-r": 12]; meta.shopTombs = ["old-s": 13]
            return try RecipeShoppingSyncStage.prepare(recipes: [recipe], shopping: [item], metadata: meta,
                remote: [], ownerID: "owner")
        }
        func image(_ stage: RecipeShoppingSyncStage) throws -> ArchiveRecipeShoppingImage {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return ArchiveRecipeShoppingImage(recipes: try stage.recipes.enumerated().map {
                ArchiveRawRecipeImage(id: $0.element.id, createdAt: $0.element.createdAt, position: $0.offset,
                    json: try encoder.encode($0.element))
            }, shopping: try stage.shopping.enumerated().map {
                ArchiveRawShoppingImage(id: $0.element.id, position: $0.offset, json: try encoder.encode($0.element))
            })
        }
        func seed(_ stage: RecipeShoppingSyncStage) throws {
            try UnifiedArchiveStartupRecovery.restoreRecipeShopping(image(stage), container: XCTUnwrap(container))
            defaults.set(try JSONEncoder().encode(stage.metadata), forKey: "ate.sync.v1")
        }
        func assertState(_ stage: RecipeShoppingSyncStage, file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(try UnifiedArchiveImportBinding.snapshotRecipeShopping(XCTUnwrap(container)), try image(stage), file: file, line: line)
            let bytes = try XCTUnwrap(defaults.data(forKey: "ate.sync.v1"), file: file, line: line)
            XCTAssertEqual(try JSONDecoder().decode(RecipeShoppingSyncStage.Metadata.self, from: bytes), stage.metadata, file: file, line: line)
        }
        func failCommit(_ stage: RecipeShoppingSyncStage, at boundary: RecipeShoppingSyncCommitJournal.Boundary) throws {
            let journal = try journal(checkpoint: { if $0 == boundary { throw Injected.crash } })
            XCTAssertThrowsError(try gate.withWriterEffect(lease) { try journal.commit(stage, receipt: receipt) })
        }
        func recover() throws -> Bool {
            let journal = try journal()
            return try gate.withWriterEffect(lease) { try journal.recoverAndProject() }
        }
    }

    func testEveryCommitBoundaryReopensRealStoreAndReplaysWithoutCloudPut() throws {
        for boundary in RecipeShoppingSyncCommitJournal.Boundary.allCases {
            let fixture = try Fixture(); defer { fixture.cleanup() }
            let old = try fixture.stage("Before"), new = try fixture.stage("After")
            try fixture.seed(old)
            try fixture.failCommit(new, at: boundary)
            fixture.close()
            try fixture.reopen()
            if boundary != .beforeIntentWrite { fixture.defaults.removeObject(forKey: "ate.sync.v1") }
            _ = try fixture.recover()
            try fixture.assertState(boundary == .beforeIntentWrite ? old : new)
            XCTAssertFalse(try fixture.recover(), "replay/authority projection is idempotent")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journalDirectory.appendingPathComponent("pending-v1.json").path))
        }
    }
    func testActualInjectedContextSaveFailureKeepsIntentAndOldRowsThenReplaysOnReopen() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let old = try fixture.stage("Before"), new = try fixture.stage("After")
        try fixture.seed(old)
        do {
            let journal = try fixture.journal(save: { _ in throw Injected.crash })
            XCTAssertThrowsError(try fixture.gate.withWriterEffect(fixture.lease) { try journal.commit(new, receipt: fixture.receipt) })
        }
        fixture.close(); try fixture.reopen()
        try fixture.assertState(old)
        XCTAssertTrue(try fixture.recover())
        try fixture.assertState(new)
    }
    func testForeignUnknownAndAdvancedAdmissionNeverReplayOrRetireEvidence() throws {
        for admission in [AccountGenerationPolicy.Receipt?.none,
                          .some(.init(ownerID: "foreign", generation: 3)), .some(.init(ownerID: "owner", generation: 4))] {
            let fixture = try Fixture(); defer { fixture.cleanup() }
            let old = try fixture.stage("Before"), new = try fixture.stage("After")
            try fixture.seed(old); try fixture.failCommit(new, at: .afterIntentWrite)
            let pending = fixture.journalDirectory.appendingPathComponent("pending-v1.json")
            let bytes = try Data(contentsOf: pending)
            fixture.close(); try fixture.reopen(); fixture.admitted = admission
            XCTAssertThrowsError(try fixture.recover())
            XCTAssertEqual(try Data(contentsOf: pending), bytes)
            try fixture.assertState(old)
        }
    }
    func testUnboundWriterInvariantBlocksCommitAndRetirement() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let old = try fixture.stage("Before"), new = try fixture.stage("After")
        try fixture.seed(old); try fixture.failCommit(new, at: .afterDefaultsWrite)
        fixture.writersBound = false
        XCTAssertThrowsError(try fixture.recover())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.journalDirectory.appendingPathComponent("pending-v1.json").path))
        fixture.writersBound = true
        XCTAssertTrue(try fixture.recover())
        try fixture.assertState(new)
    }
    func testCorruptTempEvidenceBlocksWithoutMutation() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let old = try fixture.stage("Before")
        try fixture.seed(old)
        let temp = fixture.journalDirectory.appendingPathComponent("pending-v1.json.tmp")
        let bytes = Data("partial intent".utf8); try bytes.write(to: temp)
        XCTAssertThrowsError(try fixture.recover())
        XCTAssertEqual(try Data(contentsOf: temp), bytes)
        try fixture.assertState(old)
    }
    func testProtocolItselfRejectsStaleOriginalGateWithoutCallerWrapping() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let old = try fixture.stage("Before"), new = try fixture.stage("After")
        try fixture.seed(old)
        let journal = try fixture.journal()
        try fixture.gate.invalidateWriters()
        XCTAssertThrowsError(try journal.commit(new, receipt: fixture.receipt))
        XCTAssertThrowsError(try journal.recoverAndProject())
        try fixture.assertState(old)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journalDirectory.appendingPathComponent("pending-v1.json").path))
    }

    func testDefaultsProjectionFailureRetainsIntentAndDurableAuthorityForReopen() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let old = try fixture.stage("Before"), new = try fixture.stage("After")
        try fixture.seed(old)
        do {
            let rejecting = try XCTUnwrap(RejectingProjection(suiteName: fixture.suite))
            let journal = try fixture.journal(projection: rejecting)
            XCTAssertThrowsError(try fixture.gate.withWriterEffect(fixture.lease) { try journal.commit(new, receipt: fixture.receipt) })
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.journalDirectory.appendingPathComponent("pending-v1.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.journalDirectory.appendingPathComponent("metadata-v1.json").path))
        fixture.close(); try fixture.reopen()
        XCTAssertTrue(try fixture.recover())
        try fixture.assertState(new)
    }

    func testClearAllInventoryErasesPendingAuthorityAndTempPersonalBytes() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.failCommit(fixture.stage("After"), at: .afterAuthorityWrite)
        let journal = try fixture.journal()
        let component = journal.clearAllComponent(validateResetGate: { try fixture.gate.validateResetGate() })
        try fixture.gate.acquireResetGate(); defer { fixture.gate.releaseResetGate() }
        let report = try ClearAllLocalData.execute([component], requiredNames: [component.name],
            validateWriterGate: { try fixture.gate.validateResetGate() })
        XCTAssertTrue(report.complete)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.journalDirectory.path).isEmpty)
    }
}
