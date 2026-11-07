import XCTest
@testable import Ate

final class CookCompletionTests: XCTestCase {
    private let suiteName = "CookCompletionTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func policy() -> CookReflectionOfferPolicy { CookReflectionOfferPolicy(calendar: cal, defaults: defaults) }
    private func event(_ recipe: String = "r1", id: String? = nil) -> CookCompletionEvent {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        if let id { return CookCompletionEvent(recipeID: recipe, recipeTitle: "Soup", completedAt: t, dayKey: "2027-01-15", id: id) }
        return CookCompletionEvent(recipeID: recipe, recipeTitle: "Soup", completedAt: t, dayKey: "2027-01-15")
    }

    func testVerifiedHistoryReadsBackExactCookAndPreservesPriorDays() throws {
        let history = CookingHistory(calendar: cal, defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let prior = now.addingTimeInterval(-86400)
        try history.recordVerified(recipeID: "before", date: prior, dayKey: history.key(for: prior))
        try history.recordVerified(recipeID: "r1", date: now, dayKey: history.key(for: now))
        try history.recordVerified(recipeID: "r1", date: now, dayKey: history.key(for: now))
        let fresh = CookingHistory(calendar: cal, defaults: defaults)
        XCTAssertEqual(fresh.recipeIDs(on: now), ["r1"])
        XCTAssertEqual(fresh.recipeIDs(on: prior), ["before"])
    }

    func testVerifiedHistoryNeverOverwritesUnreadableBytesOrAcceptsWrongDay() throws {
        let raw = Data("broken history".utf8)
        defaults.set(raw, forKey: "ate.cooking.history.v1")
        let history = CookingHistory(calendar: cal, defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertThrowsError(try history.recordVerified(recipeID: "r1", date: now, dayKey: history.key(for: now)))
        XCTAssertEqual(defaults.data(forKey: "ate.cooking.history.v1"), raw)
        defaults.removeObject(forKey: "ate.cooking.history.v1")
        XCTAssertThrowsError(try history.recordVerified(recipeID: "r1", date: now, dayKey: "1900-01-01"))
        XCTAssertNil(defaults.object(forKey: "ate.cooking.history.v1"))
    }

    // MARK: Event

    func testEventsBuiltWithoutAnIdGetDistinctIds() {
        XCTAssertNotEqual(event().id, event().id)
        XCTAssertTrue(event().id.hasPrefix("cook-"))
    }

    func testEventSnapshotCarriesTitleAndCookedDay() {
        let e = CookCompletionEvent(recipeID: "r1", recipeTitle: "Miso salmon", completedAt: Date(), dayKey: "2027-01-15")
        XCTAssertEqual(e.recipeSnapshot, JournalRecipeSnapshot(recipeID: "r1", title: "Miso salmon", cookedDayKey: "2027-01-15"))
    }

    func testEventSurvivesCodableWithItsIdentity() throws {
        let e = event()
        XCTAssertEqual(try JSONDecoder().decode(CookCompletionEvent.self, from: JSONEncoder().encode(e)), e)
    }

    func testEventAcceptsExtremeDatesWithoutTrapping() {
        let far = CookCompletionEvent(recipeID: "r", recipeTitle: "t", completedAt: .distantFuture, dayKey: "9999-12-31")
        XCTAssertFalse(far.id.isEmpty)
    }

    // MARK: Outbox

    func testOutboxKeepsAFinishUntilAcknowledgedAndAcrossInstances() {
        let a = event(id: "cook-a")
        try! CookCompletionOutbox(defaults: defaults).enqueue(a)
        XCTAssertEqual(try! CookCompletionOutbox(defaults: defaults).load(), [a], "survives a relaunch")
        try! CookCompletionOutbox(defaults: defaults).acknowledge(id: "cook-a")
        XCTAssertEqual(try! CookCompletionOutbox(defaults: defaults).load(), [])
    }

    func testOutboxEnqueueIsIdempotentByIdAndKeepsDistinctCooks() {
        let box = CookCompletionOutbox(defaults: defaults)
        try! box.enqueue(event(id: "cook-a"))
        try! box.enqueue(event(id: "cook-a"))
        try! box.enqueue(event(id: "cook-b"))
        XCTAssertEqual(try! box.load().map(\.id), ["cook-a", "cook-b"])
    }

    func testOutboxAcknowledgeOfUnknownIdChangesNothing() {
        let box = CookCompletionOutbox(defaults: defaults)
        try! box.enqueue(event(id: "cook-a"))
        try! box.acknowledge(id: "nope")
        XCTAssertEqual(try! box.load().map(\.id), ["cook-a"])
    }

    func testUnreadableOutboxIsNeverTreatedAsEmptyAndKeepsItsExactBytes() {
        let bytes = Data("not json".utf8)
        defaults.set(bytes, forKey: CookCompletionOutbox.defaultsKey)
        let box = CookCompletionOutbox(defaults: defaults)
        XCTAssertThrowsError(try box.load()) { XCTAssertEqual($0 as? CookCompletionOutboxError, .unreadable) }
        XCTAssertThrowsError(try box.enqueue(event(id: "cook-new")))
        XCTAssertThrowsError(try box.acknowledge(id: "cook-x"))
        XCTAssertEqual(defaults.data(forKey: CookCompletionOutbox.defaultsKey), bytes, "preserved, not replaced")
    }

    func testUnreadableOutboxCanBeSetAsideWithItsBytesThenAcceptsEvents() throws {
        let bytes = Data("not json".utf8)
        defaults.set(bytes, forKey: CookCompletionOutbox.defaultsKey)
        let box = CookCompletionOutbox(defaults: defaults)
        let key = try XCTUnwrap(try box.setUnreadableAside())
        XCTAssertEqual(defaults.data(forKey: key), bytes, "the original bytes are kept under the returned key")
        try box.enqueue(event(id: "cook-new"))
        XCTAssertEqual(try! box.load().map(\.id), ["cook-new"])
    }

    func testQueueWithDuplicateOrEmptyIdsIsUnreadableAndKeepsItsBytes() throws {
        for events in [[event(id: "cook-a"), event(id: "cook-a")], [event(id: "")]] {
            let bytes = try JSONEncoder().encode(events)
            defaults.set(bytes, forKey: CookCompletionOutbox.defaultsKey)
            let box = CookCompletionOutbox(defaults: defaults)
            XCTAssertThrowsError(try box.load()) { XCTAssertEqual($0 as? CookCompletionOutboxError, .unreadable) }
            XCTAssertThrowsError(try box.enqueue(event(id: "cook-new")))
            XCTAssertThrowsError(try box.acknowledge(id: "cook-a"))
            XCTAssertEqual(defaults.data(forKey: CookCompletionOutbox.defaultsKey), bytes)
        }
    }

    func testEmptyIncomingIdIsRefusedBeforeAnyWriteAndLeavesAHealthyQueueReadable() throws {
        let box = CookCompletionOutbox(defaults: defaults)
        try box.enqueue(event(id: "cook-a"))
        let before = defaults.data(forKey: CookCompletionOutbox.defaultsKey)
        XCTAssertThrowsError(try box.enqueue(event(id: ""))) { XCTAssertEqual($0 as? CookCompletionOutboxError, .invalidEvent) }
        XCTAssertEqual(defaults.data(forKey: CookCompletionOutbox.defaultsKey), before)
        XCTAssertEqual(try box.load().map(\.id), ["cook-a"])
    }

    func testSettingAsideAReadableOutboxDoesNothing() throws {
        let box = CookCompletionOutbox(defaults: defaults)
        try box.enqueue(event(id: "cook-a"))
        XCTAssertNil(try box.setUnreadableAside())
        XCTAssertEqual(try! box.load().map(\.id), ["cook-a"])
    }

    func testRetryWithSameIdReturnsTheFirstStoredEventWholeAndChangesNothing() throws {
        let box = CookCompletionOutbox(defaults: defaults)
        let first = CookCompletionEvent(recipeID: "r1", recipeTitle: "Soup", completedAt: Date(timeIntervalSince1970: 1_800_000_000), dayKey: "2027-01-15", id: "cook-a")
        let retry = CookCompletionEvent(recipeID: "r1", recipeTitle: "Soup v2", completedAt: Date(timeIntervalSince1970: 1_800_090_000), dayKey: "2027-01-16", id: "cook-a")
        XCTAssertEqual(try box.enqueue(first), first)
        XCTAssertEqual(try box.enqueue(retry), first, "midnight retry returns the stored payload")
        XCTAssertEqual(try box.load(), [first], "full equality: title, date and day unchanged")
    }

    // MARK: Offer frequency

    func testOfferIsUsedUpOnlyWhenShownAndThenNotAgainThatDay() {
        let p = policy()
        let morning = cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 9))!
        let evening = cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 20))!
        XCTAssertTrue(p.shouldOffer(on: morning))
        XCTAssertTrue(p.shouldOffer(on: morning), "deciding to offer does not consume the day; showing it does")
        p.markShown(on: morning)
        XCTAssertFalse(p.shouldOffer(on: evening))
    }

    func testOfferReturnsOnTheNextLocalDay() {
        let p = policy()
        p.markShown(on: cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 23, minute: 59))!)
        XCTAssertTrue(p.shouldOffer(on: cal.date(from: DateComponents(year: 2027, month: 1, day: 16, hour: 0, minute: 1))!))
    }

    func testOfferStateSurvivesANewPolicyInstance() {
        let d = cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 12))!
        policy().markShown(on: d)
        XCTAssertFalse(policy().shouldOffer(on: d))
    }

    func testOfferPolicyLeavesStandardDefaultsUntouched() {
        let before = UserDefaults.standard.string(forKey: CookReflectionOfferPolicy.defaultsKey)
        policy().markShown(on: Date())
        XCTAssertEqual(UserDefaults.standard.string(forKey: CookReflectionOfferPolicy.defaultsKey), before)
    }

    // MARK: Finish gate

    func testFinishBeginsOnceAndBlocksFurtherSessionWrites() {
        var s = CookFinishState()
        XCTAssertTrue(s.allowsSessionWrites)
        XCTAssertTrue(s.begin())
        XCTAssertFalse(s.begin())
        XCTAssertFalse(s.allowsSessionWrites)
    }

    // MARK: Draft

    func testPrefillNeverReplacesAnExistingDraft() {
        XCTAssertEqual(CookReflectionDraft.prefill(existing: "", recipeTitle: "Soup"), "Cooked Soup. ")
        XCTAssertEqual(CookReflectionDraft.prefill(existing: "  \n", recipeTitle: "Soup"), "Cooked Soup. ")
        XCTAssertEqual(CookReflectionDraft.prefill(existing: "Dinner was lovely", recipeTitle: "Soup"), "Dinner was lovely")
    }

    // MARK: Recovery

    func testResumeUsesSavedStepWhenNoTimerRuns() {
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: 2, runningTimerStep: nil, stepCount: 5), 2)
    }

    func testRunningTimerStepWinsOverSavedStep() {
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: 1, runningTimerStep: 3, stepCount: 5), 3)
    }

    func testResumeNeverPassesTheLastStepWhenTheRecipeLostSteps() {
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: 7, runningTimerStep: nil, stepCount: 4), 3)
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: 1, runningTimerStep: 9, stepCount: 4), 3)
    }

    func testResumeClampsNegativeAndMissingAndEmpty() {
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: -2, runningTimerStep: nil, stepCount: 3), 0)
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: nil, runningTimerStep: nil, stepCount: 3), 0)
        XCTAssertEqual(CookSessionRecovery.resumeStep(savedStep: 2, runningTimerStep: nil, stepCount: 0), 0)
    }

    func testReconcileKeepsAndClampsAResumableSession() {
        let s = CookSession(recipeID: "r1", stepIndex: 9, factor: 2, checked: [1])
        XCTAssertEqual(CookSessionRecovery.reconcile(session: s, stepCount: 4), .keep(stepIndex: 3))
        XCTAssertEqual(CookSessionRecovery.reconcile(session: CookSession(recipeID: "r1", stepIndex: 1), stepCount: 4), .keep(stepIndex: 1))
    }

    func testReconcileDiscardsASessionWhoseRecipeIsGoneOrHasNoSteps() {
        let s = CookSession(recipeID: "r1", stepIndex: 1)
        XCTAssertEqual(CookSessionRecovery.reconcile(session: s, stepCount: nil), .discard)
        XCTAssertEqual(CookSessionRecovery.reconcile(session: s, stepCount: 0), .discard)
    }
}
