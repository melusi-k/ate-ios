import XCTest
@testable import Ate

@MainActor
final class CookedJournalReflectionSessionTests: XCTestCase {
    private func event() -> CookCompletionEvent {
        CookCompletionEvent(recipeID: "recipe", recipeTitle: "Original pap", completedAt: Date(timeIntervalSince1970: 1_790_000_000),
                            dayKey: "2026-10-30", id: "cook-retained")
    }

    func testVerifiedSaveAcknowledgesOnlyCapturedCookAndKeepsOriginalSnapshot() throws {
        let name = "cook-session-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let box = CookCompletionOutbox(defaults: defaults)
        let captured = try box.enqueue(event())
        let other = CookCompletionEvent(recipeID: "other", recipeTitle: "Other", completedAt: Date(), dayKey: "2026-11-05", id: "cook-other")
        try box.enqueue(other)
        let journal = JournalStore(inMemory: true)
        let session = CookedJournalReflectionSession(event: captured, reflections: CookedJournalReflectionStore(journal: journal), outbox: box, existingDraft: "My retained draft")
        XCTAssertTrue(session.save())
        XCTAssertEqual(try box.load(), [other])
        XCTAssertTrue(session.draft.isEmpty)
        let rows = try journal.readReflections()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.text, "My retained draft")
        XCTAssertEqual(rows.first?.createdAt, captured.completedAt)
        XCTAssertEqual(rows.first?.dayKey, captured.cookedDayKey)
        XCTAssertTrue(session.save())
        XCTAssertEqual(try journal.readReflections().count, 1)
    }

    func testUnconfirmedSaveKeepsDraftAndExactQueuedEvent() throws {
        let name = "cook-session-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let box = CookCompletionOutbox(defaults: defaults)
        let captured = try box.enqueue(event())
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal, save: { _ in })
        let session = CookedJournalReflectionSession(event: captured, reflections: service, outbox: box, existingDraft: "Keep this")
        XCTAssertFalse(session.save())
        XCTAssertEqual(session.draft, "Keep this")
        XCTAssertEqual(session.event, captured)
        XCTAssertEqual(try box.load(), [captured])
        XCTAssertNotNil(session.problem)
        XCTAssertFalse(session.isSaved)
    }

    func testChangedQueuedPayloadCannotWriteOrAcknowledge() throws {
        let name = "cook-session-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let box = CookCompletionOutbox(defaults: defaults)
        let captured = try box.enqueue(event())
        let journal = JournalStore(inMemory: true)
        let session = CookedJournalReflectionSession(event: captured, reflections: CookedJournalReflectionStore(journal: journal), outbox: box, existingDraft: "Keep this")
        try box.acknowledge(id: captured.id)
        let replacement = CookCompletionEvent(recipeID: "changed", recipeTitle: "Changed", completedAt: captured.completedAt, dayKey: captured.cookedDayKey, id: captured.id)
        try box.enqueue(replacement)
        XCTAssertFalse(session.save())
        XCTAssertEqual(try box.load(), [replacement])
        XCTAssertTrue(try journal.readReflections().isEmpty)
        XCTAssertEqual(session.draft, "Keep this")
    }
    func testAcknowledgementThrowsAfterRemovalCanRetryVerifiedReflectionAndQueueAbsence() throws {
        let name = "cook-session-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let box = CookCompletionOutbox(defaults: defaults)
        let captured = try box.enqueue(event())
        let journal = JournalStore(inMemory: true)
        let session = CookedJournalReflectionSession(event: captured, reflections: CookedJournalReflectionStore(journal: journal),
            outbox: box, existingDraft: "Retained note", acknowledge: { id in
                try box.acknowledge(id: id)
                throw CookCompletionOutboxError.verifyFailed
            })
        XCTAssertFalse(session.save())
        XCTAssertEqual(session.draft, "Retained note")
        XCTAssertTrue(try box.load().isEmpty)
        XCTAssertEqual(try journal.readReflections().count, 1)
        XCTAssertTrue(session.save())
        XCTAssertTrue(session.isSaved)
        XCTAssertEqual(try journal.readReflections().count, 1)
    }

    func testAcknowledgementPendingDoesNotClearAnEditedDraft() throws {
        let name = "cook-session-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let box = CookCompletionOutbox(defaults: defaults)
        let captured = try box.enqueue(event())
        let journal = JournalStore(inMemory: true)
        let session = CookedJournalReflectionSession(event: captured, reflections: CookedJournalReflectionStore(journal: journal),
            outbox: box, existingDraft: "Original note", acknowledge: { _ in throw CookCompletionOutboxError.verifyFailed })
        XCTAssertFalse(session.save())
        XCTAssertTrue(session.isAcknowledgementPending)
        session.draft = "Do not erase this edit"
        XCTAssertFalse(session.save())
        XCTAssertEqual(session.draft, "Do not erase this edit")
        XCTAssertEqual(try box.load(), [captured])
        XCTAssertEqual(try journal.readReflections().first?.text, "Original note")
    }

    func testRuntimeUsesItsOwnOutboxAndActualJournalForPendingSessions() throws {
        let name = "cook-runtime-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let journal = JournalStore(inMemory: true)
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathComponent("goals.json")))
        let runtime = FoodJournalRuntime(journal: journal, goalsRepository: goals, defaults: defaults)
        let captured = try runtime.cookOutbox.enqueue(event())
        XCTAssertEqual(try runtime.pendingCookReflections(), [captured])
        let session = try runtime.reflectionSession(for: captured.id, existingDraft: "Runtime note")
        XCTAssertTrue(session.save())
        XCTAssertTrue(try runtime.pendingCookReflections().isEmpty)
        XCTAssertEqual(try journal.readReflections().first?.text, "Runtime note")
        XCTAssertThrowsError(try runtime.reflectionSession(for: "missing"))
    }

    func testHostRetainedAckPendingSessionRemainsAvailableWithoutQueueAndWaitsForModal() throws {
        let name = "cook-host-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let settings = UserDefaults.standard.object(forKey: "ate.settings.v1")
        let timers = UserDefaults.standard.object(forKey: "ate.timerprefs.v1")
        defer {
            defaults.removePersistentDomain(forName: name)
            if let settings { UserDefaults.standard.set(settings, forKey: "ate.settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.settings.v1") }
            if let timers { UserDefaults.standard.set(timers, forKey: "ate.timerprefs.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.timerprefs.v1") }
        }
        let journal = JournalStore(inMemory: true)
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathComponent("goals.json")))
        let runtime = FoodJournalRuntime(journal: journal, goalsRepository: goals, defaults: defaults)
        let captured = try runtime.cookOutbox.enqueue(event())
        let session = CookedJournalReflectionSession(event: captured, reflections: CookedJournalReflectionStore(journal: journal),
            outbox: runtime.cookOutbox, existingDraft: "Keep later", acknowledge: { id in
                try runtime.cookOutbox.acknowledge(id: id)
                throw CookCompletionOutboxError.verifyFailed
            })
        XCTAssertFalse(session.save())
        let store = AppStore(context: nil, backend: MockBackend(), foodJournalRuntime: runtime)
        // This fixture exercises modal admission after onboarding has finished.
        // Do not inherit a hosted unit-test process's real onboarding preference.
        store.showOnboarding = false
        store.cookedReflectionSessions[captured.id] = session
        XCTAssertEqual(store.availableCookedReflections(queued: try runtime.pendingCookReflections()), [captured])
        store.cookJournalModalDismissing = true
        store.requestCookedReflection(captured)
        store.presentPendingCookedReflection()
        XCTAssertNil(store.cookedReflectionPresentedID)
        XCTAssertEqual(store.cookedReflectionPendingID, captured.id)
        store.cookJournalModalDismissing = false
        store.presentPendingCookedReflection()
        XCTAssertEqual(store.cookedReflectionPresentedID, captured.id)
        store.cookedReflectionPresentedID = nil
        XCTAssertEqual(store.availableCookedReflections(queued: []), [captured])
        store.requestCookedReflection(captured)
        store.presentPendingCookedReflection()
        XCTAssertTrue(store.cookedReflectionSessions[captured.id] === session)
        XCTAssertTrue(session.save())
    }

}
