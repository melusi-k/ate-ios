import XCTest
@testable import Ate

@MainActor
final class CookPlanCancelFakeClient: CookPlanNotificationClient {
    var permitted = true
    var permissionReads = 0
    var refuseRemoval = false
    var ids: Set<String> = ["ate.timer.keep"]
    var adds: [Date] = []
    func allowed(request: Bool) async -> Bool { permissionReads += 1; return permitted }
    func pendingIDs() async -> Set<String> { ids }
    func add(_ plan: CookPlan, title: String) async throws {
        ids.insert(plan.reminderID); adds.append(plan.scheduledAt)
    }
    var suspendRemoval = false
    var removalCalls = 0
    var onRemoval: (() -> Void)?
    var removalContinuation: CheckedContinuation<Void, Never>?
    func remove(_ ids: [String]) async {
        removalCalls += 1
        if suspendRemoval { await withCheckedContinuation { removalContinuation = $0; onRemoval?() } }
        if !refuseRemoval { self.ids.subtract(ids) }
    }
    func removeAllDelivered() async {}
}

@MainActor
final class CookPlanCancelBackgroundTests: XCTestCase {
    private func plan() -> CookPlan {
        CookPlan(recipeID: "r1", scheduledAt: Date().addingTimeInterval(3600),
                 timeZoneID: "Africa/Johannesburg", reminderRequested: true)
    }
    func testCancelInBackgroundKeepsLocalCancelImmediateUnderSuspendedRemoval() async throws {
        let suite = "cookplan.cancel-background.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanCancelFakeClient(); client.suspendRemoval = true
        let adapter = CookPlanNotifications(client: client), on = plan()
        try store.save(on); client.ids.insert(on.reminderID)
        let entered = CookPlanCancelEntryGate()
        client.onRemoval = { entered.signalEntry() }
        var dismissed = false, failed = false
        let cleanup = try adapter.cancelFromSheet(recipeID: on.recipeID, store: store,
            onCommitted: { dismissed = true }, onRemovalFailure: { failed = true })
        XCTAssertTrue(dismissed, "The real sheet success action runs synchronously")
        XCTAssertTrue(try store.plans().isEmpty)
        await entered.waitForEntry()
        XCTAssertTrue(dismissed)
        XCTAssertFalse(failed)
        XCTAssertTrue(client.ids.contains(on.reminderID), "OS removal is still suspended")
        client.suspendRemoval = false; client.removalContinuation?.resume()
        await cleanup.value
        XCTAssertFalse(failed)
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }

    func testCancelInBackgroundStaysOrderedBeforeLaterReenable() async throws {
        let suite = "cookplan.cancel-order.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanCancelFakeClient(); client.suspendRemoval = true
        let adapter = CookPlanNotifications(client: client), on = plan()
        try store.save(on); client.ids.insert(on.reminderID)
        let entered = CookPlanCancelEntryGate()
        client.onRemoval = { entered.signalEntry() }
        var reenable: Task<Void, Error>?
        let cleanup = try adapter.cancelFromSheet(recipeID: on.recipeID, store: store,
            onCommitted: {
                // Even an immediate re-enable from the success action is later intent.
                reenable = Task { try await adapter.reconcile(plans: [on], recipes: [RecipeCard(id: on.recipeID, title: "Soup")]) }
            }, onRemovalFailure: { XCTFail("Removal failed") })
        await entered.waitForEntry()
        XCTAssertTrue(client.adds.isEmpty, "Re-enable cannot pass the suspended cancellation")
        client.suspendRemoval = false; client.removalContinuation?.resume()
        await cleanup.value
        let reenabling = try XCTUnwrap(reenable)
        try await reenabling.value
        XCTAssertEqual(client.ids, ["ate.timer.keep", on.reminderID])
        XCTAssertEqual(client.adds, [on.scheduledAt])
    }

    func testCancelInBackgroundReportsRetainedReminder() async throws {
        let suite = "cookplan.cancel-retained.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanCancelFakeClient(); client.refuseRemoval = true
        let adapter = CookPlanNotifications(client: client), on = plan()
        try store.save(on); client.ids.insert(on.reminderID)
        var dismissed = false, reported = false
        let cleanup = try adapter.cancelFromSheet(recipeID: on.recipeID, store: store,
            onCommitted: { dismissed = true }, onRemovalFailure: { reported = true })
        XCTAssertTrue(dismissed)
        XCTAssertFalse(reported)
        await cleanup.value
        XCTAssertTrue(reported, "Retained OS reminder must reach the real failure callback")
        XCTAssertTrue(try store.plans().isEmpty)
        XCTAssertTrue(client.ids.contains(on.reminderID))
    }

    func testFailedLocalCancelLeavesStateUnchangedAndQueuesNoRemoval() async throws {
        let suite = "cookplan.local-cancel-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CookPlanStore(defaults: defaults)
        let client = CookPlanCancelFakeClient()
        let adapter = CookPlanNotifications(client: client)
        let unreadable = Data("unreadable".utf8)
        defaults.set(unreadable, forKey: CookPlanStore.storageKey)
        var dismissed = false, reported = false
        XCTAssertThrowsError(try adapter.cancelFromSheet(recipeID: "r1", store: store,
            onCommitted: { dismissed = true }, onRemovalFailure: { reported = true }))
        XCTAssertFalse(dismissed, "Failed local cancel must leave the sheet open")
        XCTAssertFalse(reported, "No notification action exists to report failure")
        XCTAssertEqual(defaults.data(forKey: CookPlanStore.storageKey), unreadable)
        XCTAssertEqual(client.removalCalls, 0)
        // Drain the same intent queue: a wrongly registered cancellation would
        // have run before this explicit probe and raised the count to two.
        try await adapter.cancel(recipeID: "probe")
        XCTAssertEqual(client.removalCalls, 1)
        XCTAssertFalse(dismissed)
        XCTAssertFalse(reported)
        XCTAssertEqual(client.permissionReads, 0)
        XCTAssertEqual(client.ids, ["ate.timer.keep"])
    }

}

private final class CookPlanCancelEntryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?

    func signalEntry() {
        lock.lock()
        entered = true
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume()
    }

    func waitForEntry() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if entered {
                lock.unlock()
                continuation.resume()
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}
