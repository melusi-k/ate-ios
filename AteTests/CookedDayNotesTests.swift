import XCTest
@testable import Ate

@MainActor
final class CookedDayNotesTests: XCTestCase {
    private func context(_ event: String, recipe: String = "recipe-1", day: String = "2026-11-14") -> CookedJournalReflectionContext {
        .init(eventID: event, completedAt: Date(timeIntervalSince1970: 1_790_000_000),
              recipeSnapshot: .init(recipeID: recipe, title: "Original dish", cookedDayKey: day))
    }
    func testExistingNoteAppearsUnderMatchingCookedRecipeNotOtherDaysOrRecipes() throws {
        let journal = JournalStore(inMemory: true)
        let service = CookedJournalReflectionStore(journal: journal)
        let id = try service.save(text: "Needs more lemon next time", context: context("first"))
        _ = try service.save(text: "Other day", context: context("other-day", day: "2026-11-13"))
        _ = try service.save(text: "Other dish", context: context("other-recipe", recipe: "recipe-2"))
        let notes = try CookedDayNotes.read(dayKey: "2026-11-14", recipeIDs: ["recipe-1"], journal: journal)
        XCTAssertEqual(notes, [.init(id: id + ":recipe-1", recipeID: "recipe-1", text: "Needs more lemon next time")])
    }
    func testDeletingJournalEntryDeletesItsNoteButKeepsRecordedCook() throws {
        let journal = JournalStore(inMemory: true), service = CookedJournalReflectionStore(journal: journal)
        let suite = "CookedDayNotesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CookingHistory(defaults: defaults), date = Date()
        let day = history.key(for: date)
        history.record(recipeID: "recipe-1", date: date)
        let id = try service.save(text: "Delete this note", context: context("delete", day: day))
        XCTAssertEqual(try CookedDayNotes.read(dayKey: day, recipeIDs: ["recipe-1"], journal: journal).count, 1)
        XCTAssertTrue(journal.deleteReflection(id: id))
        XCTAssertTrue(try CookedDayNotes.read(dayKey: day, recipeIDs: ["recipe-1"], journal: journal).isEmpty)
        XCTAssertTrue(history.recipeIDs(on: date).contains("recipe-1"))
    }
    func testCurrentEditedTextIsReadAndMissingStoreIsNotEmptySuccess() throws {
        let journal = JournalStore(inMemory: true), service = CookedJournalReflectionStore(journal: journal)
        let id = try service.save(text: "Before edit", context: context("edited"))
        let entry = try XCTUnwrap(journal.entry(id))
        XCTAssertTrue(journal.update(entry, text: "After edit"))
        XCTAssertEqual(try CookedDayNotes.read(dayKey: "2026-11-14", recipeIDs: ["recipe-1"], journal: journal).map(\.text), ["After edit"])
        let unavailable = JournalStore(container: nil, openState: .unavailable(error: "test"))
        XCTAssertThrowsError(try CookedDayNotes.read(dayKey: "2026-11-14", recipeIDs: ["recipe-1"], journal: unavailable))
    }
    func testMultipleCookNotesStaySeparateAndReadDoesNotWrite() throws {
        let journal = JournalStore(inMemory: true), service = CookedJournalReflectionStore(journal: journal)
        _ = try service.save(text: "First cook", context: context("first"))
        _ = try service.save(text: "Second cook", context: context("second"))
        let before = try journal.readReflections().count
        let notes = try CookedDayNotes.read(dayKey: "2026-11-14", recipeIDs: ["recipe-1"], journal: journal)
        XCTAssertEqual(Set(notes.map(\.text)), ["First cook", "Second cook"])
        XCTAssertEqual(try journal.readReflections().count, before)
    }
}
