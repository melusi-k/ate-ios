import XCTest
import SwiftData
@testable import Ate

/// Native UNRUN. Explicit admitted binding only, not ordinary launch qualification.
@MainActor
final class RecipeShoppingAuthorityBindingTests: XCTestCase {
    private enum Injected: Error { case failure }
    func testAppStoreLocalWritesAndTombstonesUseDurableAuthorityAndFailureRetainsRedo() async throws {
        let suite = "AuthorityBinding-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let journalDir = root.appendingPathComponent(RecipeShoppingSyncCommitJournal.directoryName)
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: false)
        let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("recipe.store")))
        container.mainContext.autosaveEnabled = false
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
            userID: "owner", email: "fixture@example.test")
        let receipt = AccountGenerationPolicy.Receipt(ownerID: session.userID, generation: 0)
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) { try AccountGenerationReceiptStore(directory: root).save(receipt) }
        let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
            guard request.url?.lastPathComponent == "account_data_snapshot" else { throw Injected.failure }
            return (Data(#"{"generation":0,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        })
        let owner = try RecipeShoppingSyncOwner(controlDirectory: root, rpc: rpc, session: session, currentSession: { session })
        _ = try await owner.pull(session: session)
        try await owner.push([], session: session)
        var fail = false
        let journal = try RecipeShoppingSyncCommitJournal(directory: journalDir, gate: gate, writerLease: lease,
            container: container, defaults: defaults, authorize: { candidate in
                XCTAssertEqual(candidate, receipt); try owner.withAdmittedWriterEffect {}
            }, validateWriterRouting: {}, checkpoint: { boundary in
                if fail && boundary == .afterIntentWrite { throw Injected.failure }
            })
        _ = try journal.recoverAndProject()
        var metadata = RecipeShoppingSyncStage.Metadata(); metadata.userID = session.userID
        defaults.set(try JSONEncoder().encode(metadata), forKey: "ate.sync.v1")
        // Existing recipes that the legacy loader would normalize/dedupe, plus a
        // shopping sibling with exact bytes/stamp. Authority init must not repair
        // one inventory before fetching the other or commit a default-empty list.
        let recipeA = RecipeCard(id: "existing-a", title: "Same title")
        let recipeB = RecipeCard(id: "existing-b", title: "Same title")
        let existingShopping = ShoppingItem(id: "existing-shopping", name: "Keep exact", quantity: 2, unit: "g")
        let encoder = JSONEncoder()
        let shoppingBytes = try encoder.encode(existingShopping)
        let seed = ModelContext(container); seed.autosaveEnabled = false
        seed.insert(RecipeEntity(id: recipeA.id, createdAt: recipeA.createdAt, position: 0, json: try encoder.encode(recipeA)))
        seed.insert(RecipeEntity(id: recipeB.id, createdAt: recipeB.createdAt, position: 1, json: try encoder.encode(recipeB)))
        seed.insert(ShoppingEntity(id: existingShopping.id, position: 0, json: shoppingBytes))
        try seed.save()
        metadata.recipeStamps = [recipeA.id: 1, recipeB.id: 2]
        metadata.shopStamps = [existingShopping.id: 3]
        defaults.set(try encoder.encode(metadata), forKey: "ate.sync.v1")
        let rawBeforeInit = try UnifiedArchiveImportBinding.snapshotRecipeShopping(container)
        let binding = RecipeShoppingAuthorityBinding(owner: owner, receipt: receipt, journal: journal, defaults: defaults, session: session)
        let legacyCook = Data(#"{"recipeID":"existing-a","stepIndex":0,"factor":1,"checked":[]}"#.utf8)
        defaults.set(legacyCook, forKey: "ate.cookSession.v1")
        let store = AppStore(context: container.mainContext, backend: MockBackend(), recipeShoppingAuthority: binding,
            injectedAuth: MockAuth())
        // Successful inventory construction uses authority defaults for gated identity.
        XCTAssertNotEqual(defaults.data(forKey: "ate.cookSession.v1"), legacyCook)
        XCTAssertEqual(try UnifiedArchiveImportBinding.snapshotRecipeShopping(container), rawBeforeInit)
        XCTAssertEqual(store.shopping.map(\.id), [existingShopping.id])
        XCTAssertEqual(try UnifiedArchiveImportBinding.snapshotRecipeShopping(container).shopping.first?.json, shoppingBytes)
        let afterInitMeta = try JSONDecoder().decode(RecipeShoppingSyncStage.Metadata.self,
            from: XCTUnwrap(defaults.data(forKey: "ate.sync.v1")))
        XCTAssertEqual(afterInitMeta.shopStamps[existingShopping.id], 3)
        store.add(RecipeCard(id: "first", title: "First"))
        store.addManual("Keep shopping")
        let afterAdd = try UnifiedArchiveImportBinding.snapshotRecipeShopping(container)
        XCTAssertEqual(Set(afterAdd.recipes.map(\.id)), ["first", recipeA.id, recipeB.id])
        XCTAssertEqual(afterAdd.shopping.count, 2)
        store.shopping = []; store.persistShopping()
        let projected = try XCTUnwrap(defaults.data(forKey: "ate.sync.v1"))
        let savedMeta = try JSONDecoder().decode(RecipeShoppingSyncStage.Metadata.self, from: projected)
        XCTAssertEqual(savedMeta.shopTombs.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalDir.appendingPathComponent("metadata-v1.json").path))
        // Corrupt sibling inventory: no legacy cook identity write, no current
        // replacement, no widget publication/relay installation from empty arrays.
        let badContext = ModelContext(container); badContext.autosaveEnabled = false
        badContext.insert(RecipeEntity(id: "unreadable", createdAt: 1, position: 99, json: Data("bad-json".utf8)))
        try badContext.save()
        defaults.set(legacyCook, forKey: "ate.cookSession.v1")
        let priorCurrent = AppStore.current
        let publications = WidgetBridge.publicationRequests, relays = WidgetBridge.relayInstallRequests
        let refused = AppStore(context: container.mainContext, backend: MockBackend(), recipeShoppingAuthority: binding,
            injectedAuth: MockAuth())
        refused.loadPersistedCookSession(defaults: defaults)
        WidgetBridge.publish(refused); WidgetBridge.publishNow(refused); WidgetBridge.installRelays(refused)
        XCTAssertTrue(AppStore.current === priorCurrent)
        XCTAssertEqual(WidgetBridge.publicationRequests, publications)
        XCTAssertEqual(WidgetBridge.relayInstallRequests, relays)
        XCTAssertEqual(defaults.data(forKey: "ate.cookSession.v1"), legacyCook)
        XCTAssertFalse(refused.permitsExternalPublication)
        let badRows = try badContext.fetch(FetchDescriptor<RecipeEntity>()).filter { $0.id == "unreadable" }
        for row in badRows { badContext.delete(row) }; try badContext.save()
        owner.abandonCycle()
        store.loadPersistedCookSession(defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: "ate.cookSession.v1"), legacyCook, "refused authority cannot assign identity")
        _ = try await owner.pull(session: session); try await owner.push([], session: session)
        let before = store.recipes
        fail = true
        store.add(RecipeCard(id: "late", title: "Retained redo"))
        XCTAssertEqual(store.recipes, before, "failed ordinary effect does not claim publication")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalDir.appendingPathComponent("pending-v1.json").path))
        XCTAssertEqual(Set(try UnifiedArchiveImportBinding.snapshotRecipeShopping(container).recipes.map(\.id)), ["first", recipeA.id, recipeB.id])
        // Refusal revokes owner capability. Fresh admission is required before replay.
        owner.abandonCycle()
        _ = try await owner.pull(session: session); try await owner.push([], session: session)
        fail = false
        XCTAssertTrue(try journal.recoverAndProject())
        let recovered = try UnifiedArchiveImportBinding.snapshotRecipeShopping(container)
        XCTAssertEqual(Set(recovered.recipes.map(\.id)), ["first", "late", recipeA.id, recipeB.id])
    }
}
