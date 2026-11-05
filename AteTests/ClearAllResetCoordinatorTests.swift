import XCTest
@testable import Ate

/// Candidate fault-injection fixtures for the reset coordinator + RPC client.
/// WRITTEN, NOT EXECUTED natively. Transport is injected at AccountDataResetService's
/// `perform` seam; gate/surfaces/receipt are fakes; UserDefaults is an isolated suite.
/// These pin fail-closed behavior: no fabricated success, no fresh UUID over doubt.
@MainActor final class ClearAllResetCoordinatorTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "clearall-tests-\(UUID().uuidString)")
    }

    private let session = AuthSession(accessToken: "t", refreshToken: "r",
                                      expiresAt: Date.distantFuture.timeIntervalSince1970,
                                      userID: "owner-a", email: "a@example.com")

    // MARK: Fakes

    private final class FakeGate: ClearAllWriterGating {
        struct GateError: Error {}
        private(set) var acquired = false
        var failValidateAfter = Int.max
        var failOnAcquire = false
        private(set) var events: [String] = []
        private var validations = 0
        var onAcquire: (() throws -> Void)?
        func acquireResetGate() throws {
            if failOnAcquire { throw GateError() }
            try onAcquire?()   // simulate another holder acting while we wait
            acquired = true
            events.append("acquire")
        }
        func validateResetGate() throws {
            events.append("validate")
            guard acquired else { throw GateError() }   // validation without a held gate is a defect
            validations += 1
            if validations > failValidateAfter { throw ClearAllLocalData.Error.unavailableStore }
        }
        func releaseResetGate() { acquired = false; events.append("release") }
    }

    private struct FakeSurfaces: ClearAllSystemSurfaceCleaning {
        var uncleaned: [String] = []
        func cleanupAfterLocalErase() async -> [String] { uncleaned }
    }

    private func http(_ code: Int, _ body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://example.test")!,
                                          statusCode: code, httpVersion: nil, headerFields: nil)!)
    }

    /// A trivial real component so the local phase can genuinely complete.
    private func fixtureComponents() -> ([ClearAllLocalData.Component], Set<String>) {
        let store = UserDefaults(suiteName: "clearall-fixture-\(UUID().uuidString)")!
        store.set("x", forKey: "k")
        let component = ClearAllLocalData.Component(
            name: "fixture-store",
            erase: { store.removeObject(forKey: "k") },
            verifyEmpty: { if store.object(forKey: "k") != nil { throw ClearAllLocalData.Error.notEmpty } })
        return ([component], ["fixture-store"])
    }

    /// removeObject never retires: drives the saveControl(nil) verification failure.
    private final class RetireFailingDefaults: UserDefaults {
        override func removeObject(forKey defaultName: String) { /* never retires */ }
    }

    /// data(forKey:) returns garbage for the control key: drives readback failure.
    private final class ReadbackCorruptingDefaults: UserDefaults {
        override func data(forKey defaultName: String) -> Data? {
            if defaultName == ClearAllResetCoordinator.controlKey { return Data("corrupt".utf8) }
            return super.data(forKey: defaultName)
        }
    }

    private func makeCoordinator(
        transport: @escaping AccountDataResetService.Perform,
        gate: ClearAllWriterGating = FakeGate(),
        surfaces: ClearAllSystemSurfaceCleaning = FakeSurfaces(),
        currentSession: (() -> AuthSession?)? = nil,
        controlStore: UserDefaults? = nil,
        receiptSink: @escaping (Int64) throws -> Void = { _ in },
        components: @escaping () throws -> ([ClearAllLocalData.Component], Set<String>) = { ([], ["fixture-store"]) }
    ) -> ClearAllResetCoordinator {
        let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!,
                                          key: "anon", perform: transport)
        return ClearAllResetCoordinator(
            rpc: rpc, gate: gate, surfaces: surfaces, controlPersistence: DefaultsResetControlPersistence(defaults: controlStore ?? defaults,
                key: ClearAllResetCoordinator.controlKey),
            currentSession: currentSession ?? { self.session }, receiptSink: receiptSink,
            components: components)
    }

    private func seed(_ record: ClearAllResetCoordinator.ControlRecord) {
        defaults.set(try! JSONEncoder().encode(record), forKey: ClearAllResetCoordinator.controlKey)
    }

    private func record(phase: ClearAllResetCoordinator.Phase,
                        confirmed: Int64? = nil, pending: [String] = []) -> ClearAllResetCoordinator.ControlRecord {
        .init(ownerID: session.userID, requestID: UUID(), expectedGeneration: 0,
              phase: phase, confirmedGeneration: confirmed, pendingComponents: pending)
    }

    // MARK: Transport contract

    func testMalformedSnapshotRowsAreUnverifiedNotFabricatedEmpty() async {
        let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                          perform: { _ in self.http(200, #"{"generation":0,"rows":[{"broken":true}]}"#) })
        await assertThrows(Outcome { try await rpc.snapshot(session: self.session) }) {
            guard case .outcomeUnverified = $0 as? ResetRPCError else { return XCTFail("malformed rows must not decode as []") }
        }
    }

    func testBoolOrFractionalGenerationIsRejected() async {
        for body in [#"{"generation":true,"rows":[]}"#, #"{"generation":1.5,"rows":[]}"#] {
            let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                              perform: { _ in self.http(200, body) })
            await assertThrows(Outcome { try await rpc.snapshot(session: self.session) }) {
                guard case .outcomeUnverified = $0 as? ResetRPCError else { return XCTFail("non-integer generation accepted") }
            }
        }
    }

    func testPutRecipeRefusesInvalidJSONPayloadBeforeSending() async {
        var sent = 0
        let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                          perform: { _ in sent += 1; return self.http(200, "null") })
        await assertThrows(Outcome {
            try await rpc.putRecipe(session: self.session, callerGeneration: 0, kind: "recipe",
                                    id: "x", data: Data("not json".utf8), updatedAt: 1, deleted: false)
        }) {
            guard case .invalidRequest = $0 as? ResetRPCError else { return XCTFail("invalid payload must be refused") }
        }
        XCTAssertEqual(sent, 0, "no request may leave with a silently rewritten payload")
    }

    func testClearReceiptMustFollowExpectedGeneration() async {
        for receipt in ["0", "2", "7"] {   // expected 0 -> only 1 is a valid receipt
            let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                              perform: { _ in self.http(200, receipt) })
            await assertThrows(Outcome {
                try await rpc.clearAccount(session: self.session, requestID: UUID(), expectedGeneration: 0)
            }) {
                guard case .outcomeUnverified = $0 as? ResetRPCError else { return XCTFail("receipt \(receipt) accepted") }
            }
        }
    }

    func testLostClearResponseIsUnverifiedNeverSuccessOrFailure() async {
        let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                          perform: { _ in throw URLError(.networkConnectionLost) })
        await assertThrows(Outcome {
            try await rpc.clearAccount(session: self.session, requestID: UUID(), expectedGeneration: 0)
        }) {
            guard case .outcomeUnverified = $0 as? ResetRPCError else { return XCTFail("lost response misclassified") }
        }
    }

    // MARK: Coordinator control integrity

    func testResumeNeverValidatesBeforeAcquiringAndAcquireFailureStopsEverything() async {
        // Pending record: the resume path must acquire the gate before any use.
        seed(record(phase: .requested))
        let gate = FakeGate()
        gate.failOnAcquire = true
        var rpcCalls = 0
        let c = makeCoordinator(transport: { _ in rpcCalls += 1; return self.http(200, "1") },
                                gate: gate)
        let state = await c.start()
        guard case .unavailable = state else { return XCTFail("acquire failure must stop the attempt, got \(state)") }
        XCTAssertEqual(rpcCalls, 0)
        XCTAssertFalse(gate.events.contains("validate"), "validation happened without a held gate")

        // Same pending record, working gate: the first gate event is always acquire.
        let gate2 = FakeGate()
        let c2 = makeCoordinator(transport: { _ in self.http(200, "1") }, gate: gate2)
        _ = await c2.start()
        XCTAssertEqual(gate2.events.first, "acquire")
        if let firstValidate = gate2.events.firstIndex(of: "validate"),
           let firstAcquire = gate2.events.firstIndex(of: "acquire") {
            XCTAssertLessThan(firstAcquire, firstValidate)
        } else { XCTFail("pending resume never validated the gate") }
    }

    func testReceiptHandoffHappensWhileControlRecordStillPresent() async {
        seed(record(phase: .cloudCommitted, confirmed: 1))
        var recordPresentAtSink: Bool?
        let c = makeCoordinator(
            transport: { _ in XCTFail("cloud phase must not re-run"); return self.http(200, "1") },
            receiptSink: { [defaults] _ in
                recordPresentAtSink = defaults!.data(forKey: ClearAllResetCoordinator.controlKey) != nil
            },
            components: { self.fixtureComponents() })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(recordPresentAtSink, true,
                       "receipt must be handed off BEFORE the control record is retired")
    }

    func testSnapshotRejectsLegacyRepairedFields() async {
        // The legacy SyncRecord decoder would repair these; the reset boundary must not.
        let badRows = [
            #"{"generation":0,"rows":[{"user_id":"u","kind":"recipe","id":"r1","data":null,"updated_at":1}]}"#,                  // missing deleted -> repaired false
            #"{"generation":0,"rows":[{"user_id":"u","kind":"recipe","id":"r1","data":null,"updated_at":"1","deleted":false}]}"#, // string updated_at -> repaired
            #"{"generation":0,"rows":[{"user_id":"u","kind":"recipe","id":"r1","data":null,"updated_at":1.5,"deleted":false}]}"#,  // fractional -> repaired
            #"{"generation":0,"rows":[{"user_id":"u","kind":"","id":"r1","data":null,"updated_at":1,"deleted":false}]}"#,          // empty kind
            #"{"generation":0,"rows":[{"user_id":"u","kind":"recipe","id":"r1","updated_at":1,"deleted":false}]}"#,                  // missing data key
        ]
        for body in badRows {
            let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                              perform: { _ in self.http(200, body) })
            await assertThrows(Outcome { try await rpc.snapshot(session: self.session) }) {
                guard case .outcomeUnverified = $0 as? ResetRPCError else { return XCTFail("repaired row accepted: \(body)") }
            }
        }
        // Positive control: an exact row decodes.
        let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                          perform: { _ in self.http(200, #"{"generation":0,"rows":[{"user_id":"u","kind":"recipe","id":"r1","data":null,"updated_at":1,"deleted":false}]}"#) })
        let snap = try! await rpc.snapshot(session: session)
        XCTAssertEqual(snap.rows.count, 1)
        XCTAssertEqual(snap.rows[0].id, "r1")
    }

    func testGateAcquireRaceResumesInjectedRecordSameUUID() async {
        // Another holder commits its own requested record while start() waits on the
        // gate. start() must resume THAT attempt, never mint a fresh UUID over it.
        let injected = record(phase: .requested)
        let gate = FakeGate()
        gate.onAcquire = { [defaults] in
            defaults!.set(try! JSONEncoder().encode(injected),
                          forKey: ClearAllResetCoordinator.controlKey)
        }
        var requestIDs: [String] = []
        let c = makeCoordinator(transport: { r in
            let body = (try? JSONSerialization.jsonObject(with: r.httpBody!)) as? [String: Any]
            guard let id = body?["request_id"] as? String else {
                XCTFail("a fresh attempt snapshots first - the race record must win")
                return self.http(200, #"{"generation":0,"rows":[]}"#)
            }
            requestIDs.append(id)
            return self.http(200, "1")
        }, gate: gate, components: { self.fixtureComponents() })
        let state = await c.start()
        XCTAssertEqual(requestIDs, [injected.requestID.uuidString.lowercased()],
                       "must resume the injected attempt's UUID")
        XCTAssertEqual(state, .completed)
    }

    func testSemanticallyImpossibleRecordsFailClosed() async {
        // Empty owner.
        seed(ClearAllResetCoordinator.ControlRecord(
            ownerID: "", requestID: UUID(), expectedGeneration: 0,
            phase: .requested, confirmedGeneration: nil, pendingComponents: []))
        var rpcCalls = 0
        var c = makeCoordinator(transport: { _ in rpcCalls += 1; return self.http(200, "1") })
        var state = await c.start()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertEqual(rpcCalls, 0)
        // Requested phase carrying a receipt.
        seed(ClearAllResetCoordinator.ControlRecord(
            ownerID: session.userID, requestID: UUID(), expectedGeneration: 0,
            phase: .requested, confirmedGeneration: 1, pendingComponents: []))
        c = makeCoordinator(transport: { _ in rpcCalls += 1; return self.http(200, "1") })
        state = await c.start()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertEqual(rpcCalls, 0, "impossible records must never issue an RPC")
    }

    func testFailedRetirementIsUnverifiedAndRecordSurvives() async {
        let sabotaged = RetireFailingDefaults(suiteName: "clearall-retire-\(UUID().uuidString)")!
        sabotaged.set(try! JSONEncoder().encode(record(phase: .cloudCommitted, confirmed: 1)),
                      forKey: ClearAllResetCoordinator.controlKey)
        let c = makeCoordinator(transport: { _ in self.http(200, "1") },
                                controlStore: sabotaged,
                                components: { self.fixtureComponents() })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .serverOutcomeUnverified, "a failed retirement is never reported completed")
        XCTAssertNotNil(sabotaged.object(forKey: ClearAllResetCoordinator.controlKey))
    }

    func testContractMissingOnResumedRecordKeepsRecordAndUnverified() async {
        // A resumed requested record + 404: the earlier attempt may have committed
        // while the contract existed. The 404 proves nothing about it.
        seed(record(phase: .requested))
        let c = makeCoordinator(transport: { _ in self.http(404, "{}") })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertNotNil(defaults.object(forKey: ClearAllResetCoordinator.controlKey),
                        "a resumed record must never retire on a 404")
    }

    func testContractMissingFreshAttemptRetiresButFailureIsUnverified() async {
        // Fresh attempt whose clear RPC 404s: nothing ran, so retirement is honest -
        // unless the retirement itself fails, which must surface as unverified.
        let sabotaged = RetireFailingDefaults(suiteName: "clearall-retire-\(UUID().uuidString)")!
        var calls = 0
        let c = makeCoordinator(transport: { _ in
            calls += 1
            return calls == 1 ? self.http(200, #"{"generation":0,"rows":[]}"#) : self.http(404, "{}")
        }, controlStore: sabotaged)
        let state = await c.start()
        XCTAssertEqual(state, .serverOutcomeUnverified,
                       "suppressing a failed retirement turns durable doubt into a false all-clear")
        XCTAssertNotNil(sabotaged.object(forKey: ClearAllResetCoordinator.controlKey))
    }

    func testReadbackCorruptionStopsBeforeAnyResetRPC() async {
        let corrupting = ReadbackCorruptingDefaults(suiteName: "clearall-readback-\(UUID().uuidString)")!
        var clearRequests = 0
        var calls = 0
        let c = makeCoordinator(transport: { r in
            calls += 1
            let body = (try? JSONSerialization.jsonObject(with: r.httpBody!)) as? [String: Any]
            if body?["request_id"] != nil { clearRequests += 1 }
            return self.http(200, #"{"generation":0,"rows":[]}"#)
        }, controlStore: corrupting)
        let state = await c.start()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertEqual(calls, 1, "only the snapshot may run")
        XCTAssertEqual(clearRequests, 0, "no reset RPC without a proven-durable request UUID")
    }

    func testGateLostDuringCloudAwaitKeepsReceiptUnpersisted() async {
        seed(record(phase: .requested))
        let gate = FakeGate()
        gate.failValidateAfter = 2   // resume + pre-RPC pass; the post-await check fails
        let c = makeCoordinator(transport: { _ in self.http(200, "1") }, gate: gate)
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertNil(c.confirmedGeneration, "receipt must not persist across a lost gate")
        XCTAssertNotNil(defaults.object(forKey: ClearAllResetCoordinator.controlKey),
                        "record kept for recovery")
    }

    func testWrongTypeControlValueFailsClosedAndIssuesNoRPC() async {
        // A PRESENT value of the wrong type must not read as "no record".
        for value: Any in ["a string", true, 7, ["k": "v"]] {
            defaults.set(value, forKey: ClearAllResetCoordinator.controlKey)
            var rpcCalls = 0
            let c = makeCoordinator(transport: { _ in rpcCalls += 1; return self.http(200, "1") })
            let state = await c.start()
            XCTAssertEqual(state, .serverOutcomeUnverified)
            XCTAssertEqual(rpcCalls, 0, "wrong-type control value allowed a fresh reset UUID")
            defaults.removeObject(forKey: ClearAllResetCoordinator.controlKey)
        }
    }

    func testCloudCommittedRecordWithoutReceiptNeverErases() async {
        // Decodable but semantically impossible: committed phase, no receipt.
        seed(record(phase: .cloudCommitted, confirmed: nil))
        var erased = 0
        let store = UserDefaults(suiteName: "clearall-fixture-\(UUID().uuidString)")!
        store.set("x", forKey: "k")
        let component = ClearAllLocalData.Component(
            name: "fixture-store",
            erase: { erased += 1; store.removeObject(forKey: "k") },
            verifyEmpty: { if store.object(forKey: "k") != nil { throw ClearAllLocalData.Error.notEmpty } })
        let c = makeCoordinator(transport: { _ in XCTFail("no RPC may run"); return self.http(200, "1") },
                                components: { ([component], ["fixture-store"]) })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertEqual(erased, 0, "erase ran before the receipt gate")
    }

    func testClearAccountRejectsOutOfRangeExpectedGenerationBeforeSending() async {
        for bad: Int64 in [-1, Int64.max] {
            var sent = 0
            let rpc = AccountDataResetService(baseURL: URL(string: "https://example.test")!, key: "anon",
                                              perform: { _ in sent += 1; return self.http(200, "1") })
            await assertThrows(Outcome {
                try await rpc.clearAccount(session: self.session, requestID: UUID(), expectedGeneration: bad)
            }) {
                guard case .invalidRequest = $0 as? ResetRPCError else { return XCTFail("expectedGeneration \(bad) accepted") }
            }
            XCTAssertEqual(sent, 0, "out-of-range expectedGeneration left the client")
        }
    }

    func testCorruptControlRecordFailsClosedAndIssuesNoRPC() async {
        defaults.set(Data("garbage".utf8), forKey: ClearAllResetCoordinator.controlKey)
        var rpcCalls = 0
        let c = makeCoordinator(transport: { _ in rpcCalls += 1; return self.http(200, "1") })
        let state = await c.start()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertEqual(rpcCalls, 0, "a fresh reset UUID must never be issued over corrupt durable state")
    }

    func testRelaunchAfterCloudCommitRestoresReceiptAndResumesLocally() async {
        // Pre-seed the durable record as if the app crashed after the cloud commit.
        seed(record(phase: .cloudCommitted, confirmed: 1))
        var receipt: Int64?
        let c = makeCoordinator(
            transport: { _ in XCTFail("cloud phase must not re-run"); return self.http(200, "1") },
            receiptSink: { receipt = $0 },
            components: { self.fixtureComponents() })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(c.confirmedGeneration, 1, "receipt restored from the record on load")
        XCTAssertEqual(receipt, 1, "the receipt is handed off from the restored record")
        XCTAssertNil(defaults.data(forKey: ClearAllResetCoordinator.controlKey), "record retired after receipt handoff")
    }

    func testReceiptSinkFailureKeepsRecordAndNeverRetiresIt() async {
        seed(record(phase: .cloudCommitted, confirmed: 1))
        struct SinkError: Error {}
        let c = makeCoordinator(transport: { _ in self.http(200, "1") },
                                receiptSink: { _ in throw SinkError() },
                                components: { self.fixtureComponents() })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .serverOutcomeUnverified)
        XCTAssertNotNil(defaults.data(forKey: ClearAllResetCoordinator.controlKey),
                        "crash gap: the record outlives an unpersisted receipt")
    }

    func testAccountSwitchMidFlightStopsAtUnverified() async {
        var owner = "owner-a"
        seed(record(phase: .requested))
        let c = makeCoordinator(
            transport: { _ in owner = "owner-b"; return self.http(200, "1") },   // switch during the RPC await
            currentSession: { self.session.with(userID: owner) })
        let state = await c.resumeIfPending()
        XCTAssertEqual(state, .serverOutcomeUnverified, "post-await owner change must stop the reset")
    }

    func testGateLostMidLocalPhaseReportsIncompleteNeverCompleted() async {
        seed(record(phase: .cloudCommitted, confirmed: 1))
        let gate = FakeGate()
        gate.failValidateAfter = 2   // requireOwner passes, execute's first in-loop check fails
        let c = makeCoordinator(transport: { _ in self.http(200, "1") }, gate: gate,
                                components: { self.fixtureComponents() })
        let state = await c.resumeIfPending()
        guard case .cloudCommittedLocalIncomplete = state else {
            return XCTFail("gate loss mid-erase must surface as incomplete, got \(state)")
        }
        XCTAssertNotNil(defaults.data(forKey: ClearAllResetCoordinator.controlKey),
                        "record kept for idempotent retry")
    }

    func testLostClearThenResumeUsesSameRequestUUIDAndCompletes() async {
        var requestIDs: [String] = []
        var calls = 0
        let c = makeCoordinator(transport: { r in
            calls += 1
            if calls == 1 {
                return self.http(200, #"{"generation":0,"rows":[]}"#)   // snapshot
            }
            let body = try! JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
            guard let id = body["request_id"] as? String else { XCTFail("unexpected request"); return self.http(500, "{}") }
            requestIDs.append(id)
            if requestIDs.count == 1 { throw URLError(.networkConnectionLost) }   // lost response
            return self.http(200, "1")   // idempotent replay returns the same new generation
        }, components: { self.fixtureComponents() })
        let first = await c.start()
        XCTAssertEqual(first, .serverOutcomeUnverified)
        let second = await c.resumeIfPending()
        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(Set(requestIDs).count, 1, "recovery retries the SAME request UUID, never a fresh one")
        XCTAssertEqual(second, .completed)
    }

    // MARK: Helpers

    private struct Outcome<T> { let run: () async throws -> T }
    private func assertThrows<T>(_ outcome: Outcome<T>, _ check: (Error) -> Void) async {
        do { _ = try await outcome.run(); XCTFail("expected throw") } catch { check(error) }
    }
}

private extension AuthSession {
    func with(userID: String) -> AuthSession {
        AuthSession(accessToken: accessToken, refreshToken: refreshToken,
                    expiresAt: expiresAt, userID: userID, email: email)
    }
}
