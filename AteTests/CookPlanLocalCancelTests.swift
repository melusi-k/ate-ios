import XCTest
@testable import Ate

@MainActor
final class CookPlanLocalCancelTests: XCTestCase {
    private func plan() -> CookPlan {
        CookPlan(recipeID: "r1", scheduledAt: Date().addingTimeInterval(3600),
                 timeZoneID: "Africa/Johannesburg", reminderRequested: true)
    }

    func testLocalCancelCommitsBeforeSuspendedOSReadAndPreservesTimerIDs() async throws {
        let suite = "cookplan.local-cancel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults), saved = plan()
        try store.save(saved)
        let client = CookPlanFakeNotificationClient(); client.suspendPending = true
        client.ids.insert(saved.reminderID)
        let suspended = expectation(description: "OS verification suspended after local removal")
        client.onPending = { suspended.fulfill() }
        let adapter = CookPlanNotifications(client: client)
        var reported = false
        let cleanup = try adapter.cancelLocally(recipeID: saved.recipeID, store: store) { reported = true }
        XCTAssertTrue(try store.plans().isEmpty, "Caller can dismiss with verified local removal")
        await fulfillment(of: [suspended], timeout: 2)
        XCTAssertFalse(reported)
        client.suspendPending = false; client.pendingContinuation?.resume()
        await cleanup.value
        XCTAssertFalse(reported)
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
        XCTAssertEqual(client.permissionReads, 0)
    }

    func testRetainedOSReminderIsReportedWithoutResurrectingRemovedPlan() async throws {
        let suite = "cookplan.local-cancel-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults), saved = plan()
        try store.save(saved)
        let client = CookPlanFakeNotificationClient(); client.refuseRemoval = true
        client.ids.insert(saved.reminderID)
        let adapter = CookPlanNotifications(client: client)
        var reported = false
        let cleanup = try adapter.cancelLocally(recipeID: saved.recipeID, store: store) { reported = true }
        await cleanup.value
        XCTAssertTrue(reported)
        XCTAssertTrue(try store.plans().isEmpty)
        XCTAssertTrue(client.ids.contains(saved.reminderID))
        XCTAssertTrue(client.ids.contains("ate.timer.keep"))
    }

    func testUnreadableLocalPlanDoesNotQueueOSRemoval() async throws {
        let suite = "cookplan.local-cancel-corrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("not json".utf8)
        defaults.set(corrupt, forKey: CookPlanStore.storageKey)
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanFakeNotificationClient(), saved = plan()
        client.ids.insert(saved.reminderID)
        let adapter = CookPlanNotifications(client: client)
        XCTAssertThrowsError(try adapter.cancelLocally(recipeID: saved.recipeID, store: store) { XCTFail("No cleanup should be queued") })
        XCTAssertEqual(defaults.data(forKey: CookPlanStore.storageKey), corrupt)
        XCTAssertTrue(client.ids.contains(saved.reminderID))
    }

    func testCancelRegisteredBeforeLaterReenableCannotRemoveNewReminder() async throws {
        let suite = "cookplan.local-cancel-reenable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults), saved = plan()
        try store.save(saved)
        let client = CookPlanFakeNotificationClient(); client.suspendAdd = true
        let adapter = CookPlanNotifications(client: client)
        let recipes = [RecipeCard(id: saved.recipeID, title: "Soup")]
        let started = expectation(description: "old add suspended")
        client.onAdd = { started.fulfill() }
        let oldAdd = Task { try await adapter.reconcile(plans: [saved], recipes: recipes) }
        await fulfillment(of: [started], timeout: 2)
        let cleanup = try adapter.cancelLocally(recipeID: saved.recipeID, store: store) { XCTFail("Removal failed") }
        XCTAssertTrue(try store.plans().isEmpty)
        try store.save(saved)
        client.suspendAdd = false
        let reenable = Task { try await adapter.reconcile(plans: [saved], recipes: recipes) }
        await Task.yield(); client.continuation?.resume()
        try await oldAdd.value
        await cleanup.value
        try await reenable.value
        XCTAssertEqual(try store.plans(), [saved])
        XCTAssertEqual(client.ids, ["ate.timer.keep", saved.reminderID])
    }
}
