import XCTest
@testable import Ate

@MainActor
private final class ReadmissionAuth: AuthService {
    var refreshBody: (AuthSession) async throws -> AuthSession = { $0 }
    func refresh(_ s: AuthSession) async throws -> AuthSession { try await refreshBody(s) }
    func signUp(email: String, password: String) async throws -> AuthSession? { nil }
    func signIn(email: String, password: String) async throws -> AuthSession { throw AuthError("unused") }
    func sendMagicLink(email: String) async throws {}
    func resendConfirmation(email: String) async throws {}
    func recoverPassword(email: String) async throws {}
    func updatePassword(_ session: AuthSession, to password: String) async throws {}
    func session(fromCallback url: URL) async throws -> AuthCallback? { nil }
    func signOut(_ session: AuthSession) async {}
    func deleteAccount(_ session: AuthSession) async throws {}
}

/// Native UNRUN. No live requests; real local gate/receipt and explicit transport.
@MainActor
final class RecipeShoppingReadmission401Tests: XCTestCase {
    private var current: AuthSession? = .init(accessToken: "unexpired-rejected", refreshToken: "fixture", expiresAt: 4_000_000_000,
        userID: "owner", email: "fixture@example.test")
    private func directory() throws -> URL {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) { try AccountGenerationReceiptStore(directory: root).save(.init(ownerID: "owner", generation: 0)) }
        return root
    }
    private func response(_ code: Int, url: URL, pgcode: String = "") -> (Data, URLResponse) {
        let body = code == 200 ? #"{"generation":0,"rows":[]}"# : "{\"code\":\"\(pgcode)\"}"
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
    func testUnexpired401RefreshesOnceAndNewOwnerAdmitsWithNoPuts() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = ReadmissionAuth(); var refreshes = 0, snapshots = 0, builds = 0
        var owners: [RecipeShoppingSyncOwner] = []
        auth.refreshBody = { session in
            refreshes += 1
            XCTAssertThrowsError(try owners[0].withAdmittedWriterEffect {})
            var refreshed = session; refreshed.accessToken = "fresh"; return refreshed
        }
        let coordinator = RecipeShoppingSessionRemount<Int>(auth: auth, priorOwner: nil,
            currentSession: { self.current }, persistSession: { self.current = $0 }, makeOwner: { session in
                let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
                    XCTAssertEqual(request.url!.lastPathComponent, "account_data_snapshot")
                    snapshots += 1
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), snapshots == 1 ? "Bearer unexpired-rejected" : "Bearer fresh")
                    return self.response(snapshots == 1 ? 401 : 200, url: request.url!)
                })
                let owner = try RecipeShoppingSyncOwner(controlDirectory: root, rpc: rpc, session: session, currentSession: { self.current })
                owners.append(owner); return owner
            }, buildGraph: { owner, session in
                try owner.validateBoundSession(session); builds += 1; return 4
            })
        await coordinator.start()
        guard case .ready(let value) = coordinator.state else { return XCTFail("not ready") }
        XCTAssertEqual(value, 4); XCTAssertEqual(refreshes, 1); XCTAssertEqual(snapshots, 2); XCTAssertEqual(builds, 1)
        XCTAssertEqual(owners.count, 2)
        XCTAssertThrowsError(try owners[0].withAdmittedWriterEffect {})
    }
    func testPermissionGenerationOrSecond401DoesNotLoopOrBuild() async throws {
        for (code, pgcode) in [(403, ""), (400, "42501"), (409, "PT409"), (401, "")] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let auth = ReadmissionAuth(); var refreshes = 0, calls = 0, builds = 0
            auth.refreshBody = { session in refreshes += 1; var s = session; s.accessToken = "fresh"; return s }
            let coordinator = RecipeShoppingSessionRemount<Int>(auth: auth, priorOwner: nil,
                currentSession: { self.current }, persistSession: { self.current = $0 }, makeOwner: { session in
                    try RecipeShoppingSyncOwner(controlDirectory: root,
                        rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
                            calls += 1; return self.response(code, url: request.url!, pgcode: pgcode)
                        }), session: session, currentSession: { self.current })
                }, buildGraph: { _, _ in builds += 1; return 0 })
            await coordinator.start()
            guard case .failed = coordinator.state else { return XCTFail("unsafe remount") }
            XCTAssertEqual(refreshes, code == 401 ? 1 : 0)
            XCTAssertEqual(calls, code == 401 ? 2 : 1); XCTAssertEqual(builds, 0)
            XCTAssertNotNil(current)
        }
    }
    func testFailedSessionPersistencePreventsNewAdmission() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = ReadmissionAuth(); var calls = 0
        enum Injected: Error { case disk }
        auth.refreshBody = { session in var fresh = session; fresh.accessToken = "fresh"; return fresh }
        let coordinator = RecipeShoppingSessionRemount<Int>(auth: auth, priorOwner: nil,
            currentSession: { self.current }, persistSession: { _ in throw Injected.disk }, makeOwner: { _ in
                calls += 1; throw Injected.disk
            }, buildGraph: { _, _ in XCTFail("unpersisted graph"); return 0 })
        await coordinator.start(forceRefresh: true)
        guard case .failed = coordinator.state else { return XCTFail("unsafe remount") }
        XCTAssertEqual(calls, 0); XCTAssertEqual(current?.accessToken, "unexpired-rejected")
    }
}
