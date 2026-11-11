import XCTest
@testable import Ate

final class CookPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func plan(_ id: String = "recipe-1", offset: TimeInterval = 3600,
                      reminder: Bool = true, zone: String = "Africa/Johannesburg") -> CookPlan {
        CookPlan(recipeID: id, scheduledAt: now.addingTimeInterval(offset),
                 timeZoneID: zone, reminderRequested: reminder)
    }

    private func withStore(_ body: (CookPlanStore, UserDefaults) throws -> Void) throws {
        let name = "CookPlanTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(CookPlanStore(defaults: defaults), defaults)
    }

    func testPlanPersistsWithoutNotificationPermissionAndReloads() throws {
        try withStore { store, defaults in
            let p = plan()
            try store.save(p, now: now)
            XCTAssertEqual(try CookPlanStore(defaults: defaults).plans(), [p])
            let state = CookPlanReminders.reconcile(plans: try store.plans(), existingRecipeIDs: [p.recipeID],
                notificationsAllowed: false, pendingIDs: [], now: now)
            XCTAssertTrue(state.desired.isEmpty)
            XCTAssertEqual(try store.plans(), [p], "Denied permission must not discard the plan")
        }
    }

    func testChangeAndRepeatedSaveReplaceOnePlanAndKeepStableReminderIdentity() throws {
        try withStore { store, _ in
            let first = plan(), changed = plan(offset: 7200)
            try store.save(first, now: now)
            try store.save(changed, now: now)
            try store.save(changed, now: now)
            XCTAssertEqual(try store.plans(), [changed])
            XCTAssertEqual(first.reminderID, changed.reminderID)
            let state = CookPlanReminders.reconcile(plans: try store.plans(), existingRecipeIDs: [first.recipeID],
                notificationsAllowed: true, pendingIDs: [first.reminderID], now: now)
            XCTAssertEqual(state.desired, [changed])
            XCTAssertTrue(state.removeIDs.isEmpty)
        }
    }

    func testCancelKeepsOtherRecipesAndRemovesOnlyOwnedReminder() throws {
        try withStore { store, _ in
            let p = plan(), other = plan("other")
            try store.save(p, now: now); try store.save(other, now: now)
            try store.cancel(recipeID: p.recipeID)
            try store.cancel(recipeID: p.recipeID)
            XCTAssertEqual(try store.plans(), [other])
            let state = CookPlanReminders.reconcile(plans: try store.plans(), existingRecipeIDs: [other.recipeID],
                notificationsAllowed: true, pendingIDs: [p.reminderID, other.reminderID, "ate.timer.live"], now: now)
            XCTAssertEqual(state.removeIDs, [p.reminderID])
        }
    }

    func testDeniedPermissionExpiredDeletedAndOptedOutPlansHaveNoReminder() {
        let kept = plan(), expired = plan("expired", offset: -1)
        let deleted = plan("deleted"), optedOut = plan("off", reminder: false)
        let all = [kept, expired, deleted, optedOut]
        let pending = Set(all.map(\.reminderID)).union(["ate.timer.keep"])
        let allowed = CookPlanReminders.reconcile(plans: all, existingRecipeIDs: [kept.recipeID, expired.recipeID, optedOut.recipeID],
            notificationsAllowed: true, pendingIDs: pending, now: now)
        XCTAssertEqual(allowed.desired, [kept])
        XCTAssertEqual(Set(allowed.removeIDs), Set([expired.reminderID, deleted.reminderID, optedOut.reminderID]))
        let denied = CookPlanReminders.reconcile(plans: all, existingRecipeIDs: [kept.recipeID],
            notificationsAllowed: false, pendingIDs: pending, now: now)
        XCTAssertTrue(denied.desired.isEmpty)
        XCTAssertEqual(Set(denied.removeIDs), Set(all.map(\.reminderID)))
    }

    func testPastAndInvalidPlansCannotReplaceExistingPlan() throws {
        try withStore { store, _ in
            let kept = plan()
            try store.save(kept, now: now)
            for invalid in [plan(offset: 0), plan(offset: -1), plan(""), plan(zone: "not/a-zone")] {
                XCTAssertThrowsError(try store.save(invalid, now: now))
                XCTAssertEqual(try store.plans(), [kept])
            }
        }
    }

    func testCorruptBytesArePreservedInsteadOfOverwrittenBySaveOrCancel() throws {
        try withStore { store, defaults in
            let raw = Data("broken plans".utf8)
            defaults.set(raw, forKey: CookPlanStore.storageKey)
            XCTAssertThrowsError(try store.plans())
            XCTAssertThrowsError(try store.save(plan(), now: now))
            XCTAssertThrowsError(try store.cancel(recipeID: "anything"))
            XCTAssertEqual(defaults.data(forKey: CookPlanStore.storageKey), raw)
        }
    }

    func testExplicitClearPreservesUnrelatedDefaults() throws {
        try withStore { store, defaults in
            try store.save(plan(), now: now)
            defaults.set("kept", forKey: "unrelated")
            try store.clear()
            XCTAssertTrue(try store.plans().isEmpty)
            XCTAssertEqual(defaults.string(forKey: "unrelated"), "kept")
        }
    }

    func testChosenInstantAndZoneSurviveReloadAndReminderIDsDoNotCollide() throws {
        try withStore { store, defaults in
            let p = plan(zone: "America/New_York")
            try store.save(p, now: now)
            XCTAssertEqual(try CookPlanStore(defaults: defaults).plans().first, p)
            XCTAssertNotEqual(plan("a/b").reminderID, plan("a?b").reminderID)
            XCTAssertFalse(p.reminderID.hasPrefix("ate.timer."))
        }
    }
    func testReminderRouteRequiresMatchingNamespaceAndPayload() {
        let p = plan()
        XCTAssertEqual(CookPlanNotificationRoute.recipeID(requestID: p.reminderID, payloadRecipeID: p.recipeID), p.recipeID)
        XCTAssertNil(CookPlanNotificationRoute.recipeID(requestID: "ate.timer.live", payloadRecipeID: p.recipeID))
        XCTAssertNil(CookPlanNotificationRoute.recipeID(requestID: p.reminderID, payloadRecipeID: "other"))
        XCTAssertNil(CookPlanNotificationRoute.recipeID(requestID: p.reminderID, payloadRecipeID: nil))
    }

}
