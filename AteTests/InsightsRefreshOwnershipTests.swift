import XCTest
@testable import Ate

/// Test-only handshake: async protocol calls may run away from MainActor.
/// Check + waiter registration and read publication must share one lock.
private final class SuspendedInsightReads<Value> {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var reads: [CheckedContinuation<Value, Never>] { lock.withLock { continuations } }

    func suspend() async -> Value {
        await withCheckedContinuation { continuation in
            let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
                continuations.append(continuation)
                let ready = waiters.filter { $0.0 <= continuations.count }.map { $0.1 }
                waiters.removeAll { $0.0 <= continuations.count }
                return ready
            }
            // Resume outside the lock. The read is already published to every waiter.
            for waiter in ready { waiter.resume() }
        }
    }
    func waitForRead(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if continuations.count >= count { return true }
                waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

private final class SuspendedInsightHealth: HealthKitServicing {
    var access: HealthAccess = .requested
    var lastError: String?
    private let pending = SuspendedInsightReads<HealthSummary>()
    var reads: [CheckedContinuation<HealthSummary, Never>] { pending.reads }
    func requestAccess() async -> HealthAccess { access }
    func summary(days: Int) async -> HealthSummary { await pending.suspend() }
    func waitForRead(_ count: Int) async { await pending.waitForRead(count) }
}
private final class SuspendedInsightPrompts {
    private let pending = SuspendedInsightReads<[JournalPrompt]>()
    var reads: [CheckedContinuation<[JournalPrompt], Never>] { pending.reads }
    func make(_ insight: HealthInsight) async -> [JournalPrompt] { await pending.suspend() }
    func waitForRead(_ count: Int) async { await pending.waitForRead(count) }
}
@MainActor
final class InsightsRefreshOwnershipTests: XCTestCase {
    func testReadHandshakeSupportsConcurrentWaitersAndReadBeforeWait() async {
        let pending = SuspendedInsightReads<Int>()
        let firstWaiter = Task { await pending.waitForRead(1) }
        let secondWaiter = Task { await pending.waitForRead(1) }
        let read = Task { await pending.suspend() }
        await firstWaiter.value
        await secondWaiter.value
        // Registration after publication must return without depending on another read.
        await pending.waitForRead(1)
        XCTAssertEqual(pending.reads.count, 1)
        pending.reads[0].resume(returning: 42)
        let value = await read.value
        XCTAssertEqual(value, 42)
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
        let old = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.reads[0].resume(returning: summary("recovery")); await prompts.waitForRead(1)
        let new = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        prompts.reads[0].resume(returning: []); await old.value
        XCTAssertTrue(model.loading); XCTAssertNil(model.context); XCTAssertTrue(published.isEmpty)
        source.reads[1].resume(returning: summary("performance")); await prompts.waitForRead(2)
        prompts.reads[1].resume(returning: []); await new.value
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
        let waiting = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.reads[0].resume(returning: summary("recovery")); await prompts.waitForRead(1)
        source.access = .denied; prompts.reads[0].resume(returning: []); await waiting.value
        XCTAssertNil(model.context); XCTAssertEqual(model.access, .denied); XCTAssertEqual(publications, 0)
        source.access = .requested
        let empty = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        source.reads[1].resume(returning: HealthSummary(days: [])); await empty.value
        XCTAssertNil(model.context); XCTAssertFalse(model.loading); XCTAssertEqual(publications, 0)
    }
}
