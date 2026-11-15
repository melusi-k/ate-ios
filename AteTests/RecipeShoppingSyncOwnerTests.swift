import XCTest
@testable import Ate

/// Native UNRUN. Real file gate/receipt; injected HTTP only. No production requests.
@MainActor
final class RecipeShoppingSyncOwnerTests: XCTestCase {
    private var current: AuthSession? = AuthSession(accessToken: "fixture", refreshToken: "fixture",
        expiresAt: 4_000_000_000, userID: "owner", email: "fixture@example.test")

    private func directory() throws -> URL {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        return requested.resolvingSymlinksInPath().standardizedFileURL
    }
    private func response(_ rows: [SyncRecord] = [], generation: Int = 0) throws -> (Data, URLResponse) {
        let encoded = try JSONEncoder().encode(rows)
        let body = Data("{\"generation\":\(generation),\"rows\":".utf8) + encoded + Data("}".utf8)
        return (body, HTTPURLResponse(url: URL(string: "https://fixture.invalid")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!)
    }
    private func owner(_ directory: URL, _ perform: @escaping AccountDataResetService.Perform) throws -> RecipeShoppingSyncOwner {
        try RecipeShoppingSyncOwner(controlDirectory: directory,
            rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: perform),
            session: current!, currentSession: { self.current })
    }
    private func stamp(_ directory: URL, owner: String = "owner", generation: Int64 = 0) throws {
        let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) {
            try AccountGenerationReceiptStore(directory: directory).save(.init(ownerID: owner, generation: generation))
        }
    }

    func testMissingReceiptNeverFetchesStampsOrWrites() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var calls = 0
        let service = try owner(dir) { _ in calls += 1; return try self.response() }
        do { _ = try await service.pull(session: current!); XCTFail("missing receipt accepted") }
        catch RecipeShoppingSyncOwner.Refusal.receiptMissing {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(calls, 0)
        XCTAssertNil(try AccountGenerationReceiptStore(directory: dir).read())
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("not admitted") })
    }
    func testAdvancedGenerationKeepsReceiptAndPersonalBytes() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir, generation: 3)
        let personal = dir.appendingPathComponent("pending-fixture.json")
        let bytes = Data(#"{"recipeEdits":["r"],"shoppingTombstones":["s"]}"#.utf8)
        try bytes.write(to: personal)
        var paths: [String] = []
        let service = try owner(dir) { request in
            paths.append(request.url!.lastPathComponent); return try self.response(generation: 4)
        }
        do { _ = try await service.pull(session: current!); XCTFail("advanced accepted") }
        catch RecipeShoppingSyncOwner.Refusal.generationMismatch {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(try Data(contentsOf: personal), bytes)
        XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.generation, 3)
        XCTAssertEqual(paths, ["account_data_snapshot"])
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("stale write") })
    }
    func testSameOwnerNewTokenDuringSnapshotRefuses() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir)
        let original = current!
        let service = try owner(dir) { _ in self.current?.accessToken = "new-session"; return try self.response() }
        do { _ = try await service.pull(session: original); XCTFail("same owner new session accepted") }
        catch RecipeShoppingSyncOwner.Refusal.sessionChanged {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.generation, 0)
    }
    func testRecipeAndShoppingUseSnapshotThenOriginalGenerationRPCOnly() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir, generation: 3)
        var recipe = RecipeCard(title: "Fixture"); recipe.id = "same-id"
        let shopping = ShoppingItem(id: "same-id", name: "Fixture", quantity: 1, unit: "g")
        let rows = [SyncRecord(user_id: "owner", kind: "recipe", id: recipe.id,
                              data: AnyJSON(try JSONEncoder().encode(recipe)), updated_at: 1, deleted: false),
                    SyncRecord(user_id: "owner", kind: "shopping", id: shopping.id,
                              data: AnyJSON(try JSONEncoder().encode(shopping)), updated_at: 2, deleted: false)]
        var paths: [String] = [], kinds: [String] = []
        let service = try owner(dir) { request in
            paths.append(request.url!.lastPathComponent)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            if paths.count == 1 { return try self.response(rows, generation: 3) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual((body["p_caller_generation"] as! NSNumber).int64Value, 3)
            kinds.append(body["p_kind"] as! String)
            return (Data("null".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("before snapshot") })
        let pulled = try await service.pull(session: current!)
        XCTAssertEqual(pulled.count, 2)
        var effect = false
        try service.withAdmittedWriterEffect { effect = true }
        XCTAssertTrue(effect)
        try await service.push(rows, session: current!)
        XCTAssertEqual(paths, ["account_data_snapshot", "put_user_recipe", "put_user_recipe"])
        XCTAssertEqual(kinds, ["recipe", "shopping"])
        do { try await service.push(rows, session: current!); XCTFail("capture reused") }
        catch RecipeShoppingSyncOwner.Refusal.missingSnapshot {} catch { XCTFail("unexpected \(error)") }
    }
    func testPendingControlAndForeignReceiptNeverStartNetwork() async throws {
        for pending in [false, true] {
            let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
            try stamp(dir, owner: "foreign")
            if pending { try Data("pending".utf8).write(to: dir.appendingPathComponent("reset-control-v1.json")) }
            var calls = 0
            do {
                let service = try owner(dir) { _ in calls += 1; return try self.response() }
                _ = try await service.pull(session: current!)
                XCTFail("pending/foreign accepted")
            } catch { /* Fail closed at construction or receipt validation. */ }
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.ownerID, "foreign")
        }
    }
    func testMalformedLivePayloadRefusesBeforeAnyPut() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir)
        var calls = 0
        let service = try owner(dir) { _ in calls += 1; return try self.response() }
        _ = try await service.pull(session: current!)
        let invalid = SyncRecord(user_id: "owner", kind: "shopping", id: "s", data: AnyJSON(Data("{}".utf8)), updated_at: 1, deleted: false)
        do { try await service.push([invalid], session: current!); XCTFail("invalid payload accepted") }
        catch RecipeShoppingSyncOwner.Refusal.invalidRow {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(calls, 1)
    }
}

extension RecipeShoppingSyncOwnerTests {
    func testRegressedGenerationAndForeignRowsRefuseWithoutReceiptMutation() async throws {
        for foreignRows in [false, true] {
            let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
            try stamp(dir, generation: 3)
            let rows = foreignRows ? [SyncRecord(user_id: "foreign", kind: "recipe", id: "r", data: nil,
                                                updated_at: 1, deleted: true)] : []
            let service = try owner(dir) { _ in try self.response(rows, generation: foreignRows ? 3 : 2) }
            do { _ = try await service.pull(session: current!); XCTFail("regressed/foreign accepted") }
            catch { /* Adapter rejects owner; owner rejects regressed generation. */ }
            XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.generation, 3)
            XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("refused write") })
        }
    }
    func testOriginalGateLeaseRefusesAfterExternalInvalidation() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir)
        let service = try owner(dir) { _ in try self.response() }
        _ = try await service.pull(session: current!)
        let sibling = try AccountWriterGate(directory: dir, resetControlExists: { false })
        try sibling.invalidateWriters()
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("old local writer") })
        do { try await service.push([], session: current!); XCTFail("old async writer") }
        catch { /* Original lease remains stale, never recaptured. */ }
    }
    func testTombstonesKeepBothKindsAndPartialStalePutStopsWithoutReceiptAdvance() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir, generation: 3)
        let tombstones = ["recipe", "shopping"].map {
            SyncRecord(user_id: "owner", kind: $0, id: "same-id", data: nil, updated_at: 2, deleted: true)
        }
        var calls = 0
        let service = try owner(dir) { request in
            calls += 1
            if calls == 1 { return try self.response(generation: 3) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["p_deleted"] as? Bool, true)
            XCTAssertTrue(body["p_data"] is NSNull)
            XCTAssertEqual((body["p_caller_generation"] as! NSNumber).int64Value, 3)
            return (Data(#"{"code":"PT409"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 409,
                httpVersion: nil, headerFields: nil)!)
        }
        _ = try await service.pull(session: current!)
        do { try await service.push(tombstones, session: current!); XCTFail("partial stale put accepted") }
        catch ResetRPCError.staleGeneration {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(calls, 2, "stop before second put, no implicit retry")
        XCTAssertEqual(tombstones.count, 2, "input value is not consumed by refusal")
        XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.generation, 3)
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("refused writer") })
    }
}

/// Continuation barrier, no sleeps/timeouts. Response is released only by the test.
@MainActor
private final class RecipeShoppingTransportLatch {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<(Data, URLResponse), Never>?
    func suspend() async -> (Data, URLResponse) {
        await withCheckedContinuation { continuation in
            response = continuation; started = true
            waiter?.resume(); waiter = nil
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release(_ value: (Data, URLResponse)) { response?.resume(returning: value); response = nil }
}

extension RecipeShoppingSyncOwnerTests {
    func testSuspendedPullAbandonmentAndCancellationNeverAdmitReturnedRows() async throws {
        for cancel in [false, true] {
            let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
            try stamp(dir)
            let latch = RecipeShoppingTransportLatch()
            let service = try owner(dir) { _ in await latch.suspend() }
            let session = current!
            let task = Task { try await service.pull(session: session) }
            await latch.waitUntilStarted()
            if cancel { task.cancel() } else { service.abandonCycle() }
            latch.release(try response())
            do { _ = try await task.value; XCTFail("abandoned/cancelled pull returned rows") }
            catch RecipeShoppingSyncOwner.Refusal.abandonedCycle {} catch is CancellationError {}
            catch { XCTFail("unexpected \(error)") }
            XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("late admission") })
            XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.generation, 0)
        }
    }
    func testMidPushAbandonmentAndCancellationStopNextPutAndSuccess() async throws {
        for cancel in [false, true] {
            let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
            try stamp(dir)
            let latch = RecipeShoppingTransportLatch()
            var calls = 0
            let service = try owner(dir) { _ in
                calls += 1
                if calls == 1 { return try self.response() }
                return await latch.suspend()
            }
            let session = current!
            _ = try await service.pull(session: session)
            let rows = ["recipe", "shopping"].map {
                SyncRecord(user_id: "owner", kind: $0, id: "tomb", data: nil, updated_at: 1, deleted: true)
            }
            let task = Task { try await service.push(rows, session: session) }
            await latch.waitUntilStarted()
            if cancel { task.cancel() } else { service.abandonCycle() }
            latch.release(try response())
            do { try await task.value; XCTFail("abandoned/cancelled push succeeded") }
            catch RecipeShoppingSyncOwner.Refusal.abandonedCycle {} catch is CancellationError {}
            catch { XCTFail("unexpected \(error)") }
            XCTAssertEqual(calls, 2, "snapshot and first put only; no second put")
            XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("abandoned proof") })
        }
    }
    func testConcurrentRefusalKeepsActiveProofButMissingSnapshotRevokesIt() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir)
        let latch = RecipeShoppingTransportLatch()
        var calls = 0
        let service = try owner(dir) { _ in
            calls += 1
            if calls == 1 { return try self.response() }
            return await latch.suspend()
        }
        let session = current!
        _ = try await service.pull(session: session)
        let rows = [SyncRecord(user_id: "owner", kind: "shopping", id: "tomb", data: nil, updated_at: 1, deleted: true)]
        let task = Task { try await service.push(rows, session: session) }
        await latch.waitUntilStarted()
        do { _ = try await service.pull(session: session); XCTFail("concurrent accepted") }
        catch RecipeShoppingSyncOwner.Refusal.concurrentCycle {} catch { XCTFail("unexpected \(error)") }
        var effect = false
        try service.withAdmittedWriterEffect { effect = true }
        XCTAssertTrue(effect, "concurrent request alone does not revoke active cycle")
        latch.release(try response())
        try await task.value
        XCTAssertNoThrow(try service.withAdmittedWriterEffect {})
        do { try await service.push(rows, session: session); XCTFail("missing snapshot accepted") }
        catch RecipeShoppingSyncOwner.Refusal.missingSnapshot {} catch { XCTFail("unexpected \(error)") }
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("proof after missing snapshot") })
    }
    func testAbandonAfterSuccessfulCycleRevokesLocalCapability() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try stamp(dir)
        let service = try owner(dir) { _ in try self.response() }
        _ = try await service.pull(session: current!)
        try await service.push([], session: current!)
        XCTAssertNoThrow(try service.withAdmittedWriterEffect {})
        service.abandonCycle()
        XCTAssertThrowsError(try service.withAdmittedWriterEffect { XCTFail("abandoned completed capability") })
    }
}
