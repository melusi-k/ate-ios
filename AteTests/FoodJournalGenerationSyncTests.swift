import XCTest
@testable import Ate

@MainActor
final class FoodJournalGenerationSyncTests: XCTestCase {
    func testReceiptMismatchRefusesRowsAndPushNeedsSuccessfulPull() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncAdapter-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let receipts = try AccountGenerationReceiptStore(directory: root)
        try receipts.save(.init(ownerID: "owner", generation: 0))
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_102_444_800,
                                  userID: "owner", email: "fixture@example.invalid")
        var puts = 0
        let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
            if request.url!.lastPathComponent == "account_data_snapshot" {
                return (Data(#"{"generation":1,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            puts += 1
            return (Data("null".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let lease = UUID()
        let fenced = GenerationFencedSync(rpc: rpc, currentSession: { session }, captureWriter: { lease }, validateWriter: { _ in })
        let adapter = FoodJournalGenerationSync(fenced: fenced, receipts: receipts, currentSession: { session }, validate: {})
        do { _ = try await adapter.pull(session: session); XCTFail("Advanced remote generation must not publish rows") }
        catch FoodJournalGenerationSync.Failure.reconciliationRequired { }
        catch { XCTFail("Unexpected: \(error)") }
        do { try await adapter.push([], session: session); XCTFail("No successful pull") }
        catch FoodJournalGenerationSync.Failure.missingPull { }
        catch { XCTFail("Unexpected: \(error)") }
        XCTAssertEqual(puts, 0)
        XCTAssertEqual(try receipts.read()?.generation, 0, "No automatic fresh-epoch adoption")
    }
    func testSuccessfulPullAuthorizesOnlyOnePushAndSameOwnerTokenChangeRefuses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncAdapter-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let receipts = try AccountGenerationReceiptStore(directory: root)
        try receipts.save(.init(ownerID: "owner", generation: 4))
        var current = AuthSession(accessToken: "first", refreshToken: "fixture", expiresAt: 4_102_444_800,
                                  userID: "owner", email: "fixture@example.invalid")
        let first = current
        var puts = 0, changeDuringSnapshot = false
        let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
            if request.url!.lastPathComponent == "account_data_snapshot" {
                if changeDuringSnapshot { current.accessToken = "replacement" }
                return (Data(#"{"generation":4,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            puts += 1
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual((body["p_caller_generation"] as? NSNumber)?.int64Value, 4)
            return (Data("null".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let lease = UUID()
        let fenced = GenerationFencedSync(rpc: rpc, currentSession: { current }, captureWriter: { lease }, validateWriter: { _ in })
        let adapter = FoodJournalGenerationSync(fenced: fenced, receipts: receipts, currentSession: { current }, validate: {})
        let record = SyncRecord(user_id: "owner", kind: "recipe", id: "one", data: AnyJSON(Data("{}".utf8)), updated_at: 1, deleted: false)
        _ = try await adapter.pull(session: first)
        try await adapter.push([record], session: first)
        do { try await adapter.push([record], session: first); XCTFail("Cannot reuse capture") }
        catch FoodJournalGenerationSync.Failure.missingPull { }
        catch { XCTFail("Unexpected: \(error)") }
        changeDuringSnapshot = true
        do { _ = try await adapter.pull(session: first); XCTFail("Same-owner token change must refuse rows") }
        catch FoodJournalGenerationSync.Failure.identityChanged { }
        catch { XCTFail("Unexpected: \(error)") }
        do { try await adapter.push([record], session: current); XCTFail("Cannot adopt new token") }
        catch FoodJournalGenerationSync.Failure.missingPull { }
        catch { XCTFail("Unexpected: \(error)") }
        XCTAssertEqual(puts, 1)
    }

}
