import XCTest
import SwiftData
@testable import Ate

@MainActor
final class ManualJournalTests: XCTestCase {
    private func container(at url: URL? = nil) throws -> ModelContainer {
        let configuration = url.map { ModelConfiguration(url: $0) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                  configurations: configuration)
    }

    func testManualSaveHasNoInventedHealthStateAndRoundTripsOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("journal.store")
        let id: String
        do {
            let c = try container(at: url)
            let store = JournalStore(container: c, openState: .ok)
            id = try store.saveManual(text: "  Lentil supper\n")
            let saved = try XCTUnwrap(store.entry(id))
            XCTAssertEqual(saved.text, "Lentil supper")
            XCTAssertEqual(saved.stateRaw, "")
            XCTAssertNil(saved.recordedHealthState)
            XCTAssertEqual(saved.kind, .reflection)
            XCTAssertEqual(saved.prompt, "")
            XCTAssertTrue(saved.recipeIDs.isEmpty)
        }
        let reopened = try container(at: url)
        let row = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>()).first)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.text, "Lentil supper")
        XCTAssertEqual(row.stateRaw, "")
        XCTAssertNil(row.recordedHealthState)
    }

    func testWhitespaceCannotCreateAnEntry() throws {
        let c = try container()
        let store = JournalStore(container: c, openState: .ok)
        XCTAssertThrowsError(try store.saveManual(text: " \n\t"))
        XCTAssertTrue(store.entries().isEmpty)
    }

    func testOnlyUnavailableRefusesWhileFallbackAndRecoveredSave() throws {
        let c = try container()
        let unavailable = JournalStore(container: c, openState: .unavailable(error: nil))
        XCTAssertThrowsError(try unavailable.saveManual(text: "Keep this draft")) { error in
            XCTAssertEqual(error as? ManualJournalSaveError, .unavailable)
        }
        XCTAssertFalse(unavailable.save(prompt: "Health prompt", text: "Keep the Health draft", state: .recovery,
                                        recipeIDs: [], momentTitle: "Generic moment", momentDate: .distantPast))
        XCTAssertTrue(unavailable.entries().isEmpty)

        // Temporary in-memory fallback: both paths keep accepting writes for this session (the banner
        // carries the temporary-storage truth; no durability is claimed here).
        let fallback = JournalStore(container: c, openState: .inMemoryFallback(error: nil))
        XCTAssertNoThrow(try fallback.saveManual(text: "A session reflection"))
        XCTAssertTrue(fallback.save(prompt: "Health prompt", text: "A Health reflection", state: .recovery, recipeIDs: []))
        XCTAssertEqual(fallback.entries().count, 2)

        let recovered = JournalStore(container: c, openState: .recovered(backupName: "kept.store"))
        XCTAssertNoThrow(try recovered.saveManual(text: "A new reflection"))
        XCTAssertEqual(recovered.entries().count, 3)
    }

    func testManualWriteDoesNotCommitUnrelatedPendingMainContextEdits() throws {
        let c = try container()
        let unrelated = Ate.JournalEntry(prompt: "", text: "Unsaved unrelated edit", state: .recovery)
        c.mainContext.insert(unrelated)
        let store = JournalStore(container: c, openState: .ok)
        let id = try store.saveManual(text: "Manual reflection")
        XCTAssertTrue(c.mainContext.hasChanges)
        let reader = ModelContext(c)
        let rows = try reader.fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.map(\.id), [id])
        XCTAssertEqual(unrelated.text, "Unsaved unrelated edit")
    }

    func testWriteFailureLeavesNoOrphanAndDoesNotDiscardPendingMainEdits() throws {
        enum InjectedFailure: Error { case write }
        let c = try container()
        let unrelated = Ate.JournalEntry(prompt: "", text: "Unrelated pending", state: .recovery)
        c.mainContext.insert(unrelated)
        let failing = JournalStore(container: c, openState: .ok,
                                   writeReflectionContext: { _ in throw InjectedFailure.write })
        XCTAssertThrowsError(try failing.saveManual(text: "Keep this draft"))
        XCTAssertTrue(c.mainContext.hasChanges)
        XCTAssertEqual(unrelated.text, "Unrelated pending")
        let independent = ModelContext(c)
        XCTAssertTrue(try independent.fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
        let succeeding = JournalStore(container: c, openState: .ok)
        let id = try succeeding.saveManual(text: "Retry reflection")
        XCTAssertEqual(try independent.fetch(FetchDescriptor<Ate.JournalEntry>()).map(\.id), [id])
    }

    func testHealthReflectionSaveVisibleImmediatelyAndFailureDoesNotLeaveEntry() throws {
        let c = try container()
        let store = JournalStore(container: c, openState: .ok)
        XCTAssertTrue(store.save(prompt: "Health prompt", text: "Health reflection", state: .recovery,
                                 recipeIDs: ["recipe-fixture"], momentTitle: "Generic dinner", momentDate: .distantPast))
        let row = try XCTUnwrap(store.entries().first)
        XCTAssertEqual(row.recordedHealthState, .recovery)
        XCTAssertEqual(row.journalingSuggestionTitle, "Generic dinner")
        XCTAssertEqual(row.recipeIDs, ["recipe-fixture"])
        enum InjectedFailure: Error { case write }
        let failing = JournalStore(container: c, openState: .ok,
                                   writeReflectionContext: { _ in throw InjectedFailure.write })
        XCTAssertFalse(failing.save(prompt: "Keep prompt", text: "Failed reflection", state: .lowEnergy,
                                   recipeIDs: []))
        XCTAssertEqual(store.entries().map(\.id), [row.id])
    }

    func testKnownLegacyAndUnknownRawStatesArePreserved() {
        let row = Ate.JournalEntry(prompt: "", text: "Existing reflection", state: .performance)
        XCTAssertEqual(row.recordedHealthState, .performance)
        XCTAssertTrue(row.datedStateLabel.contains(HealthState.performance.title))
        row.stateRaw = "future-unknown-state"
        XCTAssertNil(row.recordedHealthState)
        XCTAssertEqual(row.stateRaw, "future-unknown-state")
        XCTAssertEqual(row.state, .balanced, "legacy fallback unchanged for old callers")
        row.stateRaw = ""
        XCTAssertNil(row.recordedHealthState)
        XCTAssertFalse(row.datedStateLabel.contains(HealthState.balanced.title))
    }
    func testRootReflectionWithoutHealthKeepsMomentAndNoInventedReading() throws {
        let c = try container()
        let journal = JournalStore(container: c, openState: .ok)
        let draft = JournalReflectionDraft()
        draft.text = "A quiet supper"
        draft.prompt = JournalPrompt(text: "What did you enjoy?", state: .balanced)
        draft.pendingMoment = ("Dinner with friends", .distantPast)
        XCTAssertTrue(draft.save(context: nil, journal: journal))
        let row = try XCTUnwrap(journal.entries().first)
        XCTAssertEqual(row.prompt, "What did you enjoy?")
        XCTAssertEqual(row.journalingSuggestionTitle, "Dinner with friends")
        XCTAssertEqual(row.momentDate, .distantPast)
        XCTAssertNil(row.recordedHealthState)
        XCTAssertEqual(row.stateRaw, "")
        XCTAssertTrue(row.recipeIDs.isEmpty)
        XCTAssertEqual(draft.text, "")
        XCTAssertNil(draft.pendingMoment)
        XCTAssertNil(draft.prompt)
        XCTAssertNil(draft.saveError)
        // A second plain reflection cannot inherit the prior moment's metadata or prompt.
        draft.text = "Ordinary reflection after the moment"
        XCTAssertTrue(draft.save(context: nil, journal: journal))
        let ordinary = try XCTUnwrap(journal.entries().first { $0.text == "Ordinary reflection after the moment" })
        XCTAssertEqual(ordinary.prompt, "")
        XCTAssertNil(ordinary.journalingSuggestionTitle)
        XCTAssertNil(ordinary.momentDate)
        XCTAssertNil(ordinary.recordedHealthState)
        XCTAssertEqual(ordinary.stateRaw, "")
        XCTAssertTrue(ordinary.recipeIDs.isEmpty)
        XCTAssertEqual(ordinary.source, .ate)
    }

    func testRootReflectionFailureRetainsDraftPromptAndMoment() throws {
        let draft = JournalReflectionDraft()
        draft.text = "Keep my words"
        draft.prompt = JournalPrompt(text: "Keep prompt", state: .recovery)
        draft.pendingMoment = ("A moment", .distantPast)
        let journal = JournalStore(container: try container(), openState: .unavailable(error: nil))
        XCTAssertFalse(draft.save(context: nil, journal: journal))
        XCTAssertEqual(draft.text, "Keep my words")
        XCTAssertEqual(draft.prompt?.text, "Keep prompt")
        XCTAssertEqual(draft.pendingMoment?.title, "A moment")
        XCTAssertNotNil(draft.saveError)
        XCTAssertTrue(journal.entries().isEmpty)
    }

    func testJournalMomentRecipeDraftDoesNotEnableHealthSuggestionEvidence() {
        let target = JournalReflectionCard.momentRecipeTarget(id: "moment-recipe-draft")
        XCTAssertEqual(target.id, "moment-recipe-draft")
        XCTAssertFalse(target.recordsHealthSuggestionEvidence,
                       "A Journal moment is not an Apple Health meal suggestion")
        let sheet = JournalReflectionCard.momentRecipeSheet(target)
        XCTAssertEqual(sheet.recipeID, target.id)
        XCTAssertFalse(sheet.recordsHealthSuggestionEvidence,
                       "The sheet disappearance must not record A-HEALTH-08 for a Journal draft")
        let healthTarget = RecipeSheetTarget(id: "actual-health-suggestion")
        XCTAssertTrue(healthTarget.recordsHealthSuggestionEvidence,
                      "The actual Health suggestion default remains unchanged")
        XCTAssertTrue(RecipeSheet(recipeID: healthTarget.id).recordsHealthSuggestionEvidence)
    }

}
