import XCTest
@testable import Ate

/// Actual dependency composition, fixture RPC only. Does not certify live Postgres,
/// all production participants, power loss or actual app/device activation.
@MainActor
final class AccountResetCompositionTests: XCTestCase {
    private struct Surfaces: ClearAllSystemSurfaceCleaning {
        let failures: [String]
        func cleanupAfterLocalErase() async -> [String] { failures }
    }
    private let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
                                      userID: "owner-a", email: "fixture@example.test")
    private func fixture(_ run: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await run(directory)
    }
    private func graph(_ directory: URL, surfaceFailures: [String] = [], erased: @escaping () -> Void) throws -> AccountResetComposition {
        let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
            let body = request.url!.lastPathComponent == "account_data_snapshot"
                ? #"{"generation":0,"rows":[]}"# : "1"
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        return try AccountResetComposition(controlDirectory: directory, rpc: rpc, currentSession: { self.session },
            surfaces: Surfaces(failures: surfaceFailures), components: {
                ([ClearAllLocalData.Component(name: "fixture", erase: erased, verifyEmpty: {})], ["fixture"])
            })
    }
    func testActualResetPersistsReceiptRetiresControlThenPolicyAdmitsLazyGraph() async throws {
        try await fixture { directory in
            var erased = false
            let graph = try self.graph(directory, erased: { erased = true })
            let state = await graph.reset.start()
            XCTAssertEqual(state, .completed)
            XCTAssertTrue(erased)
            XCTAssertNil(try graph.control.read())
            XCTAssertEqual(try graph.receipt.read(), .init(ownerID: "owner-a", generation: 1))
            var events: [String] = []
            let startup = graph.startup(authorizeLocalState: { _, composition in
                events.append("policy")
                let decision = AccountGenerationPolicy.decide(receipt: try composition.receipt.read(),
                    ownerID: "owner-a", remoteGeneration: 1, allPersonalLocalStateVerifiedEmpty: true)
                XCTAssertEqual(decision, .mergeCurrentGeneration)
            }, buildGraph: { lease, composition in
                events.append("construct")
                try composition.gate.withWriterEffect(lease) {}
                return 7
            })
            await startup.start()
            XCTAssertEqual(events, ["policy", "construct"])
            guard case .ready(7) = startup.state else { return XCTFail("actual dependency graph did not admit") }
        }
    }
    func testUnacknowledgedWatchSurfaceRetainsControlAndBlocksOrdinaryGraph() async throws {
        try await fixture { directory in
            let graph = try self.graph(directory, surfaceFailures: ["watch acknowledgement"], erased: {})
            let state = await graph.reset.start()
            XCTAssertEqual(state, .cloudCommittedLocalIncomplete(["watch acknowledgement"]))
            XCTAssertNotNil(try graph.control.read())
            XCTAssertThrowsError(try graph.gate.captureWriter())
            var built = false
            let startup = graph.startup(authorizeLocalState: { _, _ in XCTFail("no admission") },
                buildGraph: { _, _ in built = true; return 1 })
            await startup.start()
            XCTAssertFalse(built)
            guard case .blocked = startup.state else { return XCTFail("must block") }
        }
    }
    func testPolicyRefusalPrecedesAllOrdinaryConstructors() async throws {
        enum PolicyFault: Error { case legacyUnverified }
        try await fixture { directory in
            let graph = try self.graph(directory, erased: {})
            var built = false
            let startup = graph.startup(authorizeLocalState: { _, composition in
                let decision = AccountGenerationPolicy.decide(receipt: try composition.receipt.read(),
                    ownerID: "owner-a", remoteGeneration: 3, allPersonalLocalStateVerifiedEmpty: false)
                XCTAssertEqual(decision, .legacyLocalStateNeedsReconciliation)
                throw PolicyFault.legacyUnverified
            }, buildGraph: { _, _ in built = true; return 1 })
            await startup.start()
            XCTAssertFalse(built)
            guard case .failed = startup.state else { return XCTFail("must not admit legacy bytes") }
        }
    }
}
