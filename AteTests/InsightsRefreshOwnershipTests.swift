import XCTest
@testable import Ate

/// Only the existing suspension fixtures use this rendezvous. Async protocol
/// calls can run outside the test's MainActor, so readiness and append must be
/// one serialized transition, not a count check followed by callback install.
private final class SuspendedInsightReads<Value> {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<Value, Never>] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var reads: [CheckedContinuation<Value, Never>] {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    func suspend() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            pending.append(continuation)
            let ready = waiters.filter { pending.count >= $0.count }
            waiters.removeAll { pending.count >= $0.count }
            lock.unlock()
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    func waitForRead(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if pending.count >= count {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((count, continuation))
                lock.unlock()
            }
        }
    }
}

/// No HealthKit, model or widget/default side effects.
private final class SuspendedInsightHealth: HealthKitServicing {
    var access: HealthAccess = .requested
    var lastError: String?
    private let suspension = SuspendedInsightReads<HealthSummary>()
    var reads: [CheckedContinuation<HealthSummary, Never>] { suspension.reads }
    func requestAccess() async -> HealthAccess { access }
    func summary(days: Int) async -> HealthSummary { await suspension.suspend() }
    func waitForRead(_ count: Int) async { await suspension.waitForRead(count) }
}
private final class SuspendedInsightPrompts {
    private let suspension = SuspendedInsightReads<[JournalPrompt]>()
    var reads: [CheckedContinuation<[JournalPrompt], Never>] { suspension.reads }
    func make(_ insight: HealthInsight) async -> [JournalPrompt] { await suspension.suspend() }
    func waitForRead(_ count: Int) async { await suspension.waitForRead(count) }
}
@MainActor
final class InsightsRefreshOwnershipTests: XCTestCase {
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
    func testRevokedOwnerAfterSummaryCannotPublishContextOrWidgetState() async {
        let source = SuspendedInsightHealth(); var publications = 0, valid = true
        let model = InsightsModel(health: source, makePrompts: { _ in [] }, publishHealthState: { _ in publications += 1 })
        model.validateOwner = { if !valid { throw CancellationError() } }
        let waiting = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        valid = false
        source.reads[0].resume(returning: summary("recovery")); await waiting.value
        XCTAssertNil(model.context); XCTAssertEqual(publications, 0)
    }
    func testOriginalOwnerValidatorCannotBeReplacedDuringWordingAwait() async {
        let source = SuspendedInsightHealth(), prompts = SuspendedInsightPrompts()
        var publications = 0, originalValid = true
        let model = InsightsModel(health: source, makePrompts: { await prompts.make($0) }, publishHealthState: { _ in publications += 1 })
        model.validateOwner = { if !originalValid { throw CancellationError() } }
        let waiting = Task { await model.refresh(recipes: []) }; await source.waitForRead(1)
        source.reads[0].resume(returning: summary("recovery")); await prompts.waitForRead(1)
        originalValid = false; model.validateOwner = {}
        prompts.reads[0].resume(returning: []); await waiting.value
        XCTAssertNil(model.context); XCTAssertEqual(publications, 0)
    }

}
