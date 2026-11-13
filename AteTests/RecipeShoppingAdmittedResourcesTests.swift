import XCTest
import SwiftData
@testable import Ate

@MainActor
final class RecipeShoppingAdmittedResourcesTests: XCTestCase {
    private enum Injected: Error { case openFailed }
    func testNoStoreOpenBeforeAdmissionAndNoFallbackAfterOpenFailure() async throws {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let dir = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
            userID: "owner", email: "fixture@example.test")
        let gate = try AccountWriterGate(directory: dir, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) { try AccountGenerationReceiptStore(directory: dir).save(.init(ownerID: "owner", generation: 0)) }
        let owner = try RecipeShoppingSyncOwner(controlDirectory: dir,
            rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
                return (Data(#"{"generation":0,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!)
            }), session: session, currentSession: { session })
        var opens = 0
        func attempt(_ candidate: AuthSession) throws {
            _ = try RecipeShoppingAdmittedResources.open(owner: owner, session: candidate, defaults: .standard,
                commitDirectory: dir, validateWriterRouting: {}, makeContainer: { opens += 1; throw Injected.openFailed })
        }
        XCTAssertThrowsError(try attempt(session)); XCTAssertEqual(opens, 0)
        _ = try await owner.pull(session: session); try await owner.push([], session: session)
        var different = session; different.accessToken = "replacement"
        XCTAssertThrowsError(try attempt(different)); XCTAssertEqual(opens, 0)
        // Session refusal revokes capability, so re-admit before testing strict open.
        _ = try await owner.pull(session: session); try await owner.push([], session: session)
        XCTAssertThrowsError(try attempt(session)) { error in
            guard case Injected.openFailed = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(opens, 1, "no fallback/retry after throwing strict open")
    }
    func testRawUndecodableAndUnknownOwnershipNeverBecomeEmptyAdoption() throws {
        let raw = ArchiveRecipeShoppingImage(recipes: [ArchiveRawRecipeImage(id: "bad", createdAt: 1, position: 0,
            json: Data("not-json".utf8))], shopping: [])
        for owner in [String?.none, .some("foreign"), .some("owner")] {
            var metadata = RecipeShoppingSyncStage.Metadata(); metadata.userID = owner
            let inventory = RecipeShoppingRawInventory(image: raw, metadataBytes: try JSONEncoder().encode(metadata))
            XCTAssertThrowsError(try inventory.validate(ownerID: "owner"))
            XCTAssertEqual(inventory.image, raw)
        }
        let empty = RecipeShoppingRawInventory(image: .init(recipes: [], shopping: []), metadataBytes: nil)
        XCTAssertThrowsError(try empty.validate(ownerID: "owner"), "empty is not permission to stamp a receipt")
    }
}

extension RecipeShoppingAdmittedResourcesTests {
    func testAdmittedStrictOpenReplaysPendingBeforeRawInventoryAndBinding() async throws {
        let suite = "Resources-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(RecipeShoppingSyncCommitJournal.directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let config = ModelConfiguration(url: root.appendingPathComponent("recipes.store"))
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
            userID: "owner", email: "fixture@example.test")
        let receipt = AccountGenerationPolicy.Receipt(ownerID: "owner", generation: 0)
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) { try AccountGenerationReceiptStore(directory: root).save(receipt) }
        let owner = try RecipeShoppingSyncOwner(controlDirectory: root,
            rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
                (Data(#"{"generation":0,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!)
            }), session: session, currentSession: { session })
        _ = try await owner.pull(session: session); try await owner.push([], session: session)
        var metadata = RecipeShoppingSyncStage.Metadata(); metadata.userID = "owner"; metadata.recipeStamps = ["r": 1]
        let stage = try RecipeShoppingSyncStage.prepare(recipes: [RecipeCard(id: "r", title: "Replay")], shopping: [],
            metadata: metadata, remote: [], ownerID: "owner")
        do {
            let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: config)
            let journal = try RecipeShoppingSyncCommitJournal(directory: directory, gate: gate, writerLease: lease,
                container: container, defaults: defaults, authorize: { candidate in XCTAssertEqual(candidate, receipt) },
                validateWriterRouting: {}, checkpoint: { if $0 == .afterStoreSave { throw Injected.openFailed } })
            XCTAssertThrowsError(try journal.commit(stage, receipt: receipt))
        }
        let resources = try RecipeShoppingAdmittedResources.open(owner: owner, session: session,
            configuration: config, defaults: defaults, commitDirectory: directory, validateWriterRouting: {})
        XCTAssertFalse(resources.container.mainContext.autosaveEnabled)
        XCTAssertEqual(resources.rawInventory.image.recipes.map(\.id), ["r"])
        XCTAssertEqual(try resources.rawInventory.validate(ownerID: "owner"), stage.metadata)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending-v1.json").path))
        XCTAssertTrue(resources.binding.owner === owner)
    }
}
