import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalProductionAdmissionTests: XCTestCase {
    private func session(_ id: String = "account", token: String = "token") -> AuthSession {
        .init(accessToken: token, refreshToken: "fixture", expiresAt: 4_102_444_800, userID: id, email: "fixture@example.invalid")
    }
    func testRecoveryOwnerPreflightCoversLocalAdoptionMatchingAndForeignResetRefusal() throws {
        func owner(_ session: AuthSession?, _ receipt: AccountGenerationPolicy.Receipt?, _ remote: Int64?) throws -> String {
            try FoodJournalProductionAdmission.recoveryOwner(session: session, receipt: receipt, remoteGeneration: remote, localIdentity: "local")
        }
        XCTAssertEqual(try owner(nil, nil, nil), "local")
        XCTAssertEqual(try owner(nil, .init(ownerID: "prior", generation: 3), nil), "prior")
        XCTAssertEqual(try owner(session(), nil, 0), "account")
        XCTAssertEqual(try owner(session(), .init(ownerID: "account", generation: 2), 2), "account")
        XCTAssertEqual(try owner(session(), .init(ownerID: "local", generation: 2), 2), "local", "Recover old ownership before adoption")
        XCTAssertThrowsError(try owner(session(), nil, nil))
        XCTAssertThrowsError(try owner(session(), nil, 1))
        XCTAssertThrowsError(try owner(session(), .init(ownerID: "foreign", generation: 2), 2))
        XCTAssertThrowsError(try owner(session(), .init(ownerID: "account", generation: 2), 3))
        XCTAssertThrowsError(try owner(session(), .init(ownerID: "account", generation: 2), 1))
        XCTAssertThrowsError(try owner(session(), .init(ownerID: "account", generation: 2), -1))
    }
    private func fixture(_ run: (URL, UserDefaults, AccountWriterGate, UUID, FileResetControlPersistence,
                                AccountGenerationReceiptStore, FoodJournalDiskResources) async throws -> Void) async throws {
        let suite = "ProductionAdmission-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let control = FileResetControlPersistence(directory: root)
        let receipts = try AccountGenerationReceiptStore(directory: root)
        let gate = try AccountWriterGate(directory: root, resetControlExists: { try control.read() != nil })
        let resources = try FoodJournalDiskResources(defaults: defaults,
            goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
            locations: .init(storeFileURL: root.appendingPathComponent("journal.store"),
                mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
                repairBackupDirectory: root.appendingPathComponent("repair"), preservationDirectory: root.appendingPathComponent("preservation")),
            recipeConfiguration: ModelConfiguration(url: root.appendingPathComponent("recipes.store")),
            journalConfiguration: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
        try await run(root, defaults, gate, gate.captureWriter(), control, receipts, resources)
    }
    func testSignedOutAdmissionRecoversThenPreservesAndStampsLocalProofWithoutSnapshot() async throws {
        try await fixture { root, defaults, gate, lease, control, receipts, resources in
            let bytes = Data("legacy bytes".utf8)
            defaults.set(bytes, forKey: NutritionDiaryRepository.storageKey)
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: AdmissionArchive(), localIdentity: "local", currentSession: { nil },
                snapshot: { _ in XCTFail("Signed-out admission must not call server"); throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            XCTAssertEqual(try receipts.read(), .init(ownerID: "local", generation: 0))
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), bytes)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("preservation").appendingPathComponent(JournalInstallReconciliation.preservationFileName).path))
            try admission.validate(admittedLease: lease)
            let owner = try admission.bindOwner(admittedLease: lease, afterRestoreCommit: {})
            XCTAssertTrue(owner.runtime.defaults === defaults)
            XCTAssertEqual(try owner.runtime.journal.readReflections().count, 0)
        }
    }
    private func emptyArchiveData() throws -> Data {
        try JSONEncoder().encode(AteUnifiedArchive(recipes: [], shoppingItems: [],
            nutritionDiaryEntries: [], nutritionGoals: DailyNutritionGoals(), appSettings: AppSettings(),
            timerPreferences: TimerPrefs(), journal: JournalArchive(entries: [], media: [:])))
    }
    func testRetainedGraphSharesActualDomainsAndQuiescedImportUsesReceiptProof() async throws {
        try await fixture { root, defaults, gate, lease, control, receipts, resources in
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: ArchiveNestedGenerationBoundary(directory: root), localIdentity: "local",
                currentSession: { nil }, snapshot: { _ in throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
            XCTAssertThrowsError(try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {}))
            XCTAssertTrue(graph.runtime.defaults === defaults)
            XCTAssertTrue(graph.resetInventory.journal === graph.runtime.journal)
            XCTAssertTrue(graph.resetInventory.defaults === defaults)
            var drained = false
            try graph.lifecycle.register(cancel: {}, drain: { await Task.yield(); drained = true })
            _ = try await graph.archiveImport.importData(self.emptyArchiveData())
            XCTAssertTrue(drained)
            XCTAssertEqual(graph.lifecycle.state, .quiesced)
            XCTAssertThrowsError(try graph.validate())
            do { _ = try await graph.archiveExport.export(); XCTFail("Old graph cannot export after import") } catch { }
            XCTAssertEqual(try receipts.read(), .init(ownerID: "local", generation: 0))
        }
    }
    func testHostSessionTransitionRetiresDrainsHandsOffThenRebuildsExactlyOnce() async throws {
        try await fixture { root, _, gate, lease, control, receipts, resources in
            var current: AuthSession?
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: ArchiveNestedGenerationBoundary(directory: root), localIdentity: "local",
                currentSession: { current }, snapshot: { _ in throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
            var order: [String] = []
            try graph.lifecycle.register(cancel: { order.append("cancel") }, drain: { order.append("drain") })
            let host = FoodJournalGraphTransitions(graph: graph, retireEditors: { order.append("editors") },
                rebuild: { order.append("rebuild") })
            try await host.changeSession {
                XCTAssertEqual(graph.lifecycle.state, .quiesced)
                order.append("session")
                current = self.session()
            }
            XCTAssertEqual(order, ["editors", "cancel", "drain", "session", "rebuild"])
            XCTAssertThrowsError(try graph.validate())
            do { try await host.changeSession { XCTFail("Cannot reuse old host") }; XCTFail("Must refuse") } catch { }
            XCTAssertEqual(order.count, 5)
        }
    }

    func testHostRefusesMalformedImportBeforeRetiringAndFailureNeverRebuilds() async throws {
        try await fixture { root, _, gate, lease, control, receipts, resources in
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: ArchiveNestedGenerationBoundary(directory: root), localIdentity: "local",
                currentSession: { nil }, snapshot: { _ in throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
            var retired = false, rebuilt = false
            let host = FoodJournalGraphTransitions(graph: graph, retireEditors: { retired = true }, rebuild: { rebuilt = true })
            do { _ = try await host.importArchive(Data("invalid".utf8)); XCTFail("Malformed input must fail") } catch { }
            XCTAssertFalse(retired); XCTAssertFalse(rebuilt)
            try graph.validate()
            enum Refused: Error { case reset }
            do { try await host.reset { throw Refused.reset }; XCTFail("Unverified reset must fail") } catch { }
            XCTAssertTrue(retired); XCTAssertFalse(rebuilt)
            XCTAssertThrowsError(try graph.validate())
        }
    }

    func testHostImportRecipeLinksFailureStillRevokesCancelsDrainsAndPreservesOriginalError() async throws {
        try await fixture { root, defaults, gate, lease, control, receipts, resources in
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: ArchiveNestedGenerationBoundary(directory: root), localIdentity: "local",
                currentSession: { nil }, snapshot: { _ in throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
            defaults.set(Data("unreadable recipe links".utf8), forKey: NutritionRecipeAssociationStore.storageKey)
            var order: [String] = []
            try graph.lifecycle.register(cancel: { order.append("cancel") }, drain: {
                await Task.yield()
                order.append("drain")
            })
            let host = FoodJournalGraphTransitions(graph: graph, retireEditors: { order.append("editors") },
                rebuild: { order.append("rebuild") })
            do {
                _ = try await host.importArchive(self.emptyArchiveData())
                XCTFail("Unarchived links must refuse")
            } catch FoodJournalArchiveImport.Failure.recipeLinksNotArchived {
                // Original pre-quiescence error, not masked by cleanup.
            } catch { XCTFail("Original import error lost: \(error)") }
            XCTAssertEqual(order, ["editors", "cancel", "drain"])
            XCTAssertEqual(graph.lifecycle.state, .quiesced)
            XCTAssertThrowsError(try graph.validate())
            XCTAssertThrowsError(try gate.validateWriter(lease))
            XCTAssertEqual(defaults.data(forKey: NutritionRecipeAssociationStore.storageKey), Data("unreadable recipe links".utf8))
            do { try await host.changeSession { XCTFail("Retired graph cannot hand off") }; XCTFail("Must refuse") } catch { }
            XCTAssertEqual(order, ["editors", "cancel", "drain"])
        }
    }

    func testReceiptMutationDuringDrainRefusesImportBeforeTransaction() async throws {
        try await fixture { root, _, gate, lease, control, receipts, resources in
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: ArchiveNestedGenerationBoundary(directory: root), localIdentity: "local",
                currentSession: { nil }, snapshot: { _ in throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
            try graph.lifecycle.register(cancel: {}, drain: {
                try receipts.save(.init(ownerID: "foreign", generation: 0))
            })
            do { _ = try await graph.archiveImport.importData(self.emptyArchiveData()); XCTFail("Changed receipt must refuse") } catch { }
            XCTAssertEqual(graph.lifecycle.state, .quiesced)
            let replacement = try gate.captureWriter()
            try gate.withArchiveRecoveryLease(replacement) { archive in
                XCTAssertFalse(try DiskArchiveRecoveryJournal(lease: archive).hasUnresolvedTransactions())
            }
        }
    }
    func testRetainedGraphRefusesSameOwnerTokenChangeBeforeExportOrImport() async throws {
        try await fixture { root, _, gate, lease, control, receipts, resources in
            var current: AuthSession? = self.session(token: "first")
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: ArchiveNestedGenerationBoundary(directory: root), localIdentity: "local",
                currentSession: { current }, snapshot: { _ in AccountSnapshot(generation: 0, rows: []) })
            try await admission.reconcile(admittedLease: lease)
            let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
            current = self.session(token: "second")
            XCTAssertThrowsError(try graph.validate())
            do { _ = try await graph.archiveExport.export(); XCTFail("Stale export must refuse") } catch { }
            do { _ = try await graph.archiveImport.importData(self.emptyArchiveData()); XCTFail("Stale import must refuse") } catch { }
            XCTAssertEqual(graph.lifecycle.state, .active, "Identity refusal occurs before quiescence")
        }
    }

    func testMissingSignedInContractBlocksBeforePersonalOpenOrReceiptStamp() async throws {
        try await fixture { root, _, gate, lease, control, receipts, resources in
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: AdmissionArchive(), localIdentity: "local", currentSession: { self.session() },
                snapshot: { _ in throw ResetRPCError.contractMissing })
            do { try await admission.reconcile(admittedLease: lease); XCTFail("Missing contract is not generation zero") } catch { }
            XCTAssertNil(try receipts.read())
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("journal.store").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("preservation").path))
            XCTAssertThrowsError(try admission.validate(admittedLease: lease))
        }
    }
    func testSameAccountTokenChangeAcrossAwaitBlocksBeforeRecoveryAndStamp() async throws {
        try await fixture { root, _, gate, lease, control, receipts, resources in
            var current: AuthSession? = self.session(token: "before")
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: AdmissionArchive(), localIdentity: "local", currentSession: { current },
                snapshot: { _ in current = self.session(token: "after"); return AccountSnapshot(generation: 0, rows: []) })
            do { try await admission.reconcile(admittedLease: lease); XCTFail("Same userID is insufficient proof") } catch { }
            XCTAssertNil(try receipts.read())
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("journal.store").path))
        }
    }
    func testFinalProofRefusesReceiptMutationAndRotatedLease() async throws {
        try await fixture { _, _, gate, lease, control, receipts, resources in
            let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
                resources: resources, archive: AdmissionArchive(), localIdentity: "local", currentSession: { nil },
                snapshot: { _ in throw ResetRPCError.contractMissing })
            try await admission.reconcile(admittedLease: lease)
            try gate.withWriterEffect(lease) { try receipts.save(.init(ownerID: "foreign", generation: 0)) }
            XCTAssertThrowsError(try admission.validate(admittedLease: lease))
            XCTAssertThrowsError(try admission.bindOwner(admittedLease: lease, afterRestoreCommit: {}))
            try gate.invalidateWriters()
            XCTAssertThrowsError(try admission.validate(admittedLease: lease))
        }
    }
}

private final class AdmissionArchive: ArchiveNestedLeaseBoundary {
    func withNestedLease<T>(_ work: () throws -> T) throws -> T { try work() }
}
