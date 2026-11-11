import XCTest
@testable import Ate

/// Lane 3 (watch / media / system writers) writer-boundary tests (#245).
/// WRITTEN, NOT EXECUTED natively (no Xcode in the authoring sandbox). They pin user
/// intent: one mutation is one gated effect covering the write AND the publish, a stale
/// post-await result is dropped rather than applied, the legacy default changes nothing,
/// and clear-all cleanup never claims a surface it could not verify.
@MainActor final class Lane3WriterBoundaryTests: XCTestCase {

    private struct Borked: Error {}

    private final class RunCounter { var count = 0 }

    // MARK: WatchWriterBoundary seam shape

    func testLegacyWatchBoundaryIsAnExactPassthrough() throws {
        let b = WatchWriterBoundary.legacy
        let epoch = b.captureEpoch()
        XCTAssertEqual(try b.withEffect { 41 + 1 }, 42)
        b.invalidateEpoch()   // no-op for the legacy boundary
        XCTAssertEqual(b.captureEpoch(), epoch)
        XCTAssertNoThrow(try b.validateEpoch(epoch))
    }

    func testWatchBoundaryFencesStalePostAwaitResults() throws {
        let b = WatchWriterBoundary { try $0() }   // production shape: real epoch checks
        let captured = b.captureEpoch()
        b.invalidateEpoch()                        // session changed during the await
        XCTAssertThrowsError(try b.validateEpoch(captured)) { error in
            XCTAssertEqual(error as? WatchWriterBoundary.Failure, .staleEpoch)
        }
        XCTAssertNoThrow(try b.validateEpoch(b.captureEpoch()))
    }

    func testWatchBoundaryRunsTheEffectExactlyOnceAndReenters() throws {
        let counter = RunCounter()
        let b = WatchWriterBoundary { effect in counter.count += 1; try effect() }
        let value = try b.withEffect { try b.withEffect { 7 } }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(counter.count, 1)   // a nested effect never re-enters perform
        let repeated = WatchWriterBoundary { effect in try effect(); try effect() }
        XCTAssertThrowsError(try repeated.withEffect {}) { error in
            XCTAssertEqual(error as? WatchWriterBoundary.Failure, .repeatedEffect)
        }
    }

    func testHealthyExpiredTokenRefreshPublishesUnderTheNewEpoch() async throws {
        let boundary = WatchWriterBoundary { try $0() }
        let oldEpoch = boundary.captureEpoch()
        var currentToken = "expired"
        var fetchedToken: String?
        var published: String?
        try await boundary.publishAfterToken(token: {
            // Same transition as validToken -> setSession after a healthy refresh.
            try? boundary.withEffect { boundary.invalidateEpoch(); currentToken = "refreshed" }
            return currentToken
        }, isCurrentToken: { $0 == currentToken }, fetch: { token in
            fetchedToken = token
            return "fresh rows"
        }, publish: { published = $0 })
        XCTAssertThrowsError(try boundary.validateEpoch(oldEpoch))
        XCTAssertEqual(fetchedToken, "refreshed")
        XCTAssertEqual(published, "fresh rows")
    }

    func testSessionRaceDuringGETDoesNotPublishForeignRows() async {
        let boundary = WatchWriterBoundary { try $0() }
        var currentToken = "account-A"
        var published = false
        do {
            try await boundary.publishAfterToken(token: { currentToken },
                isCurrentToken: { $0 == currentToken }, fetch: { _ in
                    // Deterministic awaited response seam: B owns the session before A returns.
                    boundary.invalidateEpoch(); currentToken = "account-B"
                    return "account-A rows"
                }, publish: { _ in published = true })
            XCTFail("Stale GET must be refused")
        } catch { XCTAssertEqual(error as? WatchWriterBoundary.Failure, .staleEpoch) }
        XCTAssertFalse(published)
    }

    func testTokenNoLongerOwnedAfterAwaitDoesNotStartGET() async throws {
        let boundary = WatchWriterBoundary { try $0() }
        var fetched = false
        try await boundary.publishAfterToken(token: { "account-A" },
            isCurrentToken: { $0 == "account-B" }, fetch: { _ in fetched = true; return 1 },
            publish: { _ in XCTFail("Foreign token must not publish") })
        XCTAssertFalse(fetched)
    }

    // MARK: WatchTimerStore

    func testWatchTimerStoreSaveIsOneGatedEffect() {
        let counter = RunCounter()
        WatchTimerStore.writerBoundary = WatchWriterBoundary { effect in counter.count += 1; try effect() }
        defer {
            WatchTimerStore.writerBoundary = .legacy
            WatchTimerStore.save(nil)
        }
        WatchTimerStore.save(.start(title: "Test", step: 0, seconds: 60))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(WatchTimerStore.load()?.total, 60)
        WatchTimerStore.save(nil)
        XCTAssertNil(WatchTimerStore.load())
    }

    // MARK: TimerCenter

    func testTimerCenterMutationIsOneGatedEffect() {
        let center = TimerCenter()
        defer { LiveActivityLog.shared.clear() }
        let counter = RunCounter()
        center.writerBoundary = FoodJournalWriterBoundary { effect in counter.count += 1; try effect() }
        center.stop("missing")   // even a no-op mutation route enters the boundary once
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(center.kitchenToggle(), "started")
        XCTAssertEqual(center.timers.count, 1)
        XCTAssertEqual(counter.count, 2)
        center.stop(center.timers[0].id)
        XCTAssertTrue(center.timers.isEmpty)
        XCTAssertEqual(counter.count, 3)
    }

    func testTimerCenterFailedBoundaryPublishesNothing() {
        let center = TimerCenter()
        center.writerBoundary = FoodJournalWriterBoundary { _ in throw Borked() }
        XCTAssertEqual(center.kitchenToggle(), "unavailable")
        XCTAssertTrue(center.timers.isEmpty)   // a failed effect leaves no partial state
        center.stop("missing")
        XCTAssertTrue(center.timers.isEmpty)
    }

    func testReadOnlyTicksCommitZeroAndExpiryCommitsOneGeneration() throws {
        let saved = SharedContainer.defaults.object(forKey: TimerSnapshot.key)
        defer {
            SharedContainer.defaults.set(saved, forKey: TimerSnapshot.key)
            LiveActivityLog.shared.clear()
        }
        TimerSnapshot.save([])
        let center = TimerCenter()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.resolvingSymlinksInPath().standardizedFileURL
        func generation() throws -> UInt64 {
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            return lease.generation
        }
        center.writerBoundary = FoodJournalWriterBoundary { work in
            try SharedArchiveNestedUnit.run(directory: directory, work)
        }
        let idle = Date(timeIntervalSince1970: 1)
        center.tick(idle)
        XCTAssertEqual(center.now, idle)
        XCTAssertEqual(try generation(), 0)
        // Set up the running timer outside the measured archive generation chain.
        center.writerBoundary = .legacy
        center.startQuick(seconds: 60)
        center.writerBoundary = FoodJournalWriterBoundary { work in
            try SharedArchiveNestedUnit.run(directory: directory, work)
        }
        let running = Date()
        for _ in 0..<60 { center.tick(running) }
        XCTAssertEqual(try generation(), 0)
        XCTAssertEqual(center.timers.count, 1)
        let expiry = center.timers[0].endDate!.addingTimeInterval(1)
        center.tick(expiry)
        XCTAssertTrue(center.timers.isEmpty)
        XCTAssertEqual(try generation(), 1)
        center.tick(expiry.addingTimeInterval(1))
        XCTAssertEqual(try generation(), 1)
    }

    // MARK: LiveActivityLog

    func testLiveActivityLogWriteIsGatedAndClearIsVerifiable() {
        let log = LiveActivityLog()
        let counter = RunCounter()
        log.writerBoundary = FoodJournalWriterBoundary { effect in counter.count += 1; try effect() }
        log.add("lane3 test entry")
        XCTAssertEqual(counter.count, 1)
        XCTAssertTrue(log.entries.first?.contains("lane3 test entry") == true)
        log.clear()
        XCTAssertTrue(log.isCleared)
    }

    // MARK: SystemSurfaceCleanup (production ClearAllSystemSurfaceCleaning)

    /// The user-intent assertion: after clear-all cleanup, no widget or timer snapshot
    /// survives anywhere the widget could read it back, and the activity log is empty.
    /// System-surface outcomes that depend on the environment (Spotlight, notification
    /// center) are reported by name, not asserted here - the contract is that failure is
    /// reported, never hidden.
    func testCleanupRemovesEveryVerifiableSnapshot() async {
        let shared = SharedContainer.defaults
        shared.set(Data([1]), forKey: WidgetSnapshot.key)
        shared.set(["ate.widget.timers": 1.0], forKey: WidgetKinds.heartbeatKey)
        TimerSnapshot.save([TimerSnapshot(recipeID: "r", recipeTitle: "t", stepIndex: 0,
                                          stepCount: 1, stepText: "s", total: 60,
                                          endDate: nil, pausedRemaining: 60)])
        let center = TimerCenter()   // adopts the seeded snapshot
        XCTAssertEqual(center.timers.count, 1)
        let log = LiveActivityLog.shared
        log.add("seed")

        let cleanup = SystemSurfaceCleanup(timers: center)
        let failed = await cleanup.cleanupAfterLocalErase()

        XCTAssertTrue(center.timers.isEmpty)
        XCTAssertNil(shared.object(forKey: WidgetSnapshot.key))
        XCTAssertNil(shared.object(forKey: WidgetKinds.heartbeatKey))
        XCTAssertNil(shared.object(forKey: TimerSnapshot.key))
        XCTAssertTrue(log.isCleared)
        XCTAssertFalse(failed.contains(SystemSurfaceCleanup.Surface.widgetSnapshots))
        XCTAssertFalse(failed.contains(SystemSurfaceCleanup.Surface.activityLog))
    }

    func testSnapshotVerificationRejectsRetainedNonDataValuesAfterFailedRemoval() throws {
        let suite = "ate.cleanup.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = [WidgetSnapshot.key, WidgetKinds.heartbeatKey, TimerSnapshot.key]
        for retainedKey in keys {
            defaults.set(["heartbeat": 1.0], forKey: retainedKey)
            XCTAssertNil(defaults.data(forKey: retainedKey), "The old typed read falsely looked absent")
            XCTAssertFalse(SystemSurfaceCleanup.removeSnapshotKeys(from: defaults, remove: { key in
                if key != retainedKey { defaults.removeObject(forKey: key) }
            }), "Any retained object must fail strict absence verification")
            XCTAssertNotNil(defaults.object(forKey: retainedKey))
            XCTAssertTrue(SystemSurfaceCleanup.removeSnapshotKeys(from: defaults))
            XCTAssertNil(defaults.object(forKey: retainedKey))
        }
    }

    /// A writer fence that fails mid-cleanup is reported, and later surfaces are not
    /// claimed clean under a stale epoch.
    func testCleanupReportsAFailedWriterFence() async {
        struct Fence: Error {}
        let cleanup = SystemSurfaceCleanup(timers: TimerCenter(), validateWriter: { throw Fence() })
        let failed = await cleanup.cleanupAfterLocalErase()
        XCTAssertTrue(failed.contains(SystemSurfaceCleanup.Surface.writerFence))
    }
}
