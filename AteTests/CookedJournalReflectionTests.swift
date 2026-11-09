import XCTest
import SwiftData
@testable import Ate

@MainActor
final class CookedJournalReflectionTests: XCTestCase {
    private func context(id: String = "cook-fixture") -> CookedJournalReflectionContext {
        CookedJournalReflectionContext(eventID: id, completedAt: Date(timeIntervalSince1970: 1_790_000_000),
            recipeSnapshot: JournalRecipeSnapshot(recipeID: "recipe-1", title: "Original pap", cookedDayKey: "2026-10-30"))
    }

    func testOptionalReflectionPreservesCompletionSnapshotWithoutMealOrHealthState() throws {
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal)
        let id = try service.save(text: "  I would cook this again.  ", context: context())
        let row = try XCTUnwrap(journal.entry(id))
        XCTAssertEqual(row.text, "I would cook this again.")
        XCTAssertEqual(row.createdAt, context().completedAt)
        XCTAssertEqual(row.dayKey, "2026-10-30")
        XCTAssertEqual(row.recipeIDs, ["recipe-1"])
        XCTAssertEqual(row.recordedHealthState, nil)
        XCTAssertEqual(row.kindRaw, JournalEntryKind.reflection.rawValue)
        guard case .snapshots(let snapshots) = row.recipeSnapshotDecoding else { return XCTFail("Missing original snapshot") }
        XCTAssertEqual(snapshots, [context().recipeSnapshot])
        XCTAssertTrue(try FoodJournalStore(container: journal.container).readMeals().isEmpty)
    }

    func testRepeatedSaveSameEventReturnsSameIdentityWithoutDuplicate() throws {
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal)
        let first = try service.save(text: "Keep this", context: context())
        XCTAssertEqual(try service.save(text: "Keep this", context: context()), first)
        XCTAssertEqual(try journal.readReflections().count, 1)
    }

    func testConflictingRetryNeverOverwritesSavedReflectionOrSnapshot() throws {
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal)
        let id = try service.save(text: "First note", context: context())
        XCTAssertThrowsError(try service.save(text: "Replacement", context: context())) { error in
            XCTAssertEqual(error as? CookedJournalReflectionError, .conflictingIdentity)
        }
        XCTAssertEqual(journal.entry(id)?.text, "First note")
        XCTAssertEqual(try journal.readReflections().count, 1)
    }

    func testFailureLeavesNoPendingReflectionOrUnrelatedContextRollback() throws {
        enum Failure: Error { case injected }
        let journal = JournalStore(inMemory: true)
        let context = try XCTUnwrap(journal.container).mainContext
        context.autosaveEnabled = false
        let unrelated = Ate.JournalEntry(prompt: "", text: "Unrelated pending edit", state: nil)
        context.insert(unrelated)
        let service = CookedJournalReflectionStore(journal: journal, save: { _ in throw Failure.injected })
        XCTAssertThrowsError(try service.save(text: "Keep my draft", context: self.context()))
        XCTAssertTrue(context.hasChanges)
        try context.save()
        XCTAssertEqual(try journal.readReflections().map(\.id), [unrelated.id])
    }

    func testFallbackCannotSaveDurableCookAndEmptyOrInvalidContextCannotWrite() throws {
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let fallback = JournalStore(container: container, openState: .inMemoryFallback(error: "fixture"))
        XCTAssertThrowsError(try CookedJournalReflectionStore(journal: fallback).save(text: "Note", context: context()))
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal)
        XCTAssertThrowsError(try service.save(text: "  ", context: context()))
        XCTAssertThrowsError(try service.save(text: "Note", context: context(id: "")))
        XCTAssertTrue(try journal.readReflections().isEmpty)
    }
    func testNoOpSaveCannotBeAcknowledgedAsDurableReflection() throws {
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal, save: { _ in })
        XCTAssertThrowsError(try service.save(text: "Keep my draft", context: context())) { error in
            XCTAssertEqual(error as? CookedJournalReflectionError, .verificationFailed)
        }
        XCTAssertTrue(try journal.readReflections().isEmpty)
    }

}
