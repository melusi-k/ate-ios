import XCTest
import SwiftData
@testable import Ate

/// Native UNRUN. Pre-admission observer is not a mounted production graph.
@MainActor
final class RecipeShoppingReadOnlyLoadTests: XCTestCase {
    func testReadOnlyLoadPreservesRawDuplicatesAndMetadataAndRefusesOrdinaryMutation() async throws {
        let suite = "readOnly-\(UUID().uuidString)"
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(url: root.appendingPathComponent("recipe.store"))
        let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: configuration)
        let seed = ModelContext(container); seed.autosaveEnabled = false
        let first = RecipeCard(id: "first", title: "Duplicate"), second = RecipeCard(id: "second", title: "Duplicate")
        seed.insert(RecipeEntity(id: first.id, createdAt: first.createdAt, position: 0, json: try JSONEncoder().encode(first)))
        seed.insert(RecipeEntity(id: second.id, createdAt: second.createdAt, position: 1, json: try JSONEncoder().encode(second)))
        seed.insert(RecipeEntity(id: "unreadable", createdAt: 1, position: 2, json: Data("not-json".utf8)))
        try seed.save()
        let before = try UnifiedArchiveImportBinding.snapshotRecipeShopping(container)
        let metadata = UserDefaults.standard.data(forKey: "ate.sync.v1")
        let store = AppStore(context: container.mainContext, backend: MockBackend(),
            recipeShoppingLoadPolicy: .readOnlyPendingAdmission, injectedAuth: MockAuth(), injectedSync: MockSync())
        XCTAssertFalse(container.mainContext.autosaveEnabled)
        XCTAssertEqual(Set(store.recipes.map(\.id)), ["first", "second"])
        store.add(RecipeCard(id: "blocked", title: "No write"))
        store.addManual("No write")
        store.persistRecipes(); store.persistShopping()
        await store.syncNow()
        XCTAssertEqual(try UnifiedArchiveImportBinding.snapshotRecipeShopping(container), before)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "ate.sync.v1"), metadata)
        XCTAssertFalse(store.recipes.contains { $0.id == "blocked" })
        guard case .failed = store.syncState else { return XCTFail("pending admission reported synced") }
        store.recovery = RecoveryInfo(backupPath: nil, inMemory: false, error: "fixture")
        await store.completeRecovery()
        XCTAssertEqual(store.recovery?.restoredFromSync, false)
        XCTAssertNil(store.recovery?.exportURL)
    }
    func testObserverCollaboratorsAndLegacyCookEntryPreserveSeededPersonalEvidence() throws {
        let standard = UserDefaults.standard
        let keys = ["ate.cookSession.v1", "ate.cooking.history.v1", "ate.draft.pending.v1", "ate.draft.card.v1", "insights.lifecycle.v1", "insights.lifecycle.v1.account.fixture"]
        let prior = Dictionary(uniqueKeysWithValues: keys.map { ($0, standard.object(forKey: $0)) })
        let timerPrior = SharedContainer.defaults.object(forKey: TimerSnapshot.key)
        defer {
            for key in keys { standard.set(prior[key] ?? nil, forKey: key) }
            SharedContainer.defaults.set(timerPrior, forKey: TimerSnapshot.key)
        }
        let legacy = Data(#"{"recipeID":"old","stepIndex":0,"factor":1,"checked":[]}"#.utf8)
        standard.set(legacy, forKey: "ate.cookSession.v1")
        for key in keys where key != "ate.cookSession.v1" { standard.set(Data("retained-\(key)".utf8), forKey: key) }
        let timerBytes = try JSONEncoder().encode([TimerSnapshot(recipeID: "keep", recipeTitle: "Keep", stepIndex: 0,
            stepCount: 1, stepText: "Keep", total: 60, endDate: nil, pausedRemaining: 30)])
        SharedContainer.defaults.set(timerBytes, forKey: TimerSnapshot.key)
        let seeded = Dictionary(uniqueKeysWithValues: keys.map { ($0, standard.data(forKey: $0)) })
        let store = AppStore(context: nil, backend: MockBackend(), recipeShoppingLoadPolicy: .readOnlyPendingAdmission,
            launchArguments: ["-uiTesting", "-qaResetCookingHistory", "-qaResetInsightLifecycle", "-qaResetDraft"],
            injectedAuth: MockAuth(), injectedSync: MockSync())
        store.loadPersistedCookSession(defaults: standard)
        store.timers.startQuick(); store.timers.reloadFromShared()
        _ = store.drafts.clear(); _ = store.drafts.begin(mode: "Prompt", text: "No write")
        for key in keys { XCTAssertEqual(standard.data(forKey: key), seeded[key] ?? nil) }
        XCTAssertEqual(SharedContainer.defaults.data(forKey: TimerSnapshot.key), timerBytes)
        XCTAssertEqual(store.timers.snapshots.count, 1)
    }

}
