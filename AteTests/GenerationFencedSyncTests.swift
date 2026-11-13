import XCTest
@testable import Ate

/// Narrow async adapter contract tests. Native UNRUN. Does not certify a real durable
/// gate, Postgres concurrency, SwiftData writers or production startup composition.
@MainActor
final class GenerationFencedSyncTests: XCTestCase {
    private var current: AuthSession? = AuthSession(accessToken: "fixture", refreshToken: "fixture",
        expiresAt: 4_000_000_000, userID: "owner-a", email: "fixture@example.test")
    private var epoch = UUID()
    private enum FixtureError: Error { case staleLease }
    private func response(_ body: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://fixture.invalid")!,
            statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    private func make(_ perform: @escaping AccountDataResetService.Perform) -> GenerationFencedSync {
        GenerationFencedSync(rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!,
            key: "fixture", perform: perform), currentSession: { self.current },
            captureWriter: { self.epoch }, validateWriter: { lease in
                guard lease == self.epoch else { throw FixtureError.staleLease }
            })
    }
    private func row(_ id: String = "r", owner: String = "owner-a") -> SyncRecord {
        SyncRecord(user_id: owner, kind: "recipe", id: id, data: AnyJSON(Data("{}".utf8)),
                   updated_at: 1, deleted: false)
    }
    private func capture(_ generation: Int64 = 7) -> GenerationFencedSync.Capture {
        .init(ownerID: "owner-a", generation: generation, writerLease: epoch)
    }

    func testOwnerSwitchDuringSnapshotRefusesReturnedRows() async {
        let adapter = make { _ in
            self.current?.userID = "owner-b"
            return self.response(#"{"generation":7,"rows":[]}"#)
        }
        do { _ = try await adapter.snapshot(); XCTFail("old owner response accepted") }
        catch GenerationFencedSync.Error.ownerChanged {} catch { XCTFail("unexpected \(error)") }
    }
    func testSameOwnerReloginInvalidatesCapturedWriterEpoch() async {
        let adapter = make { _ in
            self.epoch = UUID() // real binding must advance durable epoch on session lifecycle
            return self.response(#"{"generation":7,"rows":[]}"#)
        }
        do { _ = try await adapter.snapshot(); XCTFail("stale lease accepted") }
        catch FixtureError.staleLease {} catch { XCTFail("unexpected \(error)") }
    }
    func testSnapshotRejectsMixedOwnerAndDuplicateRows() async throws {
        for rows in [[row(owner: "owner-b")], [row(), row()]] {
            let raw = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
            let adapter = make { _ in self.response("{\"generation\":7,\"rows\":\(raw)}") }
            do { _ = try await adapter.snapshot(); XCTFail("invalid rows accepted") }
            catch GenerationFencedSync.Error.mismatchedRowOwner {} catch GenerationFencedSync.Error.duplicateIdentity {}
            catch { XCTFail("unexpected \(error)") }
        }
    }
    func testInvalidBatchIsRefusedBeforeAnyPut() async {
        var calls = 0
        let adapter = make { _ in calls += 1; return self.response("null") }
        for rows in [[row(owner: "owner-b")], [row(), row()]] {
            do { try await adapter.push(rows, capture: capture()); XCTFail("invalid batch accepted") }
            catch GenerationFencedSync.Error.mismatchedRowOwner {} catch GenerationFencedSync.Error.duplicateIdentity {}
            catch { XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(calls, 0)
    }
    func testEveryPutUsesOriginalGenerationAndStopsOnPartialFailure() async throws {
        var generations: [Int64] = []
        let adapter = make { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            generations.append((body["p_caller_generation"] as! NSNumber).int64Value)
            if generations.count == 2 { return self.response(#"{"code":"PT409"}"#, status: 409) }
            return self.response("null")
        }
        do { try await adapter.push([row("a"), row("b"), row("c")], capture: capture(7)); XCTFail("partial batch accepted") }
        catch ResetRPCError.staleGeneration {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(generations, [7, 7], "no refetch, epoch promotion or third put after stale response")
    }
    func testEpochChangeAfterFirstPutStopsBeforeSecond() async {
        let original = capture()
        var calls = 0
        let adapter = make { _ in calls += 1; self.epoch = UUID(); return self.response("null") }
        do { try await adapter.push([row("a"), row("b")], capture: original); XCTFail("stale continuation accepted") }
        catch FixtureError.staleLease {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(calls, 1)
    }
}

extension GenerationFencedSyncTests {
    func testPermanentConflictPresentationDistinguishesPendingReset() {
        for operation in [AccountGenerationConflictState.Operation.snapshot, .put] {
            XCTAssertEqual(AccountGenerationConflictState.failure(.staleGeneration,
                during: operation, hasPendingReset: false), .staleLocalData)
            XCTAssertEqual(AccountGenerationConflictState.failure(.staleGeneration,
                during: operation, hasPendingReset: true), .pendingResetUnverified)
        }
        XCTAssertEqual(AccountGenerationConflictState.failure(.staleGeneration,
            during: .clear, hasPendingReset: false), .pendingResetUnverified)
    }
    func testUncertainResponseIsNotLabelledResetElsewhere() {
        for error in [ResetRPCError.outcomeUnverified("offline"), .unauthorized, .contractMissing] {
            XCTAssertNil(AccountGenerationConflictState.failure(error, during: .put, hasPendingReset: false))
        }
        XCTAssertFalse(AccountGenerationConflictState.staleLocalData.message.contains("another device"))
        XCTAssertTrue(AccountGenerationConflictState.pendingResetUnverified.message.contains("won't start another Clear all request"))
        XCTAssertTrue(AccountGenerationConflictState.staleLocalData.recoveryStatus.contains("not available"))
    }
}
