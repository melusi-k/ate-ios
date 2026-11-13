import XCTest
@testable import Ate

@MainActor
private final class RemountAuth: AuthService {
    var refreshBody: (AuthSession) async throws -> AuthSession = { $0 }
    func refresh(_ session: AuthSession) async throws -> AuthSession { try await refreshBody(session) }
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

/// Native UNRUN. Refresh/persistence/HTTP injected; actual local epoch+receipt.
@MainActor
final class RecipeShoppingSessionRemountTests: XCTestCase {
    private var current: AuthSession? = AuthSession(accessToken: "old", refreshToken: "fixture", expiresAt: 1,
        userID: "owner", email: "fixture@example.test")
    private func directory() throws -> URL {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let dir = requested.resolvingSymlinksInPath().standardizedFileURL
        let gate = try AccountWriterGate(directory: dir, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) { try AccountGenerationReceiptStore(directory: dir).save(.init(ownerID: "owner", generation: 0)) }
        return dir
    }
    private func owner(_ directory: URL, session: AuthSession, calls: @escaping (URLRequest) -> Void = { _ in }) throws -> RecipeShoppingSyncOwner {
        try RecipeShoppingSyncOwner(controlDirectory: directory,
            rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
                calls(request)
                return (Data(#"{"generation":0,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!)
            }), session: session, currentSession: { self.current })
    }
    func testRefreshRotatesOldEpochThenSnapshotAdmitsNewFullSessionBeforeBuild() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let old = try owner(dir, session: current!)
        _ = try await old.pull(session: current!); try await old.push([], session: current!)
        let auth = RemountAuth(); var events: [String] = []
        auth.refreshBody = { session in
            XCTAssertThrowsError(try old.withAdmittedWriterEffect { XCTFail("old writer still active") })
            events.append("refresh")
            var fresh = session; fresh.accessToken = "fresh"; fresh.expiresAt = 4_000_000_000; return fresh
        }
        let coordinator = RecipeShoppingSessionRemount<Int>(auth: auth, priorOwner: old,
            currentSession: { self.current }, persistSession: { self.current = $0; events.append("persist") },
            makeOwner: { session in try self.owner(dir, session: session, calls: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
                events.append(request.url!.lastPathComponent)
            }) }, buildGraph: { owner, session in
                try owner.validateBoundSession(session); events.append("build"); return 7
            })
        await coordinator.start()
        guard case .ready(let result) = coordinator.state else { return XCTFail("not ready") }
        XCTAssertEqual(result, 7); XCTAssertEqual(events, ["refresh", "persist", "account_data_snapshot", "build"])
        XCTAssertThrowsError(try old.withAdmittedWriterEffect {})
    }
    func testUnauthorizedRefreshSignsOutWithoutChangingLocalBytesOrBuilding() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let personal = dir.appendingPathComponent("pending-personal-fixture")
        let bytes = Data("recipe edits and shopping tombstones".utf8); try bytes.write(to: personal)
        let auth = RemountAuth(); auth.refreshBody = { _ in throw AuthError(.unauthorized, "fixture") }
        var builds = 0
        let coordinator = RecipeShoppingSessionRemount<Int>(auth: auth, priorOwner: nil,
            currentSession: { self.current }, persistSession: { self.current = $0 },
            makeOwner: { try self.owner(dir, session: $0) }, buildGraph: { _, _ in builds += 1; return 1 })
        await coordinator.start()
        guard case .signedOut = coordinator.state else { return XCTFail("not signed out") }
        XCTAssertNil(current); XCTAssertEqual(builds, 0); XCTAssertEqual(try Data(contentsOf: personal), bytes)
        XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read()?.generation, 0)
    }
    func testRetirementDuringSuspendedRefreshNeverPersistsOrBuildsLateResult() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let auth = RemountAuth()
        var resume: CheckedContinuation<AuthSession, Error>?
        var waiting: CheckedContinuation<Void, Never>?
        var started = false, persisted = 0, builds = 0
        auth.refreshBody = { _ in
            try await withCheckedThrowingContinuation { continuation in
                resume = continuation; started = true; waiting?.resume(); waiting = nil
            }
        }
        let coordinator = RecipeShoppingSessionRemount<Int>(auth: auth, priorOwner: nil,
            currentSession: { self.current }, persistSession: { self.current = $0; persisted += 1 },
            makeOwner: { try self.owner(dir, session: $0) }, buildGraph: { _, _ in builds += 1; return 1 })
        let original = current!
        let task = Task { await coordinator.start() }
        if !started { await withCheckedContinuation { waiting = $0 } }
        try coordinator.retire()
        var late = original; late.accessToken = "late"
        resume?.resume(returning: late)
        await task.value
        XCTAssertEqual(persisted, 0); XCTAssertEqual(builds, 0); XCTAssertEqual(current, original)
        guard case .failed = coordinator.state else { return XCTFail("late remount") }
    }
}
