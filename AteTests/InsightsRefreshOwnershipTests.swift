import XCTest
import Foundation
@testable import Ate

/// Native UNRUN. No HealthKit, model or widget/default side effects.
/// Atomic registration prevents a read arriving between the count check and waiter install.
/// The fake may be called on the generic async executor while the test awaits on MainActor.
private final class SuspendedInsightHealth: HealthKitServicing {
    private let lock = NSLock()
    private var storedAccess: HealthAccess = .requested
    var access: HealthAccess {
        get { lock.withLock { storedAccess } }
        set { lock.withLock { storedAccess = newValue } }
    }
    var lastError: String?
    private var storedReads: [CheckedContinuation<HealthSummary, Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var reads: [CheckedContinuation<HealthSummary, Never>] { lock.withLock { storedReads } }
    func requestAccess() async -> HealthAccess { access }
    func summary(days: Int) async -> HealthSummary {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                storedReads.append(continuation)
                let ready = waiters.filter { storedReads.count >= $0.0 }.map { $0.1 }
                waiters.removeAll { storedReads.count >= $0.0 }
                return ready
            }
            for waiter in ready { waiter.resume() }
        }
    }
    func waitForRead(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyReady = lock.withLock {
                if storedReads.count >= count { return true }
                waiters.append((count, continuation))
                return false
            }
            if alreadyReady { continuation.resume() }
        }
    }
}
private final class SuspendedInsightPrompts {
    private let lock = NSLock()
    private var storedReads: [CheckedContinuation<[JournalPrompt], Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var reads: [CheckedContinuation<[JournalPrompt], Never>] { lock.withLock { storedReads } }
    func make(_ insight: HealthInsight) async -> [JournalPrompt] {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                storedReads.append(continuation)
                let ready = waiters.filter { storedReads.count >= $0.0 }.map { $0.1 }
                waiters.removeAll { storedReads.count >= $0.0 }
                return ready
            }
            for waiter in ready { waiter.resume() }
        }
    }
    func waitForRead(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyReady = lock.withLock {
                if storedReads.count >= count { return true }
                waiters.append((count, continuation))
                return false
            }
            if alreadyReady { continuation.resume() }
        }
    }
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
}
