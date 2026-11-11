import XCTest
@testable import Ate

/// #245 slice B: non-destructive existing-install reconciliation. A wipe is never
/// automatic; adoption stamps only at generation 0 after verified preservation.
@MainActor
final class JournalInstallReconciliationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var root: URL!
    private var control: FileResetControlPersistence!
    private var receipts: AccountGenerationReceiptStore!
    private var preservationDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "JournalInstallReconciliationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        root = requested.resolvingSymlinksInPath().standardizedFileURL
        control = FileResetControlPersistence(directory: root)
        receipts = try AccountGenerationReceiptStore(directory: root)
        preservationDir = root.appendingPathComponent("AdoptionPreservation", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        super.tearDown()
    }

    private let localIdentity = "local-store-identity"
    private func session(_ userID: String) -> AuthSession {
        AuthSession(accessToken: "a", refreshToken: "r", expiresAt: 4_102_444_800, userID: userID, email: "e@example.com")
    }

    private enum SnapshotStub {
        case generation(Int64)
        case contractMissing
        case unverifiable
    }

    private func makeReconciliation(snapshotStub: SnapshotStub,
                                    currentSession: @escaping () -> AuthSession?) -> JournalInstallReconciliation {
        JournalInstallReconciliation(
            receiptStore: receipts, control: control, preservationDirectory: preservationDir,
            legacyDiary: NutritionDiaryRepository(defaults: defaults),
            goals: NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
            snapshot: { _ in
                switch snapshotStub {
                case .generation(let g): return AccountSnapshot(generation: g, rows: [])
                case .contractMissing: throw ResetRPCError.contractMissing
                case .unverifiable: throw ResetRPCError.outcomeUnverified("simulated lost response")
                }
            },
            currentSession: currentSession,
            localIdentity: localIdentity,
            stampEffect: { work in try work() })
    }

    private func assertBlocked(_ message: String, _ expression: () async throws -> JournalInstallReconciliation.Decision,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await expression()
            XCTFail("expected blocked(\(message))", file: file, line: line)
        } catch let error as JournalStartupAuthorizationError {
            guard case .blocked(let reason) = error else {
                return XCTFail("expected .blocked, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(reason, message, file: file, line: line)
        } catch {
            XCTFail("expected JournalStartupAuthorizationError, got \(error)", file: file, line: line)
        }
    }

    func testSignedOutAdoptionStampsLocalReceiptAndPreservesLegacyBytes() async throws {
        let diaryBytes = Data("legacy diary payload".utf8)
        let goalsBytes = Data(#"{"energyKcal":2000}"#.utf8)
        defaults.set(diaryBytes, forKey: "ate.nutritionDiary.v1")
        defaults.set(goalsBytes, forKey: "ate.nutritionGoals.v1")

        let decision = try await makeReconciliation(snapshotStub: .generation(0), currentSession: { nil }).reconcile()
        XCTAssertEqual(decision, .adoptedExistingInstall)
        XCTAssertEqual(try receipts.read(), .init(ownerID: localIdentity, generation: 0))

        let manifestURL = preservationDir.appendingPathComponent(JournalInstallReconciliation.preservationFileName)
        let manifest = try JSONDecoder().decode(JournalInstallReconciliation.PreservationManifest.self,
                                                from: Data(contentsOf: manifestURL))
        XCTAssertEqual(Set(manifest.items.map(\.name)), ["nutrition-diary-v1", "nutrition-goals-legacy-defaults"])
        XCTAssertEqual(manifest.items.first { $0.name == "nutrition-diary-v1" }?.bytes, diaryBytes)
        XCTAssertEqual(manifest.items.first { $0.name == "nutrition-goals-legacy-defaults" }?.bytes, goalsBytes)
    }

    func testSignedInAdoptionAtGenerationZeroStampsAccountReceipt() async throws {
        let decision = try await makeReconciliation(snapshotStub: .generation(0),
                                                    currentSession: { self.session("user-1") }).reconcile()
        XCTAssertEqual(decision, .adoptedExistingInstall)
        XCTAssertEqual(try receipts.read(), .init(ownerID: "user-1", generation: 0))
    }

    func testAdoptionRefusedWhenAResetAlreadyCommitted() async throws {
        await assertBlocked("remote reset committed; confirmed local erase required") {
            try await makeReconciliation(snapshotStub: .generation(1),
                                         currentSession: { self.session("user-1") }).reconcile()
        }
        XCTAssertNil(try receipts.read(), "A blocked adoption must never stamp a receipt")
    }

    func testAbsentResetContractBlocksWhenSignedIn() async throws {
        // A missing reset contract does not establish the server epoch: it can never
        // stand in for generation 0. Signed in + unverifiable snapshot blocks, no mutation.
        await assertBlocked("account snapshot unverifiable") {
            try await makeReconciliation(snapshotStub: .contractMissing,
                                         currentSession: { self.session("user-1") }).reconcile()
        }
        XCTAssertNil(try receipts.read(), "A blocked adoption must never stamp a receipt")
    }

    func testAbsentResetContractIsIrrelevantWhenSignedOut() async throws {
        // Signed-out adoption never consults the server, so a missing contract cannot
        // block it; the stamped receipt is the local identity at generation 0.
        let decision = try await makeReconciliation(snapshotStub: .contractMissing,
                                                    currentSession: { nil }).reconcile()
        XCTAssertEqual(decision, .adoptedExistingInstall)
        XCTAssertEqual(try receipts.read(), .init(ownerID: localIdentity, generation: 0))
    }

    func testUnverifiableSnapshotBlocksWithoutMutation() async throws {
        await assertBlocked("account snapshot unverifiable") {
            try await makeReconciliation(snapshotStub: .unverifiable,
                                         currentSession: { self.session("user-1") }).reconcile()
        }
        XCTAssertNil(try receipts.read())
    }

    func testMatchingReceiptProceedsOfflineAndOnline() async throws {
        try receipts.save(.init(ownerID: "user-1", generation: 0))
        let offline = try await makeReconciliation(snapshotStub: .unverifiable,
                                                   currentSession: { nil }).reconcile()
        // Offline with an account receipt: nothing new to check remotely; the existing
        // receipt fences writes and ordinary signed-out operation must not false-block.
        XCTAssertEqual(offline, .proceed)

        let online = try await makeReconciliation(snapshotStub: .generation(0),
                                                  currentSession: { self.session("user-1") }).reconcile()
        XCTAssertEqual(online, .proceed)
    }

    func testRemoteResetPastReceiptBlocks() async throws {
        try receipts.save(.init(ownerID: "user-1", generation: 0))
        await assertBlocked("remote reset committed; confirmed local erase required") {
            try await makeReconciliation(snapshotStub: .generation(1),
                                         currentSession: { self.session("user-1") }).reconcile()
        }
        XCTAssertEqual(try receipts.read(), .init(ownerID: "user-1", generation: 0), "no mutation on blocked paths")
    }

    func testRegressedRemoteGenerationBlocks() async throws {
        try receipts.save(.init(ownerID: "user-1", generation: 2))
        await assertBlocked("remote generation regressed") {
            try await makeReconciliation(snapshotStub: .generation(1),
                                         currentSession: { self.session("user-1") }).reconcile()
        }
    }

    func testFirstSignInTransfersLocalReceiptToAccount() async throws {
        try receipts.save(.init(ownerID: localIdentity, generation: 0))
        let decision = try await makeReconciliation(snapshotStub: .generation(0),
                                                    currentSession: { self.session("user-1") }).reconcile()
        XCTAssertEqual(decision, .adoptedAccountOwnership)
        XCTAssertEqual(try receipts.read(), .init(ownerID: "user-1", generation: 0))
    }

    func testDifferentAccountBlocksAndPreservesReceipt() async throws {
        try receipts.save(.init(ownerID: "user-2", generation: 0))
        await assertBlocked("local records belong to a different account") {
            try await makeReconciliation(snapshotStub: .generation(0),
                                         currentSession: { self.session("user-1") }).reconcile()
        }
        XCTAssertEqual(try receipts.read(), .init(ownerID: "user-2", generation: 0))
    }

    func testPresentResetControlBlocks() async throws {
        try control.write(Data("{\"phase\":\"requested\"}".utf8))
        await assertBlocked("a reset control record is present") {
            try await makeReconciliation(snapshotStub: .generation(0), currentSession: { nil }).reconcile()
        }
        XCTAssertNil(try receipts.read())
    }

    func testCorruptReceiptBlocks() async throws {
        try Data("not json".utf8).write(to: root.appendingPathComponent("account-generation-v1.json"))
        await assertBlocked("generation receipt unreadable") {
            try await makeReconciliation(snapshotStub: .generation(0), currentSession: { nil }).reconcile()
        }
    }

    func testAdoptionWithoutLegacyBytesWritesNoManifest() async throws {
        let decision = try await makeReconciliation(snapshotStub: .generation(0), currentSession: { nil }).reconcile()
        XCTAssertEqual(decision, .adoptedExistingInstall)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: preservationDir.appendingPathComponent(JournalInstallReconciliation.preservationFileName).path))
    }

    func testSessionChangeDuringSnapshotAwaitBlocks() async throws {
        let box = LockedSession(value: session("user-1"))
        let reconciliation = JournalInstallReconciliation(
            receiptStore: receipts, control: control, preservationDirectory: preservationDir,
            legacyDiary: NutritionDiaryRepository(defaults: defaults),
            goals: NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
            snapshot: { _ in
                box.value = self.session("user-2")   // account switches mid-await
                return AccountSnapshot(generation: 0, rows: [])
            },
            currentSession: { box.value },
            localIdentity: localIdentity,
            stampEffect: { work in try work() })
        await assertBlocked("signed-in account changed during startup") {
            try await reconciliation.reconcile()
        }
        XCTAssertNil(try receipts.read())
    }

    func testReceiptChangeDuringSnapshotAwaitBlocks() async throws {
        let receipts = self.receipts!
        let reconciliation = JournalInstallReconciliation(
            receiptStore: receipts, control: control, preservationDirectory: preservationDir,
            legacyDiary: NutritionDiaryRepository(defaults: defaults),
            goals: NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
            snapshot: { _ in
                try receipts.save(.init(ownerID: "user-9", generation: 3))   // another writer stamps mid-await
                return AccountSnapshot(generation: 0, rows: [])
            },
            currentSession: { self.session("user-1") },
            localIdentity: localIdentity,
            stampEffect: { work in try work() })
        await assertBlocked("generation receipt changed during startup") {
            try await reconciliation.reconcile()
        }
        XCTAssertEqual(try self.receipts.read(), .init(ownerID: "user-9", generation: 3),
                       "The other writer's receipt must be preserved, never overwritten")
    }
}

private final class LockedSession {
    var value: AuthSession?
    init(value: AuthSession?) { self.value = value }
}
