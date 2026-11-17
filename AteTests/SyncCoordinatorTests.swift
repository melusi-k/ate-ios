import XCTest
@testable import Ate

final class SyncCoordinatorTests: XCTestCase {
    private final class Transport: SyncService {
        var pulls: [AuthSession] = []
        var pushed: [[SyncRecord]] = []
        var pushSessions: [AuthSession] = []
        var rows: [SyncRecord] = []
        var fail = false
        func pull(session: AuthSession) async throws -> [SyncRecord] {
            pulls.append(session)
            if fail { throw SyncError.unauthorized }
            return rows
        }
        func push(_ records: [SyncRecord], session: AuthSession) async throws {
            pushed.append(records); pushSessions.append(session)
            if fail { throw SyncError.unauthorized }
        }
    }
    @MainActor func testCoordinatorHasSingleLifecycleStateOwner() {
        let c = SyncCoordinator()
        XCTAssertEqual(c.state, .signedOut)
        c.state = .syncing; c.inFlight = true; c.requestedWhileBusy = true
        XCTAssertEqual(c.state, .syncing)
        XCTAssertTrue(c.inFlight); XCTAssertTrue(c.requestedWhileBusy)
    }
    @MainActor func testRemoteBoundaryPreservesExactSessionRowsAndErrors() async throws {
        let c = SyncCoordinator(); let service = Transport()
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000, userID: "owner", email: "fixture@example.invalid")
        let row = SyncRecord(user_id: "owner", kind: "shopping", id: "x", data: nil, updated_at: 123, deleted: true)
        service.rows = [row]
        let receipt = try await c.pull(using: service, session: session)
        XCTAssertEqual(receipt, [row]); XCTAssertEqual(service.pulls, [session])
        try await c.push(receipt, using: service, session: session)
        XCTAssertEqual(service.pushed, [[row]]); XCTAssertEqual(service.pushSessions, [session])
        service.fail = true
        do { _ = try await c.pull(using: service, session: session); XCTFail("Pull error lost") }
        catch SyncError.unauthorized {} catch { XCTFail("Pull error changed") }
        do { try await c.push([row], using: service, session: session); XCTFail("Push error lost") }
        catch SyncError.unauthorized {} catch { XCTFail("Push error changed") }
        XCTAssertEqual(c.state, .signedOut, "Transport cannot publish success before AppStore owner checks")
    }
}

final class SyncPayloadVersionTests: XCTestCase {
    private func row(_ fields: String, kind: String = "recipe") -> SyncRecord {
        SyncRecord(user_id: "owner", kind: kind, id: "r", data: AnyJSON(Data(fields.utf8)), updated_at: 10, deleted: false)
    }
    func testLegacyAndVersionOneRecipeAndShoppingRemainCompatible() throws {
        for declaration in ["", ",\"schemaVersion\":1"] {
            try SyncPayloadSafety.validate([
                row("{\"id\":\"r\",\"title\":\"Soup\",\"ingredients\":[],\"steps\":[]\(declaration)}"),
                row("{\"id\":\"r\",\"name\":\"Beans\",\"quantity\":1,\"unit\":\"bag\",\"done\":false\(declaration)}", kind: "shopping")
            ], owner: "owner")
        }
    }
    func testFutureMalformedAndAmbiguousVersionsFailEntireReceipt() {
        for version in ["999", "0", "-1", "true", "false", "null", "\"1\"", "[]", "{}", "1.5"] {
            XCTAssertThrowsError(try SyncPayloadSafety.validate([
                row("{\"id\":\"r\",\"title\":\"Soup\",\"schemaVersion\":\(version)}")
            ], owner: "owner"), version)
        }
        XCTAssertThrowsError(try SyncPayloadSafety.validate([
            row(#"{"id":"r","title":"Soup","schemaVersion":1,"schema_version":1}"#)
        ], owner: "owner"))
    }
    func testVersionOneDoesNotBypassDomainIdentityOrCoreFieldValidation() {
        for value in [#"{"id":"wrong","title":"Soup","schemaVersion":1}"#,
                      #"{"id":"r","title":"Soup","ingredients":"bad","schemaVersion":1}"#] {
            XCTAssertThrowsError(try SyncPayloadSafety.validate([row(value)], owner: "owner"))
        }
    }
}
