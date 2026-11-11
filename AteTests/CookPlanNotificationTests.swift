import XCTest
@testable import Ate

@MainActor
final class CookPlanFakeNotificationClient: CookPlanNotificationClient {
    var permitted = true
    var permissionReads = 0
    var refuseRemoval = false
    var suspendPending = false
    var onPending: (() -> Void)?
    var pendingContinuation: CheckedContinuation<Void, Never>?
    var ids: Set<String> = ["ate.timer.keep"]
    var adds: [Date] = []
    var suspendAdd = false
    var addStarted = false
    var onAdd: (() -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
    func allowed(request: Bool) async -> Bool { permissionReads += 1; return permitted }
    func pendingIDs() async -> Set<String> {
        if suspendPending { await withCheckedContinuation { pendingContinuation = $0; onPending?() } }
        return ids
    }
    func add(_ plan: CookPlan, title: String) async throws {
        addStarted = true
        if suspendAdd { await withCheckedContinuation { continuation = $0; onAdd?() } }
        ids.insert(plan.reminderID); adds.append(plan.scheduledAt)
    }
    func remove(_ ids: [String]) async { if !refuseRemoval { self.ids.subtract(ids) } }
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
    func testNoReminderSaveReturnsCommittedPlanBeforeSuspendedOSReadAndNeverReadsPermission() async throws {
        let suite = "cookplan.local-save.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanFakeNotificationClient(); client.suspendPending = true
        let adapter = CookPlanNotifications(client: client)
        let off = CookPlan(recipeID: "r1", scheduledAt: Date().addingTimeInterval(3600),
                           timeZoneID: "Africa/Johannesburg", reminderRequested: false)
        let suspended = expectation(description: "OS read remains suspended after local save")
        client.onPending = { suspended.fulfill() }
        var failed = false
        let cleanup = try adapter.saveWithoutReminder(off, store: store) { failed = true }
        // Synchronous return lets the real sheet dismiss before ANY notification await.
        XCTAssertEqual(try store.plans(), [off])
        XCTAssertEqual(client.permissionReads, 0)
        await fulfillment(of: [suspended], timeout: 2)
        XCTAssertFalse(failed)
        client.suspendPending = false; client.pendingContinuation?.resume()
        await cleanup.value
        XCTAssertEqual(client.permissionReads, 0)
        XCTAssertFalse(failed)
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }

    func testNoReminderSaveReportsRetainedReminderWithoutLosingLocalPlan() async throws {
        let suite = "cookplan.failed-removal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanFakeNotificationClient(); client.refuseRemoval = true
        let on = plan()
        client.ids.insert(on.reminderID)
        let off = CookPlan(recipeID: on.recipeID, scheduledAt: on.scheduledAt,
                           timeZoneID: on.timeZoneID, reminderRequested: false)
        var reported = false
        let adapter = CookPlanNotifications(client: client)
        let cleanup = try adapter.saveWithoutReminder(off, store: store) { reported = true }
        XCTAssertEqual(try store.plans(), [off])
        await cleanup.value
        XCTAssertTrue(reported, "Retained OS reminder must be reported, not a false success")
        XCTAssertTrue(client.ids.contains(on.reminderID))
    }

    func testNoReminderCleanupStaysOrderedBeforeLaterReenable() async throws {
        let suite = "cookplan.reenable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanFakeNotificationClient(); client.suspendAdd = true
        let adapter = CookPlanNotifications(client: client), on = plan()
        let started = expectation(description: "old add suspended")
        client.onAdd = { started.fulfill() }
        let recipes = [RecipeCard(id: on.recipeID, title: "Soup")]
        let oldAdd = Task { try await adapter.reconcile(plans: [on], recipes: recipes) }
        await fulfillment(of: [started], timeout: 2)
        let off = CookPlan(recipeID: on.recipeID, scheduledAt: on.scheduledAt,
                           timeZoneID: on.timeZoneID, reminderRequested: false)
        let cleanup = try adapter.saveWithoutReminder(off, store: store) { XCTFail("Removal failed") }
        client.suspendAdd = false
        let reenable = Task { try await adapter.reconcile(plans: [on], recipes: recipes) }
        await Task.yield()
        client.continuation?.resume()
        try await oldAdd.value
        await cleanup.value
        try await reenable.value
        XCTAssertEqual(client.ids, ["ate.timer.keep", on.reminderID], "Old OFF cleanup cannot erase newer ON intent")
    }

    func testFailedLocalSaveCannotReturnDismissalSuccessOrQueueRemoval() throws {
        let suite = "cookplan.local-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanFakeNotificationClient(), adapter = CookPlanNotifications(client: client)
        let expired = CookPlan(recipeID: "r1", scheduledAt: Date().addingTimeInterval(-60),
                              timeZoneID: "Africa/Johannesburg", reminderRequested: false)
        XCTAssertThrowsError(try adapter.saveWithoutReminder(expired, store: store) { XCTFail("No cleanup should start") })
        XCTAssertTrue(try store.plans().isEmpty)
        XCTAssertEqual(client.permissionReads, 0)
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }

}
