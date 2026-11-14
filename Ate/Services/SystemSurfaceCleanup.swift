import Foundation
import CoreSpotlight
import UserNotifications
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Production ClearAllSystemSurfaceCleaning (#245, lane 3): the awaited system-surface
/// cleanup (protocol stage 8) the clear-all coordinator requires - no production
/// implementation existed before this one. Every surface is cleaned AND verified;
/// surfaces that could not be verified come back by name so the coordinator keeps the
/// control record and reports cloudCommittedLocalIncomplete instead of claiming done.
///
/// Gate discipline: the coordinator holds the reset gate for the whole local phase; no
/// flock is taken here and none is held across an await. `validateWriter` (the composed
/// writer-boundary validator, bound by central) is re-proven after every awaited system
/// call: a cleanup that outlived its epoch stops and reports instead of writing into a
/// state it no longer owns.
@MainActor
final class SystemSurfaceCleanup: ClearAllSystemSurfaceCleaning {
    /// Surface names reported to the coordinator on verification failure.
    enum Surface {
        static let notifications = "notifications"
        static let liveActivities = "live activities"
        static let spotlight = "spotlight"
        static let widgetSnapshots = "widget snapshots"
        static let activityLog = "activity log"
        /// The post-await writer fence failed: cleanup stopped early, later surfaces unattempted.
        static let writerFence = "writer gate validation"
    }

    private let timers: TimerCenter?
    private let bridge: PhoneWatchBridge
    private let activityLog: LiveActivityLog
    private let sharedDefaults: UserDefaults
    private let validateWriter: () throws -> Void
    private let deleteSpotlight: (@escaping @Sendable (Bool) -> Void) -> Void
    private let spotlightTimeout: TimeInterval

    /// Real dependencies are required (no fabricated empty implementation): the factory
    /// passes the live graph's timer center, bridge and log. `validateWriter` defaults
    /// to always-pass for tests and pre-activation wiring.
    init(timers: TimerCenter?,
         bridge: PhoneWatchBridge = .shared,
         activityLog: LiveActivityLog = .shared,
         sharedDefaults: UserDefaults = SharedContainer.defaults,
         validateWriter: @escaping () throws -> Void = {},
         spotlightTimeout: TimeInterval = 5,
         deleteSpotlight: @escaping (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
             CSSearchableIndex.default().deleteAllSearchableItems { error in
                 completion(error == nil)
             }
         }) {
        self.timers = timers
        self.bridge = bridge
        self.activityLog = activityLog
        self.sharedDefaults = sharedDefaults
        self.validateWriter = validateWriter
        self.spotlightTimeout = spotlightTimeout
        self.deleteSpotlight = deleteSpotlight
    }

    func cleanupAfterLocalErase() async -> [String] {
        var failed: [String] = []

        // In-memory timers first: stopping each one drives its own snapshot, bridge
        // mirror, notification cancel and Live Activity end through the writer boundary.
        if let timers { for t in timers.timers { timers.stop(t.id) } }

        // Watch mirror: queues an empty cook context over WatchConnectivity. Delivery to
        // the watch is not verifiable from here; the watch also converges on its next
        // refresh against the wiped server. Documented, not claimed as verified.
        bridge.update(timers: [])

        // Notifications: pending AND delivered, removed then verified after one settle.
        if await !TimerAlerts.removeAllAndVerify() { failed.append(Surface.notifications) }
        guard fence(&failed) else { return failed }

        // Live Activities: end every one, then verify none remain.
        if await !cleanLiveActivities() { failed.append(Surface.liveActivities) }
        guard fence(&failed) else { return failed }

        // Spotlight: no count API exists, so a successfully awaited delete of every
        // searchable item is the strongest verification the platform offers.
        if await !cleanSpotlight() { failed.append(Surface.spotlight) }
        guard fence(&failed) else { return failed }

        // Only the three widget/control snapshot keys are handled here. WidgetInbox
        // and SharedInbox queues need separate erase inventory before activation;
        // this cleanup does not claim they were cleared.
        // Read-back verifies strict absence, regardless of the stored value's type.
        if !cleanWidgetSnapshots() { failed.append(Surface.widgetSnapshots) }

        // Live Activity diagnostic log: cleared, then verified by read-back.
        activityLog.clear()
        if !activityLog.isCleared { failed.append(Surface.activityLog) }

        return failed
    }

    /// Post-await epoch re-check. A false return means the writer epoch moved mid-cleanup:
    /// the failure is reported and no further surface is attempted under a stale epoch.
    private func fence(_ failed: inout [String]) -> Bool {
        if (try? validateWriter()) != nil { return true }
        failed.append(Surface.writerFence)
        return false
    }

    private func cleanLiveActivities() async -> Bool {
        #if canImport(ActivityKit)
        for activity in Activity<CookTimerAttributes>.activities {
            await activity.end(ActivityContent(state: activity.content.state, staleDate: nil),
                               dismissalPolicy: .immediate)
        }
        return Activity<CookTimerAttributes>.activities.isEmpty
        #else
        return true
        #endif
    }

    private func cleanSpotlight() async -> Bool {
        // Service invalidation has left this callback unreturned on repeated CI
        // runs. Deadline/cancellation is UNVERIFIED, never successful erasure.
        // A late callback may not retire reset control or mutate later state.
        await SystemCleanupCompletion.wait(timeout: spotlightTimeout, start: deleteSpotlight)
    }

    private func cleanWidgetSnapshots() -> Bool {
        let clean = Self.removeSnapshotKeys(from: sharedDefaults)
        WidgetKinds.reloadAll()
        return clean
    }

    /// Internal seam tests a retained value after failed removal without system APIs.
    static func removeSnapshotKeys(from defaults: UserDefaults,
                                   remove: ((String) -> Void)? = nil) -> Bool {
        let keys = [WidgetSnapshot.key, WidgetKinds.heartbeatKey, TimerSnapshot.key]
        for key in keys {
            if let remove { remove(key) } else { defaults.removeObject(forKey: key) }
        }
        return keys.allSatisfy { defaults.object(forKey: $0) == nil }
    }
}
