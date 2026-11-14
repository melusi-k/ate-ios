import XCTest
import SwiftData
@testable import Ate

/// Issue #34 user-data sync: pure planner and payload coverage. The planner reuses
/// `SyncMerge` (the recipe/shopping LWW engine), so these tests pin the family-specific
/// behavior: deletion detection from persisted stamps, apply/push partitioning, payload
/// round-trips, stamp derivation and backend-not-migrated classification.
final class UserDataSyncTests: XCTestCase {

    private func rec(_ kind: String, _ id: String, _ stamp: Int64, deleted: Bool = false, data: Data? = nil) -> SyncRecord {
        SyncRecord(user_id: "u1", kind: kind, id: id, data: data.map { AnyJSON($0) }, updated_at: stamp, deleted: deleted)
    }

    // MARK: - Deletion detection (localWithDeletes)

    func testLocalWithDeletesTombstonesPreviouslySyncedMissingIDs() {
        let local = UserDataSyncPlanner.localWithDeletes(
            data: ["b": Data([1])],
            stamps: ["b": 10],
            tombstones: [:],
            previouslySynced: ["a": 5, "b": 10],
            now: 100)
        XCTAssertNil(local.stamps["a"])
        XCTAssertEqual(local.tombstones["a"], 100)
        XCTAssertEqual(local.data["b"], Data([1]))
        XCTAssertEqual(local.stamps["b"], 10)
    }

    func testLocalWithDeletesKeepsExistingTombstoneStamp() {
        // A re-delete is not a newer fact: the original tombstone stamp survives.
        let local = UserDataSyncPlanner.localWithDeletes(
            data: [:], stamps: [:], tombstones: ["a": 40],
            previouslySynced: ["a": 5], now: 100)
        XCTAssertEqual(local.tombstones["a"], 40)
    }

    func testLocalWithDeletesIgnoresNeverSyncedLocalData() {
        // Rows that were never synced (fresh local content) are upserts, not deletes.
        let local = UserDataSyncPlanner.localWithDeletes(
            data: ["new": Data([1])], stamps: ["new": 7], tombstones: [:],
            previouslySynced: [:], now: 100)
        XCTAssertTrue(local.tombstones.isEmpty)
        XCTAssertEqual(local.stamps["new"], 7)
    }

    // MARK: - plan: push/apply partitioning

    func testPlanPushesLocalNewerRowsAndNothingApplies() {
        let local = SyncMerge.Local(data: ["j1": Data([1])], stamps: ["j1": 200], tombstones: [:])
        let remote = [rec("journal", "j1", 100)]
        let plan = UserDataSyncPlanner.plan(kind: "journal", userID: "u1", local: local, remote: remote)
        XCTAssertTrue(plan.applyUpserts.isEmpty)
        XCTAssertTrue(plan.applyDeletes.isEmpty)
        XCTAssertEqual(plan.push.count, 1)
        XCTAssertEqual(plan.push[0].id, "j1")
        XCTAssertFalse(plan.push[0].deleted)
        XCTAssertEqual(plan.push[0].kind, "journal")
    }

    func testPlanAppliesRemoteNewerRowsAndPushesNothing() {
        let payload = Data([9, 9, 9])
        let local = SyncMerge.Local(data: ["j1": Data([1])], stamps: ["j1": 100], tombstones: [:])
        let remote = [rec("journal", "j1", 200, data: payload)]
        let plan = UserDataSyncPlanner.plan(kind: "journal", userID: "u1", local: local, remote: remote)
        XCTAssertEqual(plan.applyUpserts["j1"], payload)
        XCTAssertTrue(plan.push.isEmpty)
        XCTAssertEqual(plan.stamps["j1"], 200)
    }

    func testPlanRemoteTombstoneDeletesLocally() {
        let local = SyncMerge.Local(data: ["j1": Data([1])], stamps: ["j1": 100], tombstones: [:])
        let remote = [rec("journal", "j1", 300, deleted: true)]
        let plan = UserDataSyncPlanner.plan(kind: "journal", userID: "u1", local: local, remote: remote)
        XCTAssertEqual(plan.applyDeletes, ["j1"])
        XCTAssertEqual(plan.tombstones["j1"], 300)
        XCTAssertNil(plan.data["j1"])
    }

    func testPlanLocalTombstonePushesDelete() {
        let local = SyncMerge.Local(data: [:], stamps: [:], tombstones: ["j1": 400])
        let remote = [rec("journal", "j1", 100)]
        let plan = UserDataSyncPlanner.plan(kind: "journal", userID: "u1", local: local, remote: remote)
        XCTAssertEqual(plan.push.count, 1)
        XCTAssertTrue(plan.push[0].deleted)
        XCTAssertTrue(plan.applyUpserts.isEmpty)
    }

    func testPlanNoOpResyncPushesAndAppliesNothing() {
        let bytes = Data([1, 2, 3])
        let local = SyncMerge.Local(data: ["j1": bytes], stamps: ["j1": 500], tombstones: [:])
        let remote = [rec("journal", "j1", 500, data: bytes)]
        let plan = UserDataSyncPlanner.plan(kind: "journal", userID: "u1", local: local, remote: remote)
        XCTAssertTrue(plan.push.isEmpty)
        XCTAssertTrue(plan.applyUpserts.isEmpty)
        XCTAssertTrue(plan.applyDeletes.isEmpty)
    }

    // MARK: - Payloads

    func testJournalPayloadRoundTripsFullFidelity() throws {
        let payload = JournalEntrySyncPayload(
            id: "E1", createdAtMs: 1_700_000_000_000, prompt: "p", text: "hello", stateRaw: "balanced",
            recipeIDs: ["r1", "r2"], journalingSuggestionTitle: "t", momentDateMs: 1_700_000_100_000,
            sourceRaw: "ate", locationName: "Home", latitude: -26.2, longitude: 28.0,
            mediaFileNames: ["a.jpg"], editedAtMs: nil, kindRaw: "meal", dayKey: "2026-11-14",
            recipeSnapshotsRaw: "{\"v\":1}",
            meal: JournalMealSyncPayload(mealRaw: "lunch", foodName: "Pap", quantity: 1, quantityUnit: "cup",
                                         servings: 1, sourceRaw: "userProvided", sourceName: "",
                                         sourceIdentifier: "", verificationNote: "",
                                         energyKcal: 500, proteinGrams: nil, carbohydratesGrams: 90,
                                         fatGrams: 5, fibreGrams: nil))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(JournalEntrySyncPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
        // Nil nutrients stay nil - unknown is never replaced with an estimate.
        XCTAssertNil(decoded.meal?.proteinGrams)
        XCTAssertNil(decoded.meal?.fibreGrams)
    }

    func testJournalStampPrefersEditedAt() {
        var payload = JournalEntrySyncPayload(
            id: "E1", createdAtMs: 100, prompt: "", text: "", stateRaw: "", recipeIDs: [],
            journalingSuggestionTitle: nil, momentDateMs: nil, sourceRaw: "ate", locationName: nil,
            latitude: nil, longitude: nil, mediaFileNames: [], editedAtMs: nil, kindRaw: "reflection",
            dayKey: nil, recipeSnapshotsRaw: nil, meal: nil)
        XCTAssertEqual(payload.stampMs, 100)
        payload.editedAtMs = 250
        XCTAssertEqual(payload.stampMs, 250)
    }

    func testInsightRecordAndGoalsEncodeAsSyncPayloads() throws {
        // The families sync the existing persisted types verbatim; pin that they round-trip
        // through the jsonb `data` column shape unchanged.
        let insight = InsightLifecycleRecord(status: .snoozed, evidenceFingerprint: "fp",
                                             updatedAt: Date(timeIntervalSince1970: 1700),
                                             snoozedUntil: Date(timeIntervalSince1970: 1800))
        let insightData = try JSONEncoder().encode(insight)
        XCTAssertEqual(try JSONDecoder().decode(InsightLifecycleRecord.self, from: insightData), insight)

        let goals = DailyNutritionGoals(energyKcal: 2200, proteinGrams: 120, carbohydratesGrams: nil,
                                        fatGrams: 70, fibreGrams: 30)
        let goalsData = try JSONEncoder().encode(goals)
        XCTAssertEqual(try JSONDecoder().decode(DailyNutritionGoals.self, from: goalsData), goals)
    }

    // MARK: - Backend-not-migrated classification

    func testCheckConstraintViolationIsFamilyUnavailable() {
        // The unmigrated backend rejects new kinds with 23514: local-only, retried next round.
        let classified = UserDataSyncError.classify(
            ResetRPCError.http(400, "23514: new row violates check constraint"))
        XCTAssertEqual(classified, .familyUnavailable("server does not accept this data kind yet (23514)"))
    }

    func testMissingContractIsFamilyUnavailable() {
        XCTAssertEqual(UserDataSyncError.classify(ResetRPCError.contractMissing),
                       .familyUnavailable("sync contract not deployed"))
    }

    func testStaleGenerationAbortsRound() {
        XCTAssertEqual(UserDataSyncError.classify(ResetRPCError.staleGeneration), .generationChanged)
    }

    func testOrdinaryHTTPErrorIsTransport() {
        let classified = UserDataSyncError.classify(ResetRPCError.http(503, "Service unavailable"))
        if case .transport = classified {} else { XCTFail("expected transport, got \(classified)") }
    }

    // MARK: - Kinds

    func testFamilyKindsMatchMigrationAllowList() {
        // supabase/migrations/20261114120000_user_data_sync_kinds.sql widens the CHECK to
        // exactly these values; a rename here must rename there.
        XCTAssertEqual(UserDataFamily.allCases.map(\.kind), ["journal", "insight", "goals"])
    }

    // MARK: - Fenced transport

    @MainActor
    private struct FencedHarness {
        let transport: FencedUserDataSyncTransport
        let session: AuthSession
        let dir: URL
        let requests: RequestLog
    }

    private final class RequestLog {
        var bodies: [[String: Any]] = []
        var paths: [String] = []
    }

    @MainActor
    private func makeFencedHarness(generation: Int64, receiptGeneration: Int64? = nil,
                                   rows: [[String: Any]] = [],
                                   gate suppliedGate: SyncCycleGate? = nil) throws -> FencedHarness {
        // Default arguments are evaluated outside this actor-isolated body.
        // Construct the default here; retain an injected shared gate unchanged.
        let gate = suppliedGate ?? SyncCycleGate()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("uds-\(UUID().uuidString)", isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let receipts = try AccountGenerationReceiptStore(directory: dir)
        try receipts.save(.init(ownerID: "u1", generation: receiptGeneration ?? generation))
        let session = AuthSession(accessToken: "tok", refreshToken: "ref",
                                  expiresAt: 4_000_000_000, userID: "u1", email: "u@example.test")
        let log = RequestLog()
        let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "k") { request in
            log.paths.append(request.url?.lastPathComponent ?? "")
            if let body = request.httpBody,
               let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                log.bodies.append(parsed)
            }
            if request.url?.lastPathComponent == "account_data_snapshot" {
                let data = try JSONSerialization.data(withJSONObject: ["generation": generation, "rows": rows])
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let fenced = GenerationFencedSync(rpc: rpc, currentSession: { session },
                                          captureWriter: { UUID() }, validateWriter: { _ in })
        return FencedHarness(transport: FencedUserDataSyncTransport(fenced: fenced, receipts: receipts,
                                                                    currentSession: { session }, validate: { },
                                                                    gate: gate),
                             session: session, dir: dir, requests: log)
    }

    private func journalRow(id: String, stamp: Int64, text: String) -> [String: Any] {
        ["user_id": "u1", "kind": "journal", "id": id, "data": ["text": text],
         "updated_at": stamp, "deleted": false]
    }

    @MainActor
    func testCycleGateExcludesOverlappingCyclesAndRecoversAbandoned() throws {
        let gate = SyncCycleGate()
        let first = try gate.acquire()
        // A second cycle is refused while the first holds the gate.
        XCTAssertThrowsError(try gate.acquire()) {
            XCTAssertEqual($0 as? SyncCycleGate.Failure, .cycleInProgress)
        }
        // Abandoned-cycle recovery: replace invalidates the orphan, whose later validate
        // fails as superseded instead of writing under a stale capture.
        let second = gate.replace()
        XCTAssertThrowsError(try gate.validate(first)) {
            XCTAssertEqual($0 as? SyncCycleGate.Failure, .superseded)
        }
        gate.release(second)
        _ = try gate.acquire()
    }

    @MainActor
    func testFamilyCycleIsRefusedWhileAnotherCycleHoldsTheGate() async throws {
        let gate = SyncCycleGate()
        let held = try gate.acquire()
        defer { gate.release(held) }
        let h = try makeFencedHarness(generation: 3, gate: gate)
        defer { try? FileManager.default.removeItem(at: h.dir) }
        do {
            _ = try await h.transport.cycle(session: h.session) { _, _, _ in [String]() }
            XCTFail("a family cycle must not start while another cycle holds the gate")
        } catch {
            XCTAssertEqual(UserDataSyncError.classify(error),
                           .transport("another account-data sync cycle is active"))
        }
        XCTAssertFalse(h.requests.paths.contains("account_data_snapshot"))
    }

    @MainActor
    func testFencedCycleSnapshotAuthorizesOneBatchPushWithItsGeneration() async throws {
        let h = try makeFencedHarness(generation: 3, rows: [journalRow(id: "j0", stamp: 100, text: "old")])
        defer { try? FileManager.default.removeItem(at: h.dir) }
        let record = SyncRecord(user_id: "u1", kind: "journal", id: "j1",
                                data: AnyJSON(Data("{\"text\":\"new\"}".utf8)), stampMs: 500, deleted: false)
        try await h.transport.cycle(session: h.session) { snapshot, push, _ in
            XCTAssertEqual(snapshot.generation, 3)
            XCTAssertEqual(snapshot.rows.map(\.id), ["j0"])
            try await push([record])
            XCTAssertEqual(h.requests.paths.filter { $0 == "put_user_recipe" }.count, 1)
            let putBody = try XCTUnwrap(h.requests.bodies.first { $0["p_kind"] as? String == "journal" })
            // The write carries the generation of the snapshot that authorized it - never a
            // silently fetched newer epoch.
            XCTAssertEqual(putBody["p_caller_generation"] as? Int, 3)
            XCTAssertEqual(putBody["p_id"] as? String, "j1")
            // Single use even on success: a second push in the same cycle is refused.
            do {
                try await push([record])
                XCTFail("a consumed authorization must not push twice")
            } catch {
                XCTAssertEqual(UserDataSyncError.classify(error),
                               .transport("push already consumed for this snapshot"))
            }
            return [String]()
        }
        // The cycle released the gate: the next round acquires it cleanly.
        _ = try await h.transport.cycle(session: h.session) { _, _, _ in [String]() }
    }

    @MainActor
    func testFencedCycleRejectsStaleReceipt() async throws {
        // The persisted receipt says the account is at generation 4 but the server answered
        // 3: a reset happened elsewhere. The cycle aborts as generationChanged before work.
        let h = try makeFencedHarness(generation: 3, receiptGeneration: 4)
        defer { try? FileManager.default.removeItem(at: h.dir) }
        do {
            _ = try await h.transport.cycle(session: h.session) { _, _, _ in [String]() }
            XCTFail("a stale receipt must abort the cycle")
        } catch {
            XCTAssertEqual(UserDataSyncError.classify(error), .generationChanged)
        }
    }

    // MARK: - Remote snapshot validation (Reviewer: strict, whole-snapshot, before any write)

    private func journalPayload(id: String, kindRaw: String = "reflection",
                                stateRaw: String = "", sourceRaw: String = "ate",
                                dayKey: String? = nil, createdAtMs: Int64 = 1_000_000,
                                editedAtMs: Int64? = nil,
                                mediaFileNames: [String] = [],
                                meal: JournalMealSyncPayload? = nil) -> JournalEntrySyncPayload {
        JournalEntrySyncPayload(id: id, createdAtMs: createdAtMs, prompt: "", text: "note",
                                stateRaw: stateRaw, recipeIDs: [], journalingSuggestionTitle: nil,
                                momentDateMs: nil, sourceRaw: sourceRaw, locationName: nil,
                                latitude: nil, longitude: nil, mediaFileNames: mediaFileNames,
                                editedAtMs: editedAtMs, kindRaw: kindRaw, dayKey: dayKey,
                                recipeSnapshotsRaw: nil, meal: meal)
    }

    private func mealPayload(mealRaw: String = "lunch", sourceRaw: String = "userProvided",
                             quantity: Double = 1, servings: Double = 1,
                             energyKcal: Double? = 500) -> JournalMealSyncPayload {
        JournalMealSyncPayload(mealRaw: mealRaw, foodName: "Pap", quantity: quantity,
                               quantityUnit: "cup", servings: servings, sourceRaw: sourceRaw,
                               sourceName: "", sourceIdentifier: "", verificationNote: "",
                               energyKcal: energyKcal, proteinGrams: nil, carbohydratesGrams: nil,
                               fatGrams: nil, fibreGrams: nil)
    }

    private func wire(_ kind: String, _ id: String, _ payload: Encodable,
                      stamp: Int64 = 1_000_000, deleted: Bool = false) throws -> SyncRecord {
        SyncRecord(user_id: "u1", kind: kind, id: id,
                   data: deleted ? nil : AnyJSON(try JSONEncoder().encode(payload)),
                   stampMs: Double(stamp), deleted: deleted)
    }

    private func assertRejected(_ rows: [SyncRecord], _ fragment: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try RemoteSnapshotValidator.validate(rows: rows), file: file, line: line) {
            guard case .remoteRejected(let detail)? = $0 as? UserDataSyncError else {
                XCTFail("expected remoteRejected, got \($0)", file: file, line: line); return
            }
            XCTAssertTrue(detail.contains(fragment), "\(detail) must mention \(fragment)", file: file, line: line)
        }
    }

    func testValidatorAcceptsValidRowsOfEveryFamily() throws {
        let rows: [SyncRecord] = [
            try wire("journal", "j1", journalPayload(id: "j1")),
            try wire("journal", "j2", journalPayload(id: "j2", kindRaw: "meal", dayKey: "2026-11-14",
                                                     meal: mealPayload())),
            // The wire stamp must equal the record's own updatedAt (stamp agreement).
            try wire("insight", "i1", InsightLifecycleRecord(status: .dismissed, evidenceFingerprint: "fp",
                                                             updatedAt: Date(timeIntervalSince1970: 1700),
                                                             snoozedUntil: nil), stamp: 1_700_000),
            try wire("goals", "current", DailyNutritionGoals(energyKcal: 2200, proteinGrams: nil,
                                                             carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)),
            // A tombstone carries no payload and is valid as identity + stamp only.
            SyncRecord(user_id: "u1", kind: "journal", id: "j3", data: nil, stampMs: 3_000, deleted: true),
            // Recipe/shopping rows belong to their own transport and are ignored.
            try wire("recipe", "r1", ["title": "Beans"]),
        ]
        XCTAssertNoThrow(try RemoteSnapshotValidator.validate(rows: rows))
    }

    func testValidatorRejectsWireStampDisagreement() throws {
        // The LWW clock on the row must be the payload's own version stamp (journal: its
        // editedAt ?? createdAt; insight: its updatedAt).
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1"), stamp: 999)],
                       "wire stamp disagrees")
        assertRejected([try wire("insight", "i1", InsightLifecycleRecord(status: .seen,
                                                                         evidenceFingerprint: "fp",
                                                                         updatedAt: Date(timeIntervalSince1970: 1700),
                                                                         snoozedUntil: nil))],
                       "wire stamp disagrees")
    }

    func testValidatorRequiresDayKeyForMeals() throws {
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal",
                                                                 meal: mealPayload()))],
                       "meal entry without a valid day key")
        // Reflections may carry no day key; a malformed one is still rejected.
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", dayKey: "2026-13-14"))],
                       "malformed day key")
    }

    func testValidatorRejectsPayloadIdMismatch() throws {
        // The planner keys by wire id; a payload claiming another id must not decode-apply.
        assertRejected([try wire("journal", "j1", journalPayload(id: "other"))], "does not match")
    }

    func testValidatorRejectsDuplicateAndEmptyIDs() throws {
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1")),
                        try wire("journal", "j1", journalPayload(id: "j1"))], "duplicate")
        assertRejected([SyncRecord(user_id: "u1", kind: "journal", id: "", data: nil,
                                   stampMs: 1, deleted: true)], "empty wire id")
    }

    func testValidatorRejectsMealConsistencyViolations() throws {
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "reflection",
                                                                 meal: mealPayload()))],
                       "reflection carrying a meal payload")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal"))],
                       "meal entry without a meal payload")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "snack"))],
                       "unknown entry kind")
    }

    func testValidatorRejectsUnknownEnumsAndBadDayKey() throws {
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", stateRaw: "wired"))],
                       "unknown health state")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", sourceRaw: "cloud"))],
                       "unknown entry source")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", dayKey: "14/11/2026"))],
                       "malformed day key")
    }

    func testValidatorRejectsBadStampsQuantitiesAndNutrients() throws {
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", createdAtMs: 0), stamp: 0)],
                       "non-positive creation stamp")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", createdAtMs: 500,
                                                                 editedAtMs: 400), stamp: 400)],
                       "edit stamp precedes creation stamp")
        assertRejected([SyncRecord(user_id: "u1", kind: "journal", id: "j1", data: nil,
                                   stampMs: -5, deleted: true)], "negative LWW stamp")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal",
                                                                 meal: mealPayload(quantity: 0)))],
                       "invalid quantity")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal",
                                                                 meal: mealPayload(servings: -1)))],
                       "invalid servings")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal",
                                                                 meal: mealPayload(energyKcal: -3)))],
                       "invalid nutrient value")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal",
                                                                 meal: mealPayload(mealRaw: "brunch")))],
                       "unknown meal slot")
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1", kindRaw: "meal",
                                                                 meal: mealPayload(sourceRaw: "labelScan")))],
                       "unknown nutrient source")
    }

    func testValidatorRejectsUnsafeMediaNamesAndMissingPayloads() throws {
        assertRejected([try wire("journal", "j1", journalPayload(id: "j1",
                                                                 mediaFileNames: ["../secret"]))],
                       "unsafe media file name")
        assertRejected([SyncRecord(user_id: "u1", kind: "journal", id: "j1", data: nil,
                                   stampMs: 1, deleted: false)], "live row without a payload")
        assertRejected([SyncRecord(user_id: "u1", kind: "journal", id: "j1",
                                   data: AnyJSON(Data("not json".utf8)), stampMs: 1, deleted: false)],
                       "undecodable payload")
    }

    func testValidatorRejectsBadGoalsAndInsightRows() throws {
        assertRejected([try wire("goals", "backup", DailyNutritionGoals())], "unexpected goals row id")
        assertRejected([try wire("goals", "current", DailyNutritionGoals(energyKcal: -1, proteinGrams: nil,
                                                                         carbohydratesGrams: nil, fatGrams: nil,
                                                                         fibreGrams: nil))], "invalid goal value")
        assertRejected([SyncRecord(user_id: "u1", kind: "insight", id: "i1",
                                   data: AnyJSON(Data("{}".utf8)), stampMs: 1, deleted: false)],
                       "undecodable payload")
    }
}

// MARK: - Staged round orchestration (Reviewer changes 1 + 2)

/// A controllable family transport: serves a fixed snapshot and lets each test decide what
/// the authorized upload and the pre-commit revalidation do.
/// Change 3 failure injection: goals storage whose writes throw a configurable number of
/// times. Accepted writes persist like the real store, so once the failures are exhausted
/// the journal's post-save readback (and the next replay) observe the driven image.
private final class WriteFailingGoalsStorage: FamilySyncGoalsFileStorage {
    var failures: Int
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var backing: FileNutritionGoalsStorage { FileNutritionGoalsStorage(fileURL: fileURL) }
    init(failures: Int = 1) { self.failures = failures }
    deinit { try? FileManager.default.removeItem(at: fileURL) }
    func read() throws -> Data? { try backing.read() }
    func write(_ data: Data) throws {
        if failures > 0 { failures -= 1; throw GoalsWriteFailure() }
        try backing.write(data)
    }
    func preserveCorruptData(_ data: Data) throws { try backing.preserveCorruptData(data) }
    func remove() throws { try backing.remove() }
    struct GoalsWriteFailure: Error {}
}

/// Change 4 failure injection: a goals store whose READS always fail, so the goals family
/// never stages and the round records a family failure.
private final class ReadFailingGoalsStorage: NutritionGoalsStorage {
    func read() throws -> Data? { throw GoalsReadFailure() }
    func write(_ data: Data) throws {}
    func preserveCorruptData(_ data: Data) throws {}
    func remove() throws {}
    struct GoalsReadFailure: Error {}
}

@MainActor
private final class FakeFamilyTransport: UserDataSyncTransport {
    var snapshot: AccountSnapshot
    /// The scope this transport would confirm against; defaults to the snapshot's
    /// generation under the fixture account, matching what the real fenced transport
    /// derives from the persisted generation receipt.
    var scope: AccountDataScope?
    var currentScope: AccountDataScope? { scope }
    var onPush: (([SyncRecord]) throws -> Void)?
    var onRevalidate: (() throws -> Void)?
    private(set) var pushAttempts = 0
    init(snapshot: AccountSnapshot) {
        self.snapshot = snapshot
        self.scope = AccountDataScope(ownerID: "u1", generation: snapshot.generation)
    }
    func cycle<R>(session: AuthSession,
                  work: (AccountSnapshot, ([SyncRecord]) async throws -> Void,
                         () throws -> Void) async throws -> R) async throws -> R {
        try await work(snapshot,
                       { records in self.pushAttempts += 1; try self.onPush?(records) },
                       { try self.onRevalidate?() })
    }
}

@MainActor
final class UserDataSyncOrchestrationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var savedSyncMeta: Data?
    private var savedAuthBytes: Data?
    /// store -> its pre-provisioned commit-journal directory (intent-file assertions).
    private var journalDirs: [ObjectIdentifier: URL] = [:]
    private var stores: [AppStore] = []
    private let session = AuthSession(accessToken: "tok", refreshToken: "ref",
                                      expiresAt: 4_000_000_000, userID: "u1", email: "u@example.test")
    private enum StubError: Error { case boundaryRefused, simulatedCrash }

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "UserDataSyncOrchestrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        savedSyncMeta = UserDefaults.standard.data(forKey: "ate.sync.v1")
        UserDefaults.standard.removeObject(forKey: "ate.sync.v1")
        savedAuthBytes = Keychain.load(account: "session")
        Keychain.save(nil, account: "session")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        for store in stores { store.session = nil }
        stores = []
        if let savedSyncMeta { UserDefaults.standard.set(savedSyncMeta, forKey: "ate.sync.v1") }
        else { UserDefaults.standard.removeObject(forKey: "ate.sync.v1") }
        Keychain.save(savedAuthBytes, account: "session")
        InsightLifecycleStore.clearAll()
        savedSyncMeta = nil; savedAuthBytes = nil
        super.tearDown()
    }

    /// A fresh pre-provisioned journal directory per store (production composition
    /// provisions one immutable directory; there is no fallback).
    private func makeJournalDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Binds the durable redo journal exactly as the production composition would:
    /// authorize re-proves the CURRENT session + the transport's live scope against the
    /// recorded receipt; the writer boundary is the store's admitted write.
    private func bindJournal(to store: AppStore, directory: URL,
                             goalsRepo: NutritionGoalsRepository,
                             checkpoint: @escaping (FamilySyncCommitJournal.Boundary) throws -> Void = { _ in },
                             goalsDurabilityCheckpoint: @escaping (FamilySyncGoalsDurability.Step) throws -> Void = { _ in }) throws {
        store.familySyncCommitJournal = try FamilySyncCommitJournal(
            directory: directory, container: store.journalStore.container!, goals: goalsRepo,
            defaults: .standard,
            authorize: { [weak store] receipt in
                guard let store, store.session?.userID == receipt.ownerID,
                      store.userDataSyncTransport?.currentScope
                        == AccountDataScope(ownerID: receipt.ownerID, generation: receipt.generation)
                else { throw FamilySyncCommitJournal.Failure.ownerChanged }
            },
            withWriterEffect: { [weak store] work in
                guard let store else { throw FamilySyncCommitJournal.Failure.durabilityUnverified }
                try store.performOrdinaryWriteThrowing(work)
            },
            goalsDurabilityCheckpoint: goalsDurabilityCheckpoint,
            checkpoint: checkpoint)
    }

    private func makeStore(transport: FakeFamilyTransport,
                           goalsStorage: (any NutritionGoalsStorage)? = nil,
                           checkpoint: @escaping (FamilySyncCommitJournal.Boundary) throws -> Void = { _ in }) throws -> AppStore {
        let goalsRepo = NutritionGoalsRepository(defaults: defaults,
            storage: goalsStorage ?? FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)))
        let runtime = FoodJournalRuntime(journal: JournalStore(inMemory: true),
                                         goalsRepository: goalsRepo, defaults: defaults)
        let store = AppStore(context: nil, backend: MockBackend(),
                             nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults),
                             nutritionGoalsRepository: goalsRepo,
                             foodJournalRuntime: runtime)
        store.session = session
        store.userDataSyncTransport = transport
        let journalDir = try makeJournalDirectory()
        try bindJournal(to: store, directory: journalDir, goalsRepo: goalsRepo,
                        checkpoint: checkpoint)
        journalDirs[ObjectIdentifier(store)] = journalDir
        stores.append(store)
        return store
    }

    private func pendingIntentURL(_ store: AppStore) -> URL {
        journalDirs[ObjectIdentifier(store)]!.appendingPathComponent("pending-v1.json")
    }

    private func hasPendingIntent(_ store: AppStore) -> Bool {
        FileManager.default.fileExists(atPath: pendingIntentURL(store).path)
    }

    private func seedJournal(_ store: AppStore, id: String, text: String, stampMs: Int64) throws {
        let context = ModelContext(store.journalStore.container!)
        context.insert(JournalEntry(id: id,
                                    createdAt: Date(timeIntervalSince1970: Double(stampMs) / 1000),
                                    prompt: "", text: text, state: nil, recipeIDs: []))
        try context.save()
    }

    private func journalIDs(_ store: AppStore) throws -> [String] {
        try JournalSyncBridge.export(container: store.journalStore.container).map(\.id).sorted()
    }

    private func remoteReflection(id: String, text: String, stampMs: Int64) throws -> SyncRecord {
        let payload = JournalEntrySyncPayload(id: id, createdAtMs: stampMs, prompt: "", text: text,
                                              stateRaw: "", recipeIDs: [], journalingSuggestionTitle: nil,
                                              momentDateMs: nil, sourceRaw: "ate", locationName: nil,
                                              latitude: nil, longitude: nil, mediaFileNames: [],
                                              editedAtMs: nil, kindRaw: "reflection", dayKey: nil,
                                              recipeSnapshotsRaw: nil, meal: nil)
        return SyncRecord(user_id: "u1", kind: "journal", id: id,
                          data: AnyJSON(try JSONEncoder().encode(payload)),
                          stampMs: Double(stampMs), deleted: false)
    }

    private func transportWith(rows: [SyncRecord]) -> FakeFamilyTransport {
        FakeFamilyTransport(snapshot: AccountSnapshot(generation: 1, rows: rows))
    }

    /// Change 2: proposals are staged, the authorized upload runs FIRST, and local
    /// publication happens only after it (asserted inside the upload itself).
    func testUploadHappensBeforeLocalPublication() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)

        transport.onPush = { records in
            // Inside the authorized upload the remote winner must NOT be published locally yet.
            XCTAssertEqual(records.map(\.id), ["j-local"])
            XCTAssertEqual(try? JournalSyncBridge.export(container: store.journalStore.container).map(\.id),
                           ["j-local"])
        }
        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local", "j-remote"])
        XCTAssertEqual(store.meta.journalStamps?["j-remote"], 2_000_000)
        XCTAssertEqual(store.meta.journalStamps?["j-local"], 1_000_000)
        XCTAssertEqual(store.userDataSyncStatus, .synced)
        XCTAssertFalse(store.userDataSyncBackendUnavailable)
        // Per-record: both records' current versions are now held by the server.
        XCTAssertEqual(store.journalRecordSyncState(id: "j-local",
                                                    createdAt: Date(timeIntervalSince1970: 1000)), .confirmed)
        XCTAssertEqual(store.journalRecordSyncState(id: "j-remote",
                                                    createdAt: Date(timeIntervalSince1970: 2000)), .confirmed)
    }

    /// Change 2: a failed upload publishes NOTHING locally - the staged remote winner is
    /// discarded and no stamps move.
    func testPushFailurePublishesNothingLocally() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)
        transport.onPush = { _ in throw ResetRPCError.http(500, "boom") }

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local"])
        XCTAssertNil(store.meta.journalStamps)
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
        XCTAssertFalse(store.userDataSyncBackendUnavailable)
    }

    /// Change 2: an unmigrated backend (23514) fails the upload as familyUnavailable;
    /// records report localOnly - never "queued" for an upload the server refuses.
    func testUnmigratedBackendKeepsRecordsLocalOnly() async throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)
        transport.onPush = { _ in
            throw ResetRPCError.http(400, "23514: new row violates check constraint")
        }

        await store.syncUserDataFamilies()

        XCTAssertTrue(store.userDataSyncBackendUnavailable)
        XCTAssertEqual(store.journalRecordSyncState(id: "j-local",
                                                    createdAt: Date(timeIntervalSince1970: 1000)), .localOnly)
        XCTAssertEqual(store.journalRecordSyncState(id: nil), .localOnly)
        XCTAssertEqual(try journalIDs(store), ["j-local"])
    }

    /// Change 2: a reset/account change surfacing at the pre-commit revalidation abandons
    /// publication even though the upload already ran.
    func testResetMidCyclePublishesNothingLocally() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)
        transport.onRevalidate = { throw ResetRPCError.staleGeneration }

        await store.syncUserDataFamilies()

        XCTAssertEqual(transport.pushAttempts, 1, "the authorized upload already ran")
        XCTAssertEqual(try journalIDs(store), ["j-local"], "no local publication after a mid-cycle reset")
        XCTAssertNil(store.meta.journalStamps)
        if case .unavailable(let detail) = store.userDataSyncStatus {
            XCTAssertTrue(detail.contains("changed on the server"), detail)
        } else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 1: local apply + metadata ride ONE admitted commit; a refused writer leaves
    /// content AND stamps unchanged. The recovery pass at the round's start also runs
    /// inside the admitted writer, so the refusal is armed only for the commit itself.
    func testWriterRefusalLeavesContentAndMetadataUnchanged() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)
        var recoveryPassed = false
        store.journalWriterEffect = { work in
            if recoveryPassed { throw StubError.boundaryRefused }
            recoveryPassed = true
            try work()
        }

        await store.syncUserDataFamilies()

        XCTAssertEqual(transport.pushAttempts, 1)
        XCTAssertEqual(try journalIDs(store), ["j-local"], "a refused writer must leave content unchanged")
        XCTAssertNil(store.meta.journalStamps, "a refused writer must leave stamps unchanged")
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 3: a malformed snapshot rejects the whole round before ANY upload or write.
    func testMalformedSnapshotRejectsRoundBeforeAnyWrite() async throws {
        let bad = SyncRecord(user_id: "u1", kind: "journal", id: "j-bad",
                             data: AnyJSON(try JSONEncoder().encode(
                                JournalEntrySyncPayload(id: "other", createdAtMs: 2_000_000, prompt: "",
                                                        text: "", stateRaw: "", recipeIDs: [],
                                                        journalingSuggestionTitle: nil, momentDateMs: nil,
                                                        sourceRaw: "ate", locationName: nil, latitude: nil,
                                                        longitude: nil, mediaFileNames: [], editedAtMs: nil,
                                                        kindRaw: "reflection", dayKey: nil,
                                                        recipeSnapshotsRaw: nil, meal: nil))),
                             stampMs: 2_000_000, deleted: false)
        let transport = transportWith(rows: [bad])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)

        await store.syncUserDataFamilies()

        XCTAssertEqual(transport.pushAttempts, 0, "a rejected snapshot must never reach the upload")
        XCTAssertEqual(try journalIDs(store), ["j-local"])
        XCTAssertNil(store.meta.journalStamps)
        if case .unavailable(let detail) = store.userDataSyncStatus {
            XCTAssertTrue(detail.contains("cannot read"), detail)
        } else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    // MARK: - Per-record privacy state (Reviewer change 4)

    func testJournalRecordSyncStateTransitions() throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        let created = Date(timeIntervalSince1970: 1000)

        // Active, unconfirmed: a composed record and an existing record are both pending.
        XCTAssertEqual(store.journalRecordSyncState(id: nil), .pending)
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .pending)

        // Confirmed: the persisted merged stamp equals the record's current version stamp,
        // bound to the account scope the round committed under.
        store.meta.journalStamps = ["j1": 1_000_000]
        store.meta.journalScope = AccountDataScope(ownerID: "u1", generation: 1)
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .confirmed)
        // An edit moves the version stamp: the new version is pending until a round confirms it.
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created,
                                                    editedAt: created.addingTimeInterval(60)), .pending)

        // A backend that refuses these kinds keeps the historical cloud copy visible as
        // such; only never-synced records report "saved only on this iPhone".
        store.userDataSyncBackendUnavailable = true
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .cloudCopyOnly(currentVersion: true))
        // Change 4 (Reviewer): edited after the upload, THEN sync lost: the server holds an
        // EARLIER version - the copy must say so instead of "saved only on this iPhone".
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created,
                                                    editedAt: created.addingTimeInterval(60)),
                       .cloudCopyOnly(currentVersion: false))
    }

    /// Change 4: "ever uploaded" is separate from "current version confirmed": a record
    /// edited after its upload keeps its cloud-copy truth when the flag is switched OFF.
    func testEditedRecordReportsEarlierCloudCopyWhenFlagOff() throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        let created = Date(timeIntervalSince1970: 1000)
        store.meta.journalStamps = ["j1": 1_000_000]
        store.meta.journalScope = AccountDataScope(ownerID: "u1", generation: 1)

        store.userDataSyncEnabledOverride = false
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created,
                                                    editedAt: created.addingTimeInterval(60)),
                       .cloudCopyOnly(currentVersion: false),
                       "an edited record's earlier version is still in the account")
        XCTAssertEqual(store.journalRecordSyncState(id: "j2", createdAt: created),
                       .localOnly,
                       "a record that never uploaded still reports local-only")
    }

    /// Change 2 (Reviewer): an edit landing mid-upload must not be overwritten by staged
    /// remote winners, and the stale plan must not be stamped confirmed. The commit's
    /// second local read refuses; the edited content survives untouched.
    func testEditDuringUploadRefusesCommit() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)
        transport.onPush = { _ in
            // The user edits the entry while the upload is in flight.
            let context = ModelContext(store.journalStore.container!)
            let entry = try! context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == "j-local" })).first!
            entry.text = "edited during upload"
            entry.editedAt = Date(timeIntervalSince1970: 1500)
            try! context.save()
        }

        await store.syncUserDataFamilies()

        let payloads = try JournalSyncBridge.export(container: store.journalStore.container)
        XCTAssertEqual(payloads.map(\.id), ["j-local"], "the staged remote winner must not publish over the edit")
        XCTAssertEqual(payloads.first?.text, "edited during upload")
        XCTAssertNil(store.meta.journalStamps, "the stale plan must not be stamped confirmed")
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 2: a delete landing mid-upload also refuses the commit.
    func testDeleteDuringUploadRefusesCommit() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport)
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)
        transport.onPush = { _ in
            let context = ModelContext(store.journalStore.container!)
            let entry = try! context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == "j-local" })).first!
            context.delete(entry)
            try! context.save()
        }

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), [], "the delete stands; the staged remote winner must not publish")
        XCTAssertNil(store.meta.journalStamps)
    }

    /// Change 2: goals changed mid-upload refuse the commit; the new local value stands.
    func testGoalsChangeDuringUploadRefusesCommit() async throws {
        let remoteGoals = SyncRecord(user_id: "u1", kind: "goals", id: "current",
                                     data: AnyJSON(try JSONEncoder().encode(
                                        DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                                            carbohydratesGrams: nil, fatGrams: nil,
                                                            fibreGrams: nil))),
                                     stampMs: 2_000_000, deleted: false)
        let transport = transportWith(rows: [remoteGoals])
        let store = try makeStore(transport: transport)
        transport.onPush = { _ in
            try! store.journalGoalsRepository.save(
                DailyNutritionGoals(energyKcal: 1800, proteinGrams: nil, carbohydratesGrams: nil,
                                    fatGrams: nil, fibreGrams: nil))
        }

        await store.syncUserDataFamilies()

        XCTAssertEqual(try store.journalGoalsRepository.load().energyKcal, 1800,
                       "the mid-upload goals change stands; the remote winner must not overwrite it")
        XCTAssertNil(store.meta.goalsStamps)
    }

    /// Change 4 (Reviewer): confirmation scope is PER FAMILY. A generation advance with a
    /// failed family round confirms the successful families under the new epoch while the
    /// failed family keeps its OLD scope - its stale stamps are never promoted.
    func testFailedFamilyKeepsOldScopeAcrossGenerationChange() async throws {
        let transport = FakeFamilyTransport(snapshot: AccountSnapshot(generation: 2, rows: []))
        transport.scope = AccountDataScope(ownerID: "u1", generation: 2)
        let store = try makeStore(transport: transport, goalsStorage: ReadFailingGoalsStorage())
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)
        // Prior-epoch state carried in metadata (e.g. persisted before this journal was bound):
        // both families confirmed under generation 1.
        let oldScope = AccountDataScope(ownerID: "u1", generation: 1)
        store.meta.journalStamps = ["j-local": 1_000_000]
        store.meta.goalsStamps = ["current": 1_000_000]
        store.meta.journalScope = oldScope
        store.meta.goalsScope = oldScope

        await store.syncUserDataFamilies()

        XCTAssertEqual(store.meta.journalScope, AccountDataScope(ownerID: "u1", generation: 2),
                       "the journal family confirmed under the new epoch")
        XCTAssertEqual(store.meta.insightScope, nil,
                       "insight states are dormant in this slice: no scope is confirmed")
        XCTAssertEqual(store.meta.goalsScope, oldScope,
                       "the failed goals family keeps its old scope: no promotion into the new epoch")
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable (goals failed), got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 4: with the commit-journal seam unbound the round refuses to run, so a record
    /// must report localOnly - never "queued" for an upload that cannot happen.
    func testUnboundCommitJournalReportsLocalOnly() throws {
        let store = try makeStore(transport: transportWith(rows: []))
        try seedJournal(store, id: "j-local", text: "on device", stampMs: 1_000_000)
        store.familySyncCommitJournal = nil
        XCTAssertEqual(store.journalRecordSyncState(id: "j-local",
                                                    createdAt: Date(timeIntervalSince1970: 1000)), .localOnly)
    }

    func testPushOnlyGoalsRoundCannotConfirmBeforeDurability() async throws {
        let store = try makeStore(transport: transportWith(rows: []))
        try store.journalGoalsRepository.save(DailyNutritionGoals(energyKcal: 2100,
            proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        try bindJournal(to: store, directory: journalDirs[ObjectIdentifier(store)]!,
                        goalsRepo: store.journalGoalsRepository,
                        goalsDurabilityCheckpoint: { _ in throw StubError.simulatedCrash })
        await store.syncUserDataFamilies()
        XCTAssertNil(store.meta.goalsScope)
        XCTAssertTrue(hasPendingIntent(store), "a push-only round still seals its complete goals target")
        try bindJournal(to: store, directory: journalDirs[ObjectIdentifier(store)]!,
                        goalsRepo: store.journalGoalsRepository)
        await store.syncUserDataFamilies()
        XCTAssertEqual(store.meta.goalsScope, AccountDataScope(ownerID: "u1", generation: 1))
        XCTAssertEqual(try store.journalGoalsRepository.load().energyKcal, 2100)
        XCTAssertFalse(hasPendingIntent(store))
    }

    /// Change 3 (Reviewer): the commit is a DURABLE REDO, not a rollback. A mid-commit
    /// failure (goals save throws after the journal apply) leaves the recorded intent on
    /// disk and the metadata unwritten; the NEXT round's replay completes the recorded
    /// target - drives goals forward, installs the metadata authority, retires the intent.
    func testMidCommitFailureIsCompletedByReplay() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let remoteGoals = SyncRecord(user_id: "u1", kind: "goals", id: "current",
                                     data: AnyJSON(try JSONEncoder().encode(
                                        DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                                            carbohydratesGrams: nil, fatGrams: nil,
                                                            fibreGrams: nil))),
                                     stampMs: 2_000_000, deleted: false)
        let transport = transportWith(rows: [remote, remoteGoals])
        let store = try makeStore(transport: transport, goalsStorage: WriteFailingGoalsStorage(failures: 1))
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local", "j-remote"],
                       "journal was already driven forward; redo never rolls it back")
        XCTAssertNil(store.meta.journalStamps, "no in-memory metadata adoption without a completed commit")
        XCTAssertTrue(hasPendingIntent(store), "the recorded intent survives for replay")
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }

        // Storage healed: the next round replays the recorded target to completion.
        await store.syncUserDataFamilies()

        XCTAssertEqual(try store.journalGoalsRepository.load().energyKcal, 2100,
                       "replay completed the interrupted goals apply")
        XCTAssertEqual(store.meta.journalStamps?["j-remote"], 2_000_000)
        XCTAssertEqual(store.meta.journalStamps?["j-local"], 1_000_000)
        XCTAssertFalse(hasPendingIntent(store), "a completed replay retires the intent")
        XCTAssertEqual(store.userDataSyncStatus, .synced)
    }

    /// Change 3: a crash before the intent is recorded leaves NOTHING behind: no intent
    /// file, no store mutation, no metadata.
    func testCrashBeforeIntentWriteAbortsBeforeAnyApply() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport, checkpoint: { boundary in
            if boundary == .beforeIntentWrite { throw StubError.simulatedCrash }
        })
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local"], "no apply may run before a durable intent")
        XCTAssertNil(store.meta.journalStamps)
        XCTAssertFalse(hasPendingIntent(store))
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 3: an interrupted commit (intent on disk, journal already driven, metadata
    /// not) is completed by replay at the next round with a FRESH journal instance over
    /// the same directory - the real disk-reopen path.
    func testInterruptedCommitIsCompletedByReplayAfterReopen() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let remoteGoals = SyncRecord(user_id: "u1", kind: "goals", id: "current",
                                     data: AnyJSON(try JSONEncoder().encode(
                                        DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                                            carbohydratesGrams: nil, fatGrams: nil,
                                                            fibreGrams: nil))),
                                     stampMs: 2_000_000, deleted: false)
        let transport = transportWith(rows: [remote, remoteGoals])
        let store = try makeStore(transport: transport, checkpoint: { boundary in
            if boundary == .afterJournalApply { throw StubError.simulatedCrash }
        })
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)

        await store.syncUserDataFamilies()
        XCTAssertEqual(try journalIDs(store), ["j-local", "j-remote"])
        XCTAssertNil(store.meta.journalStamps)
        XCTAssertTrue(hasPendingIntent(store))

        // Relaunch: a fresh journal instance reopens the same directory, bound to the
        // store's real goals repository.
        let directory = journalDirs[ObjectIdentifier(store)]!
        try bindJournal(to: store, directory: directory, goalsRepo: store.journalGoalsRepository)

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local", "j-remote"], "replay is idempotent")
        XCTAssertEqual(try store.journalGoalsRepository.load().energyKcal, 2100,
                       "replay completed the recorded goals target")
        XCTAssertEqual(store.meta.journalStamps?["j-remote"], 2_000_000)
        XCTAssertFalse(hasPendingIntent(store), "a completed replay retires the intent")
        XCTAssertEqual(store.userDataSyncStatus, .synced)
    }

    /// Change 2/3 (Reviewer): a pending intent replays ONLY from its recorded before-image.
    /// An ordinary edit that landed after the crash makes replay REFUSE - the edit and the
    /// intent are both preserved, nothing is overwritten by a stale recording.
    func testEditAfterCrashMakesReplayRefuseAndPreserve() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport, checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubError.simulatedCrash }
        })
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)

        await store.syncUserDataFamilies()
        XCTAssertTrue(hasPendingIntent(store))

        // The user edits before the next round runs.
        let context = ModelContext(store.journalStore.container!)
        let entry = try! context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == "j-local" })).first!
        entry.text = "edited after the crash"
        try! context.save()

        await store.syncUserDataFamilies()

        let payloads = try JournalSyncBridge.export(container: store.journalStore.container)
        XCTAssertEqual(payloads.map(\.id), ["j-local"], "the remote winner must NOT publish over the edit")
        XCTAssertEqual(payloads.first?.text, "edited after the crash", "the edit is preserved")
        XCTAssertTrue(hasPendingIntent(store), "the refused intent is preserved, not discarded")
        XCTAssertNil(store.meta.journalStamps)
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 2 (Reviewer): a pending intent from account A must NEVER replay under
    /// account B - replay refuses fail-closed and mutates nothing.
    func testPendingIntentFromAccountANeverReplaysUnderB() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport, checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubError.simulatedCrash }
        })
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)
        await store.syncUserDataFamilies()
        XCTAssertTrue(hasPendingIntent(store))

        store.session = AuthSession(accessToken: "tok2", refreshToken: "ref2",
                                    expiresAt: 4_000_000_000, userID: "u2", email: "v@example.test")
        transport.scope = AccountDataScope(ownerID: "u2", generation: 7)

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local"], "A's recorded result must not publish under B")
        XCTAssertTrue(hasPendingIntent(store), "the foreign intent is preserved for the reset composition")
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 2: a pending intent from an old generation (reset elsewhere) refuses replay
    /// under the new epoch; the reset composition owns erasure of the journal directory.
    func testPendingIntentFromOldGenerationRefusesReplay() async throws {
        let remote = try remoteReflection(id: "j-remote", text: "from cloud", stampMs: 2_000_000)
        let transport = transportWith(rows: [remote])
        let store = try makeStore(transport: transport, checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubError.simulatedCrash }
        })
        try seedJournal(store, id: "j-local", text: "original", stampMs: 1_000_000)
        await store.syncUserDataFamilies()
        XCTAssertTrue(hasPendingIntent(store))

        transport.scope = AccountDataScope(ownerID: "u1", generation: 2)

        await store.syncUserDataFamilies()

        XCTAssertEqual(try journalIDs(store), ["j-local"])
        XCTAssertTrue(hasPendingIntent(store))
        if case .unavailable = store.userDataSyncStatus {} else {
            XCTFail("expected unavailable, got \(String(describing: store.userDataSyncStatus))")
        }
    }

    /// Change 4 (Reviewer): a confirmed record keeps its cloud-copy truth when sync can no
    /// longer run - flag off, signed out, unbound graph, backend refusing - instead of
    /// degrading to "Saved only on this iPhone".
    func testConfirmedRecordReportsCloudCopyWhenSyncCannotRun() throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        let created = Date(timeIntervalSince1970: 1000)
        store.meta.journalStamps = ["j1": 1_000_000]
        store.meta.journalScope = AccountDataScope(ownerID: "u1", generation: 1)
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .confirmed)

        store.userDataSyncEnabledOverride = false
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .cloudCopyOnly(currentVersion: true),
                       "flag off: the server still holds the confirmed version")
        store.userDataSyncEnabledOverride = nil

        store.userDataSyncBackendUnavailable = true
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .cloudCopyOnly(currentVersion: true),
                       "23514: the server still holds the confirmed version")
        store.userDataSyncBackendUnavailable = false

        store.userDataSyncTransport = nil
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .cloudCopyOnly(currentVersion: true),
                       "unbound graph: the server still holds the confirmed version")
        store.userDataSyncTransport = transport

        store.session = nil
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .cloudCopyOnly(currentVersion: true),
                       "signed out: the account's server copy still exists")
    }

    /// Change 4: confirmation is bound to owner + generation. After switching accounts
    /// (before any sync reset runs), account A's stamps must not confirm records under B.
    func testAccountSwitchBeforeSyncDoesNotConfirm() throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        let created = Date(timeIntervalSince1970: 1000)
        store.meta.journalStamps = ["j1": 1_000_000]
        store.meta.journalScope = AccountDataScope(ownerID: "u1", generation: 1)
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .confirmed)

        store.session = AuthSession(accessToken: "tok2", refreshToken: "ref2",
                                    expiresAt: 4_000_000_000, userID: "u2", email: "v@example.test")
        transport.scope = AccountDataScope(ownerID: "u2", generation: 7)
        XCTAssertNotEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .confirmed,
                          "account B must not inherit account A's confirmation")
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .pending,
                       "under B the record is queued for B's account, not confirmed to A's")
    }

    /// Change 4: a generation advance (reset elsewhere) breaks confirmation even for the
    /// same account; the next successful round re-establishes scope.
    func testGenerationAdvanceBreaksConfirmation() throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        let created = Date(timeIntervalSince1970: 1000)
        store.meta.journalStamps = ["j1": 1_000_000]
        store.meta.journalScope = AccountDataScope(ownerID: "u1", generation: 1)
        transport.scope = AccountDataScope(ownerID: "u1", generation: 2)
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: created), .pending,
                       "the receipt advanced past the confirmed generation: re-sync before claiming")
    }

    func testSessionChangeResetsFamilySyncState() throws {
        let transport = transportWith(rows: [])
        let store = try makeStore(transport: transport)
        store.meta.journalStamps = ["j1": 1_000_000]
        store.meta.journalScope = AccountDataScope(ownerID: "u1", generation: 1)
        store.userDataSyncStatus = .synced
        store.userDataSyncBackendUnavailable = true

        store.session = nil
        XCTAssertNil(store.userDataSyncStatus)
        XCTAssertFalse(store.userDataSyncBackendUnavailable)
        // The aggregate status reset does not erase the historical cloud-copy fact.
        XCTAssertEqual(store.journalRecordSyncState(id: "j1", createdAt: Date(timeIntervalSince1970: 1000)),
                       .cloudCopyOnly(currentVersion: true))

        // A different account also starts clean, never with the previous account's status.
        store.session = AuthSession(accessToken: "tok2", refreshToken: "ref2",
                                    expiresAt: 4_000_000_000, userID: "u2", email: "v@example.test")
        XCTAssertNil(store.userDataSyncStatus)
        XCTAssertFalse(store.userDataSyncBackendUnavailable)
    }
}

// MARK: - FamilySyncCommitJournal (durable redo journal, #532 discipline)

/// Round-independent crash/durability coverage for the family commit journal: every
/// recovery path runs against a FRESH journal instance over the same on-disk directory
/// (file reopen). Most tests use in-memory SwiftData; the matrix closes and reopens
/// an on-disk container. Neither test setup simulates OS power loss or device durability.
@MainActor
final class FamilySyncCommitJournalTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!
    private var container: ModelContainer!
    private var goalsFile: URL!
    /// The identity/epoch the composition would prove; tests flip it to simulate
    /// account switch and generation advance.
    private var liveScope = AccountDataScope(ownerID: "u1", generation: 1)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaultsSuite = "FamilySyncCommitJournalTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        container = JournalStore(inMemory: true).container
        goalsFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        liveScope = AccountDataScope(ownerID: "u1", generation: 1)
        InsightLifecycleStore.clearAll()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        InsightLifecycleStore.clearAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: goalsFile)
        super.tearDown()
    }

    private func makeJournal(checkpoint: @escaping (FamilySyncCommitJournal.Boundary) throws -> Void = { _ in },
                             goalsStorage: (any NutritionGoalsStorage)? = nil,
                             allowsInsightContent: Bool = false,
                             goalsDurabilityCheckpoint: @escaping (FamilySyncGoalsDurability.Step) throws -> Void = { _ in }) throws -> FamilySyncCommitJournal {
        let scope = { self.liveScope }
        return try FamilySyncCommitJournal(
            directory: directory, container: container,
            goals: NutritionGoalsRepository(defaults: defaults,
                storage: goalsStorage ?? FileNutritionGoalsStorage(fileURL: goalsFile)),
            defaults: defaults,
            authorize: { receipt in
                guard scope() == AccountDataScope(ownerID: receipt.ownerID,
                                                  generation: receipt.generation) else {
                    throw FamilySyncCommitJournal.Failure.ownerChanged
                }
            },
            withWriterEffect: { work in try work() },
            allowsInsightContent: allowsInsightContent,
            goalsDurabilityCheckpoint: goalsDurabilityCheckpoint,
            checkpoint: checkpoint)
    }

    private func payload(_ id: String, _ text: String, _ stampMs: Int64) -> JournalEntrySyncPayload {
        JournalEntrySyncPayload(id: id, createdAtMs: stampMs, prompt: "", text: text, stateRaw: "",
                                recipeIDs: [], journalingSuggestionTitle: nil, momentDateMs: nil,
                                sourceRaw: "ate", locationName: nil, latitude: nil, longitude: nil,
                                mediaFileNames: [], editedAtMs: nil, kindRaw: "reflection",
                                dayKey: nil, recipeSnapshotsRaw: nil, meal: nil)
    }

    private func seed(_ entries: [JournalEntrySyncPayload]) throws {
        try JournalSyncBridge.apply(upserts: entries, deletes: [], container: container)
    }

    private func exportIDs() throws -> [String] {
        try JournalSyncBridge.export(container: container).map(\.id).sorted()
    }

    private func metadata(ownerID: String = "u1", generation: Int64 = 1) -> FamilySyncMetadata {
        let scope = AccountDataScope(ownerID: ownerID, generation: generation)
        return FamilySyncMetadata(journalStamps: ["j-a": 1_000_000], journalTombs: nil,
                                  insightStamps: nil, insightTombs: nil,
                                  goalsStamps: ["current": 1_000_000], goalsTombs: nil,
                                  goalsSyncedPayload: nil,
                                  journalScope: scope, insightScope: scope, goalsScope: scope,
                                  ownerID: ownerID)
    }

    private func insightRecord(_ status: InsightLifecycleStatus, _ fingerprint: String,
                               _ updatedAt: Double) -> InsightLifecycleRecord {
        InsightLifecycleRecord(status: status, evidenceFingerprint: fingerprint,
                               updatedAt: Date(timeIntervalSince1970: updatedAt), snoozedUntil: nil)
    }

    private func makeCommit(before: [JournalEntrySyncPayload], after: [JournalEntrySyncPayload],
                            insightBefore: [String: InsightLifecycleRecord]? = nil,
                            insightAfter: [String: InsightLifecycleRecord]? = nil,
                            goalsAfter: DailyNutritionGoals? = nil,
                            goalsBefore: DailyNutritionGoals? = nil) -> FamilySyncCommitJournal.Commit {
        FamilySyncCommitJournal.Commit(
            receipt: AccountGenerationPolicy.Receipt(ownerID: "u1", generation: 1),
            metadata: metadata(),
            before: FamilySyncCommitJournal.Images(
                journal: before, insight: insightAfter == nil ? nil : (insightBefore ?? [:]),
                goals: goalsAfter == nil ? nil : (goalsBefore ?? DailyNutritionGoals())),
            after: FamilySyncCommitJournal.Images(journal: after, insight: insightAfter, goals: goalsAfter),
            verify: {})
    }

    private var intentURL: URL { directory.appendingPathComponent("pending-v1.json") }
    private var authorityURL: URL { directory.appendingPathComponent("metadata-v1.json") }


    func testAbsentIntentIsANoOp() throws {
        let journal = try makeJournal()
        XCTAssertNil(try journal.recoverAndProject(), "raw absence recovers as nothing to do")
        XCTAssertEqual(try exportIDs(), [])
    }

    func testCommitDrivesStoresAndRetiresIntent() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        let journal = try makeJournal()
        let goalsAfter = DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                             carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000), payload("j-b", "new", 2_000_000)],
                                goalsAfter: goalsAfter,
                                goalsBefore: DailyNutritionGoals())

        let projected = try journal.commit(commit)

        XCTAssertEqual(projected, metadata())
        XCTAssertEqual(try exportIDs(), ["j-a", "j-b"])
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first { $0.id == "j-a" }?.text, "after")
        // Goals load() reports the empty/all-nil forms alike; compare through the repository.
        let goalsRepo = NutritionGoalsRepository(defaults: defaults,
                                                 storage: FileNutritionGoalsStorage(fileURL: goalsFile))
        XCTAssertEqual(try goalsRepo.load().energyKcal, 2100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path), "a completed commit retires the intent")
        XCTAssertTrue(FileManager.default.fileExists(atPath: authorityURL.path), "the metadata authority is durable")
        // The defaults projection carries the family fields and survives a reopen.
        let data = try XCTUnwrap(defaults.data(forKey: "ate.sync.v1"))
        let meta = try JSONDecoder().decode(SyncMeta.self, from: data)
        XCTAssertEqual(meta.journalStamps, ["j-a": 1_000_000])
        XCTAssertEqual(meta.journalScope, AccountDataScope(ownerID: "u1", generation: 1))
    }

    func testCrashAfterIntentWriteReplaysToCompletionAfterReopen() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        })
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit))
        XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path))
        XCTAssertEqual(try exportIDs(), ["j-a"], "crash landed before any store apply")

        journal = try makeJournal() // reopen: fresh instance, same directory
        let projected = try XCTUnwrap(try journal.recoverAndProject())
        XCTAssertEqual(projected, metadata())
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "after")
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
    }

    func testCrashBeforeIntentRetireReplaysIdempotently() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .beforeIntentRetire { throw StubCrash.crash }
        })
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit))
        // Content + authority + defaults all landed; only the retire did not.
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "after")
        XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: authorityURL.path))

        journal = try makeJournal()
        XCTAssertNotNil(try journal.recoverAndProject(), "replay reconverges and retires")
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "after")
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
        // A second reopen now finds only the authority and re-projects from it.
        journal = try makeJournal()
        XCTAssertEqual(try journal.recoverAndProject(), metadata())
    }

    func testMidApplyStoreFailureKeepsIntentForReplay() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        let goalsAfter = DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                             carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        var journal = try makeJournal(goalsStorage: WriteFailingGoalsStorage(failures: 1))
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)],
                                goalsAfter: goalsAfter, goalsBefore: DailyNutritionGoals())
        XCTAssertThrowsError(try journal.commit(commit))
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "after",
                       "journal was driven before the goals failure; redo never rolls back")
        XCTAssertFalse(FileManager.default.fileExists(atPath: authorityURL.path),
                       "metadata authority is not installed when an apply fails")

        journal = try makeJournal() // healed storage
        XCTAssertEqual(try journal.recoverAndProject(), metadata())
        let goalsRepo = NutritionGoalsRepository(defaults: defaults,
                                                 storage: FileNutritionGoalsStorage(fileURL: goalsFile))
        XCTAssertEqual(try goalsRepo.load().energyKcal, 2100, "replay completed the goals apply")
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
    }

    func testUnreadableIntentBlocksAndPreserves() throws {
        try Data("not json at all".utf8).write(to: intentURL)
        let journal = try makeJournal()
        XCTAssertThrowsError(try journal.recoverAndProject()) { error in
            guard case FamilySyncCommitJournal.Failure.unverifiedRecord = error else {
                return XCTFail("expected unverifiedRecord, got \(error)")
            }
        }
        // The evidence is preserved, never silently treated as absent.
        XCTAssertEqual(try Data(contentsOf: intentURL), Data("not json at all".utf8))
    }

    func testCorruptChecksumBlocksReplay() throws {
        // Well-formed envelope JSON whose sha256 does not match its payload.
        let forged = """
        {"payload":"eyJ2ZXJzaW9uIjoxfQ==","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}
        """
        try Data(forged.utf8).write(to: intentURL)
        let journal = try makeJournal()
        XCTAssertThrowsError(try journal.recoverAndProject()) { error in
            guard case FamilySyncCommitJournal.Failure.unverifiedRecord = error else {
                return XCTFail("expected unverifiedRecord, got \(error)")
            }
        }
    }

    func testAmbiguousTempAndPendingBlocks() throws {
        // Simulate a crash mid-rename with both names present: truth is ambiguous.
        try Data("x".utf8).write(to: intentURL)
        try Data("y".utf8).write(to: intentURL.appendingPathExtension("tmp"))
        let journal = try makeJournal()
        XCTAssertThrowsError(try journal.recoverAndProject())
        XCTAssertEqual(try? Data(contentsOf: intentURL), Data("x".utf8), "evidence preserved")
    }

    func testSecondCommitRefusesWhileIntentPending() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        })
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit))

        journal = try makeJournal()
        XCTAssertThrowsError(try journal.commit(commit)) { error in
            guard case FamilySyncCommitJournal.Failure.pendingCommit = error else {
                return XCTFail("expected pendingCommit, got \(error)")
            }
        }
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "before",
                       "a refused commit mutates nothing")
    }

    func testVerifyRefusalRecordsNothing() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        let journal = try makeJournal()
        var commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        commit = FamilySyncCommitJournal.Commit(receipt: commit.receipt, metadata: commit.metadata,
                                                before: commit.before, after: commit.after,
                                                verify: { throw StubCrash.crash })
        XCTAssertThrowsError(try journal.commit(commit))
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path),
                       "a refused second read leaves no intent")
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "before")
    }

    func testReplayRefusesContentChangedSinceAdmission() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        })
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit))

        // An ordinary edit lands after the crash.
        try seed([payload("j-a", "edited after crash", 1_000_000)])

        journal = try makeJournal()
        XCTAssertThrowsError(try journal.recoverAndProject()) { error in
            guard case FamilySyncCommitJournal.Failure.unverifiedRecord = error else {
                return XCTFail("expected unverifiedRecord, got \(error)")
            }
        }
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "edited after crash",
                       "changed content is preserved, never overwritten by the stale recording")
        XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path), "the intent is preserved")
    }

    func testReplayRefusesForeignOwner() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        })
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit))

        liveScope = AccountDataScope(ownerID: "u2", generation: 7) // account switch
        journal = try makeJournal()
        XCTAssertThrowsError(try journal.recoverAndProject()) { error in
            guard case FamilySyncCommitJournal.Failure.ownerChanged = error else {
                return XCTFail("expected ownerChanged, got \(error)")
            }
        }
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "before",
                       "A's recorded result never publishes under B")
    }

    func testReplayRefusesStaleGeneration() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        })
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit))

        liveScope = AccountDataScope(ownerID: "u1", generation: 2) // reset elsewhere
        journal = try makeJournal()
        XCTAssertThrowsError(try journal.recoverAndProject())
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "before")
    }

    func testBareAuthorityReprojectsDefaultsAfterReopen() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var journal = try makeJournal()
        _ = try journal.commit(makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                          after: [payload("j-a", "after", 1_000_000)]))
        defaults.removeObject(forKey: "ate.sync.v1") // projection lost (e.g. defaults wipe)

        journal = try makeJournal()
        XCTAssertEqual(try journal.recoverAndProject(), metadata(),
                       "the durable authority re-projects the family metadata")
        let data = try XCTUnwrap(defaults.data(forKey: "ate.sync.v1"))
        XCTAssertEqual(try JSONDecoder().decode(SyncMeta.self, from: data).journalStamps, ["j-a": 1_000_000])
    }

    // MARK: - Reviewer changes 4

    /// Gap 1: existing `ate.sync.v1` bytes that are corrupt (or not Data at all) refuse the
    /// projection WITHOUT writing - the exact raw bytes survive, the intent is retained,
    /// and recipe/shopping metadata is never overwritten by an empty-base projection.
    func testCorruptExistingSyncMetaRefusesProjectionAndPreservesBytes() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        let corrupt = Data("not a SyncMeta".utf8)
        defaults.set(corrupt, forKey: "ate.sync.v1")
        let journal = try makeJournal()
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)])
        XCTAssertThrowsError(try journal.commit(commit)) { error in
            guard case FamilySyncCommitJournal.Failure.unverifiedRecord = error else {
                return XCTFail("expected unverifiedRecord, got \(error)")
            }
        }
        XCTAssertEqual(defaults.data(forKey: "ate.sync.v1"), corrupt,
                       "the unreadable bytes are preserved exactly")
        XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path),
                      "the intent survives for replay after the metadata is repaired")
        // A non-Data object under the key refuses the same way.
        defaults.set("a string", forKey: "ate.sync.v1")
        XCTAssertThrowsError(try makeJournal().recoverAndProject())
        XCTAssertEqual(defaults.object(forKey: "ate.sync.v1") as? String, "a string")
    }

    /// Gap 1: a decodable existing SyncMeta keeps its unrelated fields through the projection.
    func testProjectionPreservesUnrelatedSyncMetaFields() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        var existing = SyncMeta()
        existing.recipeStamps = ["r1": 5]
        existing.userID = "u1"
        defaults.set(try JSONEncoder().encode(existing), forKey: "ate.sync.v1")
        let journal = try makeJournal()
        _ = try journal.commit(makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                          after: [payload("j-a", "after", 1_000_000)]))
        let data = try XCTUnwrap(defaults.data(forKey: "ate.sync.v1"))
        let meta = try JSONDecoder().decode(SyncMeta.self, from: data)
        XCTAssertEqual(meta.recipeStamps, ["r1": 5], "recipe stamps survive the family projection")
        XCTAssertEqual(meta.userID, "u1")
        XCTAssertEqual(meta.journalStamps, ["j-a": 1_000_000])
    }

    /// Gap 3 (Reviewer): replay preflights EVERY family (and the metadata ownership) before
    /// any write. A foreign insight change refuses the replay with the journal family still
    /// untouched at its before-image.
    func testReplayPreflightRefusesBeforeAnyMutation() throws {
        try seed([payload("j-a", "before", 1_000_000)])
        let insightBefore = ["i1": insightRecord(.seen, "a", 1000)]
        let insightAfter = ["i1": insightRecord(.dismissed, "a", 2000)]
        InsightLifecycleStore(accountID: "u1").applySyncedRecords(insightBefore)
        var journal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        }, allowsInsightContent: true)
        let commit = makeCommit(before: [payload("j-a", "before", 1_000_000)],
                                after: [payload("j-a", "after", 1_000_000)],
                                insightBefore: insightBefore, insightAfter: insightAfter)
        XCTAssertThrowsError(try journal.commit(commit))
        // A foreign insight change lands after the crash.
        InsightLifecycleStore(accountID: "u1").applySyncedRecords(["i9": insightRecord(.seen, "z", 3000)])
        journal = try makeJournal(allowsInsightContent: true)
        XCTAssertThrowsError(try journal.recoverAndProject()) { error in
            guard case FamilySyncCommitJournal.Failure.unverifiedRecord = error else {
                return XCTFail("expected unverifiedRecord, got \(error)")
            }
        }
        XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "before",
                       "preflight refused before ANY family write - the journal is untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path))
    }

    /// Injected interruption/reopen matrix over the journal/goals checkpoints, ON DISK.
    /// The two debug-only insight checkpoints are excluded because insight is refused.
    /// This does NOT simulate OS power loss or validate hardware durability.
    /// a completed first commit lands, a SECOND commit crashes at the boundary, and a real
    /// reopen (the SwiftData container is dropped and re-created over the same store file,
    /// plus a fresh journal and goals repo) must either show nothing new recorded (crash
    /// before the second intent write: state == commit 1's target) or replay the second
    /// commit to exact convergence with the intent retired. This also covers intent/authority
    /// temp crashes with a prior completed commit's authority on disk.
    func testJournalAndGoalsInterruptionBoundariesReopen() throws {
        let goals1 = DailyNutritionGoals(energyKcal: 1500, proteinGrams: nil, carbohydratesGrams: nil,
                                         fatGrams: nil, fibreGrams: nil)
        let goals2 = DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil, carbohydratesGrams: nil,
                                         fatGrams: nil, fibreGrams: nil)
        for boundary in FamilySyncCommitJournal.Boundary.allCases
            where boundary != .beforeInsightApply && boundary != .afterInsightApply {
            // Fresh durable state per boundary, journal directory and store file together.
            container = nil
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            InsightLifecycleStore.clearAll()
            try? FileManager.default.removeItem(at: goalsFile)
            defaults.removeObject(forKey: "ate.sync.v1")
            let configuration = ModelConfiguration("matrix-\(UUID().uuidString)",
                url: directory.appendingPathComponent("journal.sqlite"))
            container = try ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                                           configurations: configuration)

            // Commit 1 completes.
            try seed([payload("j-a", "v1", 1_000_000)])
            var journal: FamilySyncCommitJournal? = try makeJournal()
            _ = try journal!.commit(makeCommit(before: [payload("j-a", "v1", 1_000_000)],
                                              after: [payload("j-a", "v1c", 1_000_000)],
                                              goalsAfter: goals1, goalsBefore: DailyNutritionGoals()))

            // Commit 2 crashes at the boundary under test.
            journal = try makeJournal(checkpoint: { b in
                if b == boundary { throw StubCrash.crash }
            })
            let commit2 = makeCommit(before: [payload("j-a", "v1c", 1_000_000)],
                                     after: [payload("j-a", "v2c", 1_000_000), payload("j-b", "new", 2_000_000)],
                                     goalsAfter: goals2, goalsBefore: goals1)
            XCTAssertThrowsError(try journal!.commit(commit2), "boundary \(boundary)")

            // Release BOTH owners of the old container before opening the same store.
            weak var oldContainer = container
            journal = nil
            container = nil
            XCTAssertNil(oldContainer, "the prior journal must not retain the old container")
            container = try ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                                           configurations: configuration)
            journal = try makeJournal()
            let goalsRepo = NutritionGoalsRepository(defaults: defaults,
                                                     storage: FileNutritionGoalsStorage(fileURL: goalsFile))
            if boundary == .beforeIntentWrite {
                XCTAssertNotNil(try journal!.recoverAndProject(), "\(boundary): commit 1's authority re-projects")
                XCTAssertEqual(try JournalSyncBridge.export(container: container).first?.text, "v1c",
                               "\(boundary): commit 2 recorded nothing; commit 1's target stands")
                XCTAssertEqual(try goalsRepo.load().energyKcal, 1500, "\(boundary)")
            } else {
                XCTAssertNotNil(try journal!.recoverAndProject(), "\(boundary): replay converges")
                XCTAssertEqual(try exportIDs(), ["j-a", "j-b"], "\(boundary)")
                XCTAssertEqual(try JournalSyncBridge.export(container: container).first { $0.id == "j-a" }?.text,
                               "v2c", "\(boundary)")
                XCTAssertEqual(try goalsRepo.load().energyKcal, 2100, "\(boundary)")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: authorityURL.path), "\(boundary)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path), "\(boundary)")
            journal = nil
            container = nil
        }
    }

    func testInsightImagesAreRefusedByDefaultOnCommitAndReplay() throws {
        let commit = makeCommit(before: [], after: [], insightBefore: [:],
                                insightAfter: ["i1": insightRecord(.seen, "a", 1000)])
        XCTAssertThrowsError(try makeJournal().commit(commit))
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
        // Only an explicit debug-test fixture can record this otherwise forbidden shape.
        let testJournal = try makeJournal(checkpoint: { boundary in
            if boundary == .afterIntentWrite { throw StubCrash.crash }
        }, allowsInsightContent: true)
        XCTAssertThrowsError(try testJournal.commit(commit))
        let bytes = try Data(contentsOf: intentURL)
        XCTAssertThrowsError(try makeJournal().recoverAndProject())
        XCTAssertEqual(try Data(contentsOf: intentURL), bytes)
        XCTAssertEqual(InsightLifecycleStore(accountID: "u1").exportRecords(), [:])
    }

    /// Injection checks the journal's retirement ordering, not simulated hardware loss.
    /// Write, readback and directory-sync failures must all leave a recoverable intent.
    func testGoalsDurabilityFailuresKeepIntentForValueAndDeletion() throws {
        let value = DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                        carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        for deletion in [false, true] {
            for step in [FamilySyncGoalsDurability.Step.beforeWrite, .beforeReadback, .beforeDirectorySync] {
                try? FileManager.default.removeItem(at: directory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: goalsFile)
                defaults.removeObject(forKey: "ate.sync.v1")
                let repository = NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: goalsFile))
                let before = deletion ? value : DailyNutritionGoals()
                let after = deletion ? DailyNutritionGoals() : value
                try repository.save(before)
                let journal = try makeJournal(goalsDurabilityCheckpoint: { actual in
                    if actual == step { throw StubCrash.crash }
                })
                XCTAssertThrowsError(try journal.commit(makeCommit(before: [], after: [],
                    goalsAfter: after, goalsBefore: before)))
                XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: authorityURL.path),
                               "no confirmed authority before goals durability succeeds")
                XCTAssertNotNil(try makeJournal().recoverAndProject())
                XCTAssertEqual(try repository.load(), after)
                XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
                XCTAssertEqual(FileManager.default.fileExists(atPath: goalsFile.path), !deletion)
            }
        }
    }

    func testUnchangedGoalsStillRequireDurabilityBeforeRetirement() throws {
        let value = DailyNutritionGoals(energyKcal: 2100, proteinGrams: nil,
                                        carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let repository = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: goalsFile))
        try repository.save(value)
        let journal = try makeJournal(goalsDurabilityCheckpoint: { _ in throw StubCrash.crash })
        XCTAssertThrowsError(try journal.commit(makeCommit(before: [], after: [],
            goalsAfter: value, goalsBefore: value)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: intentURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: authorityURL.path))
    }

    func testBareAuthorityRefusesForeignMetadataAndPreservesExactBytes() throws {
        let journal = try makeJournal()
        _ = try journal.commit(makeCommit(before: [], after: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
        var foreign = SyncMeta()
        foreign.userID = "u2"
        foreign.recipeStamps = ["foreign-recipe": 123]
        foreign.shopTombs = ["foreign-deletion": 456]
        let bytes = try JSONEncoder().encode(foreign)
        defaults.set(bytes, forKey: "ate.sync.v1")
        XCTAssertThrowsError(try makeJournal().recoverAndProject()) { error in
            guard case FamilySyncCommitJournal.Failure.ownerChanged = error else {
                return XCTFail("expected ownerChanged, got \(error)")
            }
        }
        XCTAssertEqual(defaults.data(forKey: "ate.sync.v1"), bytes)
    }

    func testResetMetadataRefusesForeignProjectionAndPreservesExactBytes() throws {
        let journal = try makeJournal()
        _ = try journal.commit(makeCommit(before: [], after: []))
        var foreign = SyncMeta()
        foreign.userID = "u2"
        foreign.recipeTombs = ["foreign-recipe": 123]
        foreign.shopStamps = ["foreign-shopping": 456]
        let bytes = try JSONEncoder().encode(foreign)
        defaults.set(bytes, forKey: "ate.sync.v1")
        liveScope = AccountDataScope(ownerID: "u1", generation: 2)
        XCTAssertThrowsError(try journal.resetMetadata(metadata(generation: 2),
            receipt: AccountGenerationPolicy.Receipt(ownerID: "u1", generation: 2))) { error in
            guard case FamilySyncCommitJournal.Failure.ownerChanged = error else {
                return XCTFail("expected ownerChanged, got \(error)")
            }
        }
        XCTAssertEqual(defaults.data(forKey: "ate.sync.v1"), bytes)
        // A later bare-authority attempt cannot bypass the common projection guard.
        XCTAssertThrowsError(try makeJournal().recoverAndProject())
        XCTAssertEqual(defaults.data(forKey: "ate.sync.v1"), bytes)
    }

    private enum StubCrash: Error { case crash }
}
