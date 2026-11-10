import XCTest
@testable import Ate

@MainActor
final class CookPlanFakeNotificationClient: CookPlanNotificationClient {
    var permitted = true
    var ids: Set<String> = ["ate.timer.keep"]
    var adds: [Date] = []
    var suspendAdd = false
    var addStarted = false
    var onAdd: (() -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
    func allowed(request: Bool) async -> Bool { permitted }
    func pendingIDs() async -> Set<String> { ids }
    func add(_ plan: CookPlan, title: String) async throws {
        addStarted = true
        if suspendAdd { await withCheckedContinuation { continuation = $0; onAdd?() } }
        ids.insert(plan.reminderID); adds.append(plan.scheduledAt)
    }
    func remove(_ ids: [String]) async { self.ids.subtract(ids) }
    func removeAllDelivered() async {}
}

@MainActor
final class CookPlanNotificationTests: XCTestCase {
    private func plan(offset: Double = 3600) -> CookPlan {
        CookPlan(recipeID: "r1", scheduledAt: Date().addingTimeInterval(offset),
                 timeZoneID: "Africa/Johannesburg", reminderRequested: true)
    }
    func testSaveChangeCancelWaitsForRemovalAndPreservesTimerIDs() async throws {
        let client = CookPlanFakeNotificationClient()
        let adapter = CookPlanNotifications(client: client)
        let first = plan(), changed = plan(offset: 7200)
        let recipes = [RecipeCard(id: "r1", title: "Soup")]
        try await adapter.reconcile(plans: [first], recipes: recipes)
        try await adapter.reconcile(plans: [changed], recipes: recipes)
        XCTAssertEqual(client.ids, ["ate.timer.keep", first.reminderID])
        XCTAssertEqual(client.adds, [first.scheduledAt, changed.scheduledAt])
        try await adapter.cancel(recipeID: "r1")
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }
    func testClearWhileAddSuspendedInvalidatesAddAndWaitsForCleanup() async throws {
        let client = CookPlanFakeNotificationClient(); client.suspendAdd = true
        let adapter = CookPlanNotifications(client: client), p = plan()
        let started = expectation(description: "OS add suspended")
        client.onAdd = { started.fulfill() }
        let adding = Task { try await adapter.reconcile(plans: [p], recipes: [RecipeCard(id: "r1", title: "Soup")]) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(client.addStarted)
        var cleanupReturned = false
        let clearing = Task { try await adapter.cancelAll(); cleanupReturned = true }
        await Task.yield()
        XCTAssertFalse(cleanupReturned, "Cleanup must await the suspended OS add")
        client.continuation?.resume()
        try await adding.value; try await clearing.value
        XCTAssertTrue(cleanupReturned)
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }
    func testCancelWhileAddSuspendedCannotLeaveObsoleteReminder() async throws {
        let client = CookPlanFakeNotificationClient(); client.suspendAdd = true
        let adapter = CookPlanNotifications(client: client), p = plan()
        let started = expectation(description: "OS add suspended")
        client.onAdd = { started.fulfill() }
        let adding = Task { try await adapter.reconcile(plans: [p], recipes: [RecipeCard(id: "r1", title: "Soup")]) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(client.addStarted)
        let cancel = Task { try await adapter.cancel(recipeID: "r1") }
        await Task.yield(); client.continuation?.resume()
        try await adding.value; try await cancel.value
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }
}
