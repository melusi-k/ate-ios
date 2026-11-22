import XCTest
@testable import Ate

/// Test-only rendezvous. Read arrival and waiter registration share one lock.
/// Notifications run after unlocking so continuations can safely re-enter.
private final class SuspendedInsightReads<Value> {
    private struct Waiter {
        let count: Int
        let notify: () -> Void
    }
    private let lock = NSLock()
    private var values: [Value] = []
    private var waiters: [Waiter] = []

    var snapshot: [Value] { lock.withLock { values } }

    func append(_ value: Value) {
        let ready: [() -> Void] = lock.withLock {
            values.append(value)
            let count = values.count
            let ready = waiters.filter { $0.count <= count }.map { $0.notify }
            waiters.removeAll { $0.count <= count }
            return ready
        }
        ready.forEach { $0() }
    }

    func whenRead(_ count: Int, notify: @escaping () -> Void) {
        let ready = lock.withLock {
            if values.count >= count { return true }
            waiters.append(Waiter(count: count, notify: notify))
            return false
        }
        if ready { notify() }
    }

    func waitForRead(_ count: Int) async {
        await withCheckedContinuation { continuation in
            whenRead(count) { continuation.resume() }
        }
    }
}

private final class SuspendedInsightHealth: HealthKitServicing {
    var access: HealthAccess = .requested
    var lastError: String?
    private let pending = SuspendedInsightReads<CheckedContinuation<HealthSummary, Never>>()
    var reads: [CheckedContinuation<HealthSummary, Never>] { pending.snapshot }
    func requestAccess() async -> HealthAccess { access }
    func summary(days: Int) async -> HealthSummary {
        await withCheckedContinuation { continuation in pending.append(continuation) }
    }
    func waitForRead(_ count: Int) async { await pending.waitForRead(count) }
}
private final class SuspendedInsightPrompts {
    private let pending = SuspendedInsightReads<CheckedContinuation<[JournalPrompt], Never>>()
    var reads: [CheckedContinuation<[JournalPrompt], Never>] { pending.snapshot }
    func make(_ insight: HealthInsight) async -> [JournalPrompt] {
        await withCheckedContinuation { continuation in pending.append(continuation) }
    }
    func waitForRead(_ count: Int) async { await pending.waitForRead(count) }
}
@MainActor
final class InsightsRefreshOwnershipTests: XCTestCase {
    func testReadRegistrationCannotLoseArrivalAfterEarlierEmptyObservation() {
        let pending = SuspendedInsightReads<Int>()
        // Replay the lost-wakeup order: observe empty, arrive, then register.
        XCTAssertTrue(pending.snapshot.isEmpty)
        pending.append(1)
        var notifications = 0
        pending.whenRead(1) { notifications += 1 }
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(pending.snapshot, [1])
        pending.append(2)
        XCTAssertEqual(notifications, 1)
    }
    func testReadRegistrationNotifiesEachThresholdOnceAfterUnlocking() {
        let pending = SuspendedInsightReads<Int>()
        var notifications: [Int] = []
        pending.whenRead(1) {
            notifications.append(pending.snapshot.count)
        }
        pending.whenRead(2) {
            notifications.append(pending.snapshot.count)
        }
        pending.append(1)
        XCTAssertEqual(notifications, [1])
        pending.append(2)
        XCTAssertEqual(notifications, [1, 2])
        pending.append(3)
        XCTAssertEqual(notifications, [1, 2])
    }
    private func summary(_ scenario: String) -> HealthSummary {
        MockHealthKitService.fixture(scenario, now: Date(timeIntervalSince1970: 1_794_564_000))
    }
    func testLateOlderSummaryCannotReplaceNewContextOrWidgetState() async {
        let source = SuspendedInsightHealth(); var published: [HealthState] = []
        let model = InsightsModel(health: source, makePrompts: { _ in [] }, publishHealthState: { published.append($0) })
        let old = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        let new = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        let fresh = summary("performance")
        source.reads[1].resume(returning: fresh); await new.value
        let expected = model.context?.insight.state
        XCTAssertNotNil(expected); XCTAssertFalse(model.loading); XCTAssertEqual(published.count, 1)
        source.reads[0].resume(returning: summary("recovery")); await old.value
        XCTAssertEqual(model.context?.insight.state, expected)
        XCTAssertEqual(model.context?.summary, fresh); XCTAssertEqual(published.count, 1)
    }
    func testLatePromptCannotPublishAndOldDeferCannotStopNewLoading() async {
        let source = SuspendedInsightHealth(), prompts = SuspendedInsightPrompts(); var published: [HealthState] = []
        let model = InsightsModel(health: source, makePrompts: { await prompts.make($0) }, publishHealthState: { published.append($0) })
        insightAwaitPhase("before-old-health-read")
        let old = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        insightAwaitPhase("after-old-health-read")
        insightAwaitPhase("before-old-prompts-read")
        source.reads[0].resume(returning: summary("recovery")); await prompts.waitForRead(1)
        insightAwaitPhase("after-old-prompts-read")
        insightAwaitPhase("before-new-health-read")
        let new = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        insightAwaitPhase("after-new-health-read")
        insightAwaitPhase("before-old-task-return")
        prompts.reads[0].resume(returning: []); await old.value
        insightAwaitPhase("after-old-task-return")
        XCTAssertTrue(model.loading); XCTAssertNil(model.context); XCTAssertTrue(published.isEmpty)
        insightAwaitPhase("before-new-prompts-read")
        source.reads[1].resume(returning: summary("performance")); await prompts.waitForRead(2)
        insightAwaitPhase("after-new-prompts-read")
        insightAwaitPhase("before-new-task-return")
        prompts.reads[1].resume(returning: []); await new.value
        insightAwaitPhase("after-new-task-return")
        XCTAssertFalse(model.loading); XCTAssertNotNil(model.context); XCTAssertEqual(published.count, 1)
    }
    func testAccessLossAndCancellationDoNotPublishSuspendedSummary() async {
        let source = SuspendedInsightHealth(); var publications = 0
        let model = InsightsModel(health: source, makePrompts: { _ in [] }, publishHealthState: { _ in publications += 1 })
        let first = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.access = .denied
        source.reads[0].resume(returning: summary("recovery")); await first.value
        XCTAssertNil(model.context); XCTAssertEqual(model.access, .denied); XCTAssertEqual(publications, 0)
        source.access = .requested
        let cancelled = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        cancelled.cancel(); source.reads[1].resume(returning: summary("performance")); await cancelled.value
        XCTAssertNil(model.context); XCTAssertFalse(model.loading); XCTAssertEqual(publications, 0)
    }
    func testAccessLostDuringWordingAndNewEmptyEvidenceClearWithoutPublishing() async {
        let source = SuspendedInsightHealth(), prompts = SuspendedInsightPrompts(); var publications = 0
        let model = InsightsModel(health: source, makePrompts: { await prompts.make($0) }, publishHealthState: { _ in publications += 1 })
        insightAwaitPhase("accesslost-before-health-one")
        let waiting = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        insightAwaitPhase("accesslost-after-health-one")
        insightAwaitPhase("accesslost-before-prompts-one")
        source.reads[0].resume(returning: summary("recovery")); await prompts.waitForRead(1)
        insightAwaitPhase("accesslost-after-prompts-one")
        insightAwaitPhase("accesslost-before-waiting-task-return")
        source.access = .denied; prompts.reads[0].resume(returning: []); await waiting.value
        insightAwaitPhase("accesslost-after-waiting-task-return")
        XCTAssertNil(model.context); XCTAssertEqual(model.access, .denied); XCTAssertEqual(publications, 0)
        source.access = .requested
        insightAwaitPhase("accesslost-before-health-two")
        let empty = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        insightAwaitPhase("accesslost-after-health-two")
        insightAwaitPhase("accesslost-before-empty-task-return")
        source.reads[1].resume(returning: HealthSummary(days: [])); await empty.value
        insightAwaitPhase("accesslost-after-empty-task-return")
        XCTAssertNil(model.context); XCTAssertFalse(model.loading); XCTAssertEqual(publications, 0)
    }
}

// Fixed-count diagnostic only. No synchronization, actor or scheduling decisions.
private func insightAwaitPhase(_ phase: String) {
    let line = "INSIGHTS-AWAIT phase=\(phase) monotonic_ns=\(DispatchTime.now().uptimeNanoseconds) main_thread=\(Thread.isMainThread)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}
