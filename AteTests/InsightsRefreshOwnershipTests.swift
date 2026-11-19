import XCTest
@testable import Ate

/// Continuation registration and waiter installation share one lock. Async helper
/// methods are not implicitly isolated by the test case's MainActor annotation.
private final class SuspendedInsightReads<Value> {
    private let lock = NSLock()
    private var reads: [CheckedContinuation<Value, Never>] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func read() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            reads.append(continuation)
            let ready = waiters.filter { reads.count >= $0.count }
            waiters.removeAll { reads.count >= $0.count }
            lock.unlock()
            // Never resume while holding the state lock.
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    func waitForRead(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if reads.count >= count {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((count, continuation))
                lock.unlock()
            }
        }
    }

    func resumeRead(_ index: Int, returning value: Value) {
        lock.lock()
        let continuation = reads[index]
        lock.unlock()
        continuation.resume(returning: value)
    }
}

/// No HealthKit, model or widget/default side effects.
private final class SuspendedInsightHealth: HealthKitServicing {
    private let accessLock = NSLock()
    private var storedAccess: HealthAccess = .requested
    var access: HealthAccess {
        get { accessLock.lock(); defer { accessLock.unlock() }; return storedAccess }
        set { accessLock.lock(); defer { accessLock.unlock() }; storedAccess = newValue }
    }
    var lastError: String? { nil }
    private let pending = SuspendedInsightReads<HealthSummary>()
    func requestAccess() async -> HealthAccess { access }
    func summary(days: Int) async -> HealthSummary { await pending.read() }
    func waitForRead(_ count: Int) async { await pending.waitForRead(count) }
    func resumeRead(_ index: Int, returning value: HealthSummary) { pending.resumeRead(index, returning: value) }
}
private final class SuspendedInsightPrompts {
    private let pending = SuspendedInsightReads<[JournalPrompt]>()
    func make(_ insight: HealthInsight) async -> [JournalPrompt] { await pending.read() }
    func waitForRead(_ count: Int) async { await pending.waitForRead(count) }
    func resumeRead(_ index: Int, returning value: [JournalPrompt]) { pending.resumeRead(index, returning: value) }
}
@MainActor
final class InsightsRefreshOwnershipTests: XCTestCase {
    func testSuspendedReadHandshakeSupportsConcurrentWaitersAndLateObservers() async {
        for value in 0..<32 {
            let pending = SuspendedInsightReads<Int>()
            let reader = Task { await pending.read() }
            let first = Task { await pending.waitForRead(1) }
            let second = Task { await pending.waitForRead(1) }
            await first.value
            await second.value
            // Read registration already happened: this observer must not suspend.
            await pending.waitForRead(1)
            pending.resumeRead(0, returning: value)
            let result = await reader.value
            XCTAssertEqual(result, value)
        }
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
        source.resumeRead(1, returning: fresh); await new.value
        let expected = model.context?.insight.state
        XCTAssertNotNil(expected); XCTAssertFalse(model.loading); XCTAssertEqual(published.count, 1)
        source.resumeRead(0, returning: summary("recovery")); await old.value
        XCTAssertEqual(model.context?.insight.state, expected)
        XCTAssertEqual(model.context?.summary, fresh); XCTAssertEqual(published.count, 1)
    }
    func testLatePromptCannotPublishAndOldDeferCannotStopNewLoading() async {
        let source = SuspendedInsightHealth(), prompts = SuspendedInsightPrompts(); var published: [HealthState] = []
        let model = InsightsModel(health: source, makePrompts: { await prompts.make($0) }, publishHealthState: { published.append($0) })
        let old = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.resumeRead(0, returning: summary("recovery")); await prompts.waitForRead(1)
        let new = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        prompts.resumeRead(0, returning: []); await old.value
        XCTAssertTrue(model.loading); XCTAssertNil(model.context); XCTAssertTrue(published.isEmpty)
        source.resumeRead(1, returning: summary("performance")); await prompts.waitForRead(2)
        prompts.resumeRead(1, returning: []); await new.value
        XCTAssertFalse(model.loading); XCTAssertNotNil(model.context); XCTAssertEqual(published.count, 1)
    }
    func testAccessLossAndCancellationDoNotPublishSuspendedSummary() async {
        let source = SuspendedInsightHealth(); var publications = 0
        let model = InsightsModel(health: source, makePrompts: { _ in [] }, publishHealthState: { _ in publications += 1 })
        let first = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.access = .denied
        source.resumeRead(0, returning: summary("recovery")); await first.value
        XCTAssertNil(model.context); XCTAssertEqual(model.access, .denied); XCTAssertEqual(publications, 0)
        source.access = .requested
        let cancelled = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        cancelled.cancel(); source.resumeRead(1, returning: summary("performance")); await cancelled.value
        XCTAssertNil(model.context); XCTAssertFalse(model.loading); XCTAssertEqual(publications, 0)
    }
    func testAccessLostDuringWordingAndNewEmptyEvidenceClearWithoutPublishing() async {
        let source = SuspendedInsightHealth(), prompts = SuspendedInsightPrompts(); var publications = 0
        let model = InsightsModel(health: source, makePrompts: { await prompts.make($0) }, publishHealthState: { _ in publications += 1 })
        let waiting = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.resumeRead(0, returning: summary("recovery")); await prompts.waitForRead(1)
        source.access = .denied; prompts.resumeRead(0, returning: []); await waiting.value
        XCTAssertNil(model.context); XCTAssertEqual(model.access, .denied); XCTAssertEqual(publications, 0)
        source.access = .requested
        let empty = Task { await model.refresh(recipes: []) }; await source.waitForRead(2)
        source.resumeRead(1, returning: HealthSummary(days: [])); await empty.value
        XCTAssertNil(model.context); XCTAssertFalse(model.loading); XCTAssertEqual(publications, 0)
    }
}
