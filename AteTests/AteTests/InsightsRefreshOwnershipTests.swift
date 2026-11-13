import XCTest
@testable import Ate

/// Native UNRUN. No HealthKit, model or widget/default side effects.
private final class SuspendedInsightHealth: HealthKitServicing {
    var access: HealthAccess = .requested
    var lastError: String?
    var reads: [CheckedContinuation<HealthSummary, Never>] = []
    var onRead: (() -> Void)?
    func requestAccess() async -> HealthAccess { access }
    func summary(days: Int) async -> HealthSummary {
        await withCheckedContinuation { continuation in
            reads.append(continuation); onRead?()
        }
    }
    func waitForRead(_ count: Int) async {
        if reads.count >= count { return }
        await withCheckedContinuation { continuation in
            onRead = { [weak self] in
                if let self, self.reads.count >= count { self.onRead = nil; continuation.resume() }
            }
        }
    }
}
private final class SuspendedInsightPrompts {
    var reads: [CheckedContinuation<[JournalPrompt], Never>] = []
    var onRead: (() -> Void)?
    func make(_ insight: HealthInsight) async -> [JournalPrompt] {
        await withCheckedContinuation { continuation in reads.append(continuation); onRead?() }
    }
    func waitForRead(_ count: Int) async {
        if reads.count >= count { return }
        await withCheckedContinuation { continuation in
            onRead = { [weak self] in
                if let self, self.reads.count >= count { self.onRead = nil; continuation.resume() }
            }
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
