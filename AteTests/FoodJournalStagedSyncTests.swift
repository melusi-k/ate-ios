import XCTest
@testable import Ate

@MainActor
final class FoodJournalStagedSyncTests: XCTestCase {
    private enum Injected: Error { case network, commit }
    @MainActor private final class Fixture {
        let root: URL
        var current = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_102_444_800,
                                  userID: "owner", email: "fixture@example.invalid")
        var local: FoodJournalGenerationSync.LocalSnapshot
        var adapter: FoodJournalGenerationSync!
        var beforeResponse: ((URLRequest) async throws -> Void)?
        var puts = 0, commits = 0
        init() throws {
            let requested = FileManager.default.temporaryDirectory.appendingPathComponent("StagedSync-\(UUID())")
            try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
            root = requested.resolvingSymlinksInPath().standardizedFileURL
            var meta = RecipeShoppingSyncStage.Metadata()
            meta.userID = "owner"; meta.recipeStamps = ["one": 5]
            local = .init(recipes: [RecipeCard(id: "one", title: "Keep")], shopping: [], metadata: meta)
            let receipts = try AccountGenerationReceiptStore(directory: root)
            try receipts.save(.init(ownerID: "owner", generation: 4))
            let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { [self] request in
                let snapshot = request.url!.lastPathComponent == "account_data_snapshot"
                if !snapshot { puts += 1 }
                try await beforeResponse?(request)
                let bytes = snapshot ? Data(#"{"generation":4,"rows":[]}"#.utf8) : Data("null".utf8)
                return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            let lease = UUID()
            let fenced = GenerationFencedSync(rpc: rpc, currentSession: { self.current }, captureWriter: { lease }, validateWriter: { _ in })
            adapter = FoodJournalGenerationSync(fenced: fenced, receipts: receipts, currentSession: { self.current }, validate: {})
        }
        func run(commitError: Bool = false) async throws -> Int {
            try await adapter.syncRecipeShopping(session: current, readLocal: { self.local }, commit: { stage, expected, receipt in
                XCTAssertEqual(expected, self.local)
                XCTAssertEqual(receipt, .init(ownerID: "owner", generation: 4))
                XCTAssertEqual(self.puts, 1, "No local commit before upload")
                if commitError { throw Injected.commit }
                self.commits += 1
                self.local = .init(recipes: stage.recipes, shopping: stage.shopping, metadata: stage.metadata)
            })
        }
        func edit() {
            var metadata = local.metadata; metadata.recipeStamps["one"] = 9
            local = .init(recipes: [RecipeCard(id: "one", title: "New edit")], shopping: [], metadata: metadata)
        }
        func clean() { adapter = nil; beforeResponse = nil; try? FileManager.default.removeItem(at: root) }
    }
    func testSuccessfulCycleCommitsOnlyAfterUploadAndOriginalGenerationProof() async throws {
        let f = try Fixture(); defer { f.clean() }
        let result = try await f.run()
        XCTAssertEqual(result, 1); XCTAssertEqual(f.commits, 1)
    }
    func testLocalEditDuringPullOrPushRemainsPendingWithoutCommit() async throws {
        for duringPull in [true, false] {
            let f = try Fixture(); defer { f.clean() }
            f.beforeResponse = { request in
                if (request.url!.lastPathComponent == "account_data_snapshot") == duringPull { f.edit() }
            }
            do { _ = try await f.run(); XCTFail("Changed revision committed") }
            catch FoodJournalGenerationSync.Failure.localRevisionChanged {} catch { XCTFail("Unexpected \(error)") }
            XCTAssertEqual(f.puts, duringPull ? 0 : 1); XCTAssertEqual(f.commits, 0)
            XCTAssertEqual(f.local.recipes.first?.title, "New edit")
            XCTAssertEqual(f.local.metadata.recipeStamps["one"], 9)
        }
    }
    func testUploadAndCommitFailureKeepLocalStateAndRequireNewSnapshot() async throws {
        for commitFailure in [false, true] {
            let f = try Fixture(); defer { f.clean() }
            let original = f.local
            f.beforeResponse = { request in
                if request.url!.lastPathComponent != "account_data_snapshot", !commitFailure { throw Injected.network }
            }
            do { _ = try await f.run(commitError: commitFailure); XCTFail("Injected failure accepted") }
            catch ResetRPCError.outcomeUnverified(let diagnostic) {
                XCTAssertFalse(commitFailure, "Only the transport failure is wrapped as unverified")
                XCTAssertEqual(diagnostic, Net.friendly(Injected.network), "Preserve the exact injected transport diagnostic")
                XCTAssertEqual(f.puts, 1, "Injected failure must occur during upload")
            } catch Injected.commit {
                XCTAssertTrue(commitFailure, "Only the durable commit injection escapes unchanged")
            } catch { XCTFail("Unexpected \(error)") }
            XCTAssertEqual(f.local, original); XCTAssertEqual(f.commits, 0)
            do { try await f.adapter.push([], session: f.current); XCTFail("No reusable pull capture") }
            catch FoodJournalGenerationSync.Failure.missingPull {} catch { XCTFail("Unexpected \(error)") }
        }
    }
    func testSameOwnerTokenChangeBeforePublicationCannotCommit() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.beforeResponse = { request in
            if request.url!.lastPathComponent != "account_data_snapshot" { f.current.accessToken = "replacement" }
        }
        do { _ = try await f.run(); XCTFail("Replacement session committed") }
        catch GenerationFencedSync.Error.ownerChanged {} catch FoodJournalGenerationSync.Failure.identityChanged {}
        catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(f.commits, 0)
    }
    func testExistingPullCaptureAndConcurrentCycleRefuseWithoutConsumingOwner() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try await f.adapter.pull(session: f.current)
        do { _ = try await f.run(); XCTFail("Pending pull capture stolen") }
        catch FoodJournalGenerationSync.Failure.operationInProgress {} catch { XCTFail("Unexpected \(error)") }
        try await f.adapter.push([], session: f.current)
        f.beforeResponse = { request in
            if request.url!.lastPathComponent == "account_data_snapshot" {
                do { _ = try await f.adapter.pull(session: f.current); XCTFail("Concurrent pull admitted") }
                catch FoodJournalGenerationSync.Failure.operationInProgress {} catch { XCTFail("Unexpected \(error)") }
            }
        }
        _ = try await f.run()
        XCTAssertEqual(f.commits, 1)
    }
    func testCancellationIgnoringTransportCannotPublishAfterPullOrPush() async throws {
        for duringPull in [true, false] {
            let f = try Fixture(); defer { f.clean() }
            f.beforeResponse = { request in
                if (request.url!.lastPathComponent == "account_data_snapshot") == duringPull {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            let task = Task { try await f.run() }
            do { _ = try await task.value; XCTFail("Cancellation ignored at publication") }
            catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
            XCTAssertEqual(f.commits, 0)
            XCTAssertEqual(f.puts, duringPull ? 0 : 1)
        }
    }

}
