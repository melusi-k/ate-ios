import XCTest
import UserNotifications
@testable import Ate

/// Guards the kitchen-toggle relay stall repair. Measured fact (KITCHEN-SUB
/// ledger, run 46113118998): a 110s stall inside TimerAlerts.schedule as a whole
/// on the relay return; the first-IPC/usernoted explanation is a hypothesis, not
/// verified. These tests stall the system-call seam on the alert queue, prove the
/// worker entered the seam before releasing it, and require callers to return
/// anyway; a synchronous regression trips the elapsed bound instead of hanging.
/// Gates are bounded (10s self-release) and registered for guaranteed teardown
/// release, so a failing test cannot strand queue work, and every mutable seam is
/// restored in tearDown so nothing leaks between tests.
final class TimerAlertsRelayTests: XCTestCase {
    override func tearDown() {
        TimerAlerts.performSystemSchedule = TimerAlerts.systemSchedule
        TimerAlerts.performRemoveAll = TimerAlerts.systemRemoveAll
        TimerAlerts.now = Date.init
        TimerAlerts.drainTimeout = 5
        TimerAlerts.fenceInstalled = {}
        super.tearDown()
    }

    /// A fake IPC worker that proves its own entry, then stalls on a bounded gate
    /// (self-releasing after 10s, and released by a teardown block on any failure,
    /// so queue work can never be stranded).
    private func stalledWorker(_ entered: XCTestExpectation, _ finished: XCTestExpectation,
                               gate: DispatchSemaphore,
                               onRun: @escaping (UNNotificationRequest?) -> Void = { _ in }) {
        addTeardownBlock { gate.signal() }
        TimerAlerts.performSystemSchedule = { _, makeRequest, completion in
            entered.fulfill()
            _ = gate.wait(timeout: .now() + 10)
            onRun(makeRequest())
            completion(nil)
            finished.fulfill()
        }
    }

    func testScheduleDoesNotBlockCallerWhenNotificationIPCStalls() {
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "worker entered the seam")
        let finished = expectation(description: "stalled IPC released")
        stalledWorker(entered, finished, gate: gate)
        let start = Date()
        TimerAlerts.schedule(id: "relay-stall", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "schedule returned while the notification IPC was stalled")
        wait(for: [entered], timeout: 5)   // prove the worker is inside the seam before releasing it
        gate.signal()
        wait(for: [finished], timeout: 15)
    }

    func testCancelDoesNotBlockCallerWhenNotificationIPCStalls() {
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "worker entered the seam")
        let finished = expectation(description: "stalled IPC released")
        stalledWorker(entered, finished, gate: gate)
        let start = Date()
        TimerAlerts.cancel(id: "relay-stall")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "cancel returned while the notification IPC was stalled")
        wait(for: [entered], timeout: 5)
        gate.signal()
        wait(for: [finished], timeout: 15)
    }

    func testScheduleRecordsFailureSurfaceOnAlertError() {
        let ran = expectation(description: "alert IPC ran")
        TimerAlerts.performSystemSchedule = { _, _, completion in
            completion(NSError(domain: "TimerAlertsRelayTests", code: 1))
            ran.fulfill()
        }
        TimerAlerts.schedule(id: "relay-failure", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [ran], timeout: 5)
        XCTAssertNotNil(TimerAlerts.lastScheduleError, "best-effort scheduling records the failure instead of throwing")
    }

    func testScheduleSuccessClearsSeededFailureSurface() {
        let failed = expectation(description: "failing IPC ran")
        TimerAlerts.performSystemSchedule = { _, _, completion in
            completion(NSError(domain: "TimerAlertsRelayTests", code: 1))
            failed.fulfill()
        }
        TimerAlerts.schedule(id: "relay-seed", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [failed], timeout: 5)
        XCTAssertNotNil(TimerAlerts.lastScheduleError, "seeded failure is recorded before the success")
        let succeeded = expectation(description: "succeeding IPC ran")
        TimerAlerts.performSystemSchedule = { _, _, completion in
            completion(nil)
            succeeded.fulfill()
        }
        TimerAlerts.schedule(id: "relay-seed", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [succeeded], timeout: 5)
        XCTAssertNil(TimerAlerts.lastScheduleError, "a successful schedule clears the seeded failure surface")
    }

    /// The relay path itself: kitchenToggle must return its result and persist the
    /// timer snapshot synchronously (widget durability) while the alert IPC is
    /// still stalled in the background. The elapsed assertion is bounded by the
    /// gate's self-release, so a synchronous regression fails instead of passing
    /// after the gate times out.
    @MainActor
    func testKitchenToggleRelayReturnsWithSynchronousSnapshotWhileAlertIPCStalled() {
        XCTAssertTrue(TimerSnapshot.save([]))
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "worker entered the seam")
        let finished = expectation(description: "stalled IPC released")
        stalledWorker(entered, finished, gate: gate)
        let center = TimerCenter()
        let start = Date()
        XCTAssertEqual(center.kitchenToggle(), "started")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5,
                          "kitchenToggle returned while the alert IPC was stalled")
        XCTAssertEqual(TimerSnapshot.load().first?.recipeID, TimerMath.quickRecipeID,
                       "TimerSnapshot.save stays synchronous on the relay path")
        wait(for: [entered], timeout: 5)
        gate.signal()
        wait(for: [finished], timeout: 15)
    }

    /// Elapsed deadline, adversarial: the clock advances DURING the removal, while
    /// the worker is provably held inside the seam before the request is built.
    /// The trigger must reflect the end date at that moment, not the enqueue time.
    func testScheduleComputesTriggerAfterRemovalFromRetainedEndDate() {
        let base = Date()
        var fakeNow = base
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "worker inside the removal")
        let ran = expectation(description: "alert IPC ran")
        var captured: UNTimeIntervalNotificationTrigger?
        TimerAlerts.now = { fakeNow }
        TimerAlerts.performSystemSchedule = { _, makeRequest, completion in
            entered.fulfill()
            _ = gate.wait(timeout: .now() + 10)   // hold the worker mid-removal, before the request is built
            captured = makeRequest()?.trigger as? UNTimeIntervalNotificationTrigger
            completion(nil)
            ran.fulfill()
        }
        addTeardownBlock { gate.signal() }
        TimerAlerts.schedule(id: "exec-time", step: 1, recipeTitle: "Test", at: base.addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [entered], timeout: 5)   // worker provably mid-removal; the clock advances during it
        fakeNow = base.addingTimeInterval(45)
        gate.signal()
        wait(for: [ran], timeout: 15)
        XCTAssertEqual(captured?.timeInterval ?? -1, 15, accuracy: 0.5,
                       "trigger is computed after the removal, from the retained absolute end date")
    }

    /// An end date that expires during the removal is refused: no add is built and
    /// the refusal is recorded.
    func testScheduleRefusesEndDateExpiredDuringRemovalAndRecordsRefusal() {
        let base = Date()
        var fakeNow = base
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "worker inside the removal")
        let ran = expectation(description: "alert IPC ran")
        var sawAdd = false
        TimerAlerts.now = { fakeNow }
        TimerAlerts.performSystemSchedule = { _, makeRequest, completion in
            entered.fulfill()
            _ = gate.wait(timeout: .now() + 10)
            if makeRequest() != nil { sawAdd = true }
            completion(nil)
            ran.fulfill()
        }
        addTeardownBlock { gate.signal() }
        TimerAlerts.schedule(id: "expired", step: 1, recipeTitle: "Test", at: base.addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [entered], timeout: 5)
        fakeNow = base.addingTimeInterval(120)   // end date expires during the removal
        gate.signal()
        wait(for: [ran], timeout: 15)
        XCTAssertFalse(sawAdd, "an expired end date is never added")
        XCTAssertEqual(TimerAlerts.lastScheduleError, "refused expired schedule for ate.timer.expired")
    }

    /// Pending work versus erase, adversarial: the add's callback is HELD, so the
    /// erase cannot be ordered by queue position alone. removeAllAndVerify must
    /// wait for the in-flight add callback before removing; only then may it claim
    /// erasure.
    func testEraseWaitsForInFlightAddCallbackBeforeRemoving() async {
        let entered = expectation(description: "add initiated with its callback held")
        let seamLock = NSLock()
        var heldCompletion: ((Error?) -> Void)?
        // Consume-and-nil under the lock on every release path: a held completion
        // fires at most once, so the global in-flight count stays balanced.
        let releaseHeld = {
            seamLock.lock()
            let release = heldCompletion
            heldCompletion = nil
            seamLock.unlock()
            release?(nil)
        }
        TimerAlerts.performSystemSchedule = { _, makeRequest, completion in
            _ = makeRequest()
            seamLock.lock(); heldCompletion = completion; seamLock.unlock()
            entered.fulfill()
        }
        let eraseRan = expectation(description: "erase ran")
        let eraseEarly = expectation(description: "erase ran while an add callback was held")
        eraseEarly.isInverted = true
        TimerAlerts.performRemoveAll = { eraseRan.fulfill(); eraseEarly.fulfill() }
        addTeardownBlock { releaseHeld() }   // never strand the queue: release on any outcome
        TimerAlerts.schedule(id: "held-add", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [entered], timeout: 5)   // add initiated; its completion is provably held
        let cleanup = Task { await TimerAlerts.removeAllAndVerify() }
        wait(for: [eraseEarly], timeout: 1)   // passes only if no erase runs during the held callback
        releaseHeld()
        wait(for: [eraseRan], timeout: 15)
        let ok = await cleanup.value
        XCTAssertTrue(ok, "once the in-flight add drains, the erase runs and reports success")
    }

    /// Stale-epoch rejection: work enqueued before a clear-all fence that only
    /// reaches the queue after the fence must be rejected without touching the
    /// system seam; work enqueued after the fence schedules normally.
    func testStaleQueuedScheduleRejectedAfterClearAllEpoch() async {
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "first schedule worker inside the seam")
        let lock = NSLock()
        var order: [String] = []
        var seamCalls = 0
        let noteAdd = { (id: String) in lock.lock(); order.append("add:" + id); seamCalls += 1; lock.unlock() }
        TimerAlerts.performSystemSchedule = { id, makeRequest, completion in
            entered.fulfill()
            _ = gate.wait(timeout: .now() + 10)
            if makeRequest() != nil { noteAdd(id) }
            completion(nil)
        }
        let eraseRan = expectation(description: "erase ran")
        TimerAlerts.performRemoveAll = { eraseRan.fulfill() }
        addTeardownBlock { gate.signal() }
        let fenced = expectation(description: "clear-all fence installed")
        TimerAlerts.fenceInstalled = { fenced.fulfill() }
        TimerAlerts.schedule(id: "running", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [entered], timeout: 5)   // the first schedule is provably stalled inside the seam
        TimerAlerts.schedule(id: "stale", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        let cleanup = Task { await TimerAlerts.removeAllAndVerify() }   // fences: "stale" was enqueued before it
        wait(for: [fenced], timeout: 5)   // deterministic: the epoch bump is acknowledged before the worker is released
        gate.signal()
        wait(for: [eraseRan], timeout: 15)
        let ok = await cleanup.value
        XCTAssertTrue(ok)
        lock.lock(); let finalOrder = order; let calls = seamCalls; lock.unlock()
        XCTAssertEqual(calls, 1, "the stale queued schedule never reaches the system seam")
        XCTAssertEqual(finalOrder, ["add:running"], "only the pre-fence running schedule added, then the erase")
        XCTAssertEqual(TimerAlerts.lastScheduleError, "refused stale schedule for ate.timer.stale: superseded by clear-all")
        let postFence = expectation(description: "post-fence schedule added")
        TimerAlerts.performSystemSchedule = { id, makeRequest, completion in
            if makeRequest() != nil { noteAdd(id) }
            completion(nil)
            postFence.fulfill()
        }
        TimerAlerts.schedule(id: "post-fence", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [postFence], timeout: 5)
        lock.lock(); let after = order; lock.unlock()
        XCTAssertEqual(after, ["add:running", "add:post-fence"], "work enqueued after the fence schedules normally")
        XCTAssertNil(TimerAlerts.lastScheduleError, "the post-fence success clears the recorded refusal")
    }

    /// Bounded failure reporting: if in-flight alert work cannot drain, the
    /// clear-all must not run the removal and must report failure instead of
    /// claiming erasure while old schedule effects can still appear.
    func testEraseReportsFailureWhenInFlightWorkCannotDrain() async {
        TimerAlerts.drainTimeout = 0.5
        let entered = expectation(description: "add initiated with its callback held")
        let seamLock = NSLock()
        var heldCompletion: ((Error?) -> Void)?
        // Consume-and-nil under the lock on every release path: a held completion
        // fires at most once, so the global in-flight count stays balanced.
        let releaseHeld = {
            seamLock.lock()
            let release = heldCompletion
            heldCompletion = nil
            seamLock.unlock()
            release?(nil)
        }
        TimerAlerts.performSystemSchedule = { _, makeRequest, completion in
            _ = makeRequest()
            seamLock.lock(); heldCompletion = completion; seamLock.unlock()
            entered.fulfill()
        }
        let eraseMustNotRun = expectation(description: "removeAll ran while the add was stuck")
        eraseMustNotRun.isInverted = true
        TimerAlerts.performRemoveAll = { eraseMustNotRun.fulfill() }
        addTeardownBlock { releaseHeld() }
        TimerAlerts.schedule(id: "stuck-add", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [entered], timeout: 5)
        let ok = await TimerAlerts.removeAllAndVerify()
        XCTAssertFalse(ok, "a clear-all that cannot drain in-flight work reports failure")
        XCTAssertEqual(TimerAlerts.lastScheduleError, "clear-all could not drain in-flight alert work; erasure not claimed")
        wait(for: [eraseMustNotRun], timeout: 1)
    }

    /// Sequence identity: an older add callback must not overwrite the result of a
    /// newer schedule that completed first.
    func testOlderCompletionCannotOverwriteNewerRecordedResult() {
        var completions: [(Error?) -> Void] = []
        let captured = expectation(description: "both schedules reached the seam")
        captured.expectedFulfillmentCount = 2
        TimerAlerts.performSystemSchedule = { _, _, completion in
            completions.append(completion)
            captured.fulfill()
        }
        TimerAlerts.schedule(id: "older", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        TimerAlerts.schedule(id: "newer", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [captured], timeout: 5)
        completions[1](nil)   // newer completes first: success
        XCTAssertNil(TimerAlerts.lastScheduleError)
        completions[0](NSError(domain: "TimerAlertsRelayTests", code: 1))   // older failure arrives late
        XCTAssertNil(TimerAlerts.lastScheduleError, "an older completion cannot overwrite the newer recorded result")
    }

    /// The other order: the older failure lands first, the newer success still wins.
    func testNewerCompletionAfterOlderFailureReplacesRecordedResult() {
        var completions: [(Error?) -> Void] = []
        let captured = expectation(description: "both schedules reached the seam")
        captured.expectedFulfillmentCount = 2
        TimerAlerts.performSystemSchedule = { _, _, completion in
            completions.append(completion)
            captured.fulfill()
        }
        TimerAlerts.schedule(id: "older", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        TimerAlerts.schedule(id: "newer", step: 1, recipeTitle: "Test", at: Date().addingTimeInterval(60), prefs: TimerPrefs())
        wait(for: [captured], timeout: 5)
        completions[0](NSError(domain: "TimerAlertsRelayTests", code: 1))
        XCTAssertNotNil(TimerAlerts.lastScheduleError)
        completions[1](nil)
        XCTAssertNil(TimerAlerts.lastScheduleError, "the newer completion replaces the older recorded result")
    }
}
