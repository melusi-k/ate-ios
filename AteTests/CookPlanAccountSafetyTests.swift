import XCTest
@testable import Ate

@MainActor
final class CookPlanAccountSafetyTests: XCTestCase {
    enum Injected: Error { case clear }
    private func store() -> AppStore {
        AppStore(context: nil, backend: MockBackend(),
            cookPlanNotifications: CookPlanNotifications(client: CookPlanFakeNotificationClient()),
            clearCookPlans: { throw Injected.clear }, authOverride: MockAuth(), syncOverride: MockSync())
    }
    private var accountB: AuthSession {
        AuthSession(accessToken: "mock", refreshToken: "mock", expiresAt: Date().timeIntervalSince1970 + 3600,
            userID: "account-b", email: "b@example.com")
    }
    func testSuccessfulRemotePullThenPlanClearFailureSignsOutAndPreservesPreviousData() async throws {
        let oldSync = UserDefaults.standard.data(forKey: "ate.sync.v1")
        let oldSession = Keychain.load(account: "session")
        let oldPlans = UserDefaults.standard.data(forKey: CookPlanStore.storageKey)
        let retainedPlan = Data("retained account-a recovery bytes".utf8)
        UserDefaults.standard.set(retainedPlan, forKey: CookPlanStore.storageKey)
        defer {
            UserDefaults.standard.set(oldPlans, forKey: CookPlanStore.storageKey)
            UserDefaults.standard.set(oldSync, forKey: "ate.sync.v1")
            Keychain.save(oldSession, account: "session")
        }
        UserDefaults.standard.set(Data("{\"userID\":\"account-a\",\"recipeStamps\":{},\"recipeTombs\":{},\"shopStamps\":{},\"shopTombs\":{}}".utf8), forKey: "ate.sync.v1")
        let store = store()
        store.recipes = [RecipeCard(id: "a-recipe", title: "A's soup")]
        store.shopping = [ShoppingItem(id: "a-shopping", name: "Beans", quantity: 1, unit: "bag")]
        store.session = accountB
        await store.syncNow()
        XCTAssertNil(store.session, "B must not remain active over A's retained local data")
        XCTAssertEqual(store.recipes.map(\.id), ["a-recipe"])
        XCTAssertEqual(store.shopping.map(\.id), ["a-shopping"])
        XCTAssertEqual(UserDefaults.standard.data(forKey: CookPlanStore.storageKey), retainedPlan)
        guard case .failed = store.syncState else { return XCTFail("Switch failure must stay explicit") }
    }
    func testSignOutRemovalFailureDoesNotClaimLocalRemoval() async {
        let oldSession = Keychain.load(account: "session")
        defer { Keychain.save(oldSession, account: "session") }
        let store = store(); store.session = accountB
        store.recipes = [RecipeCard(id: "kept", title: "Retained for recovery")]
        await store.signOut(removeLocalData: true)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.recipes.map(\.id), ["kept"])
        XCTAssertTrue(store.toast?.message.contains("cleanup failed") == true)
    }
    func testServerDeleteThenLocalRemovalFailureReturnsPartialError() async {
        let oldSession = Keychain.load(account: "session")
        defer { Keychain.save(oldSession, account: "session") }
        let store = store(); store.session = accountB
        store.recipes = [RecipeCard(id: "kept", title: "Retained for recovery")]
        let error = await store.deleteAccount()
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.message.contains("server account was deleted") == true)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.recipes.map(\.id), ["kept"])
    }
}
