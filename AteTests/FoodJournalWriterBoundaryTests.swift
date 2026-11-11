import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalWriterBoundaryTests: XCTestCase {
    enum Denied: Error { case stale }

    func testNestedJournalWorkUsesOneOuterAdmission() throws {
        var admissions = 0
        let boundary = FoodJournalWriterBoundary { work in
            admissions += 1
            try work()
        }
        let value = try boundary.withEffect { try boundary.withEffect { 42 } }
        XCTAssertEqual(value, 42)
        XCTAssertEqual(admissions, 1)
        XCTAssertEqual(try boundary.withEffect { 43 }, 43)
        XCTAssertEqual(admissions, 2)
    }

    func testDeniedAdmissionDoesNotRunEffects() {
        var mutations = 0
        let boundary = FoodJournalWriterBoundary { _ in throw Denied.stale }
        XCTAssertThrowsError(try boundary.withEffect { mutations += 1 })
        XCTAssertEqual(mutations, 0)
    }

    func testMissingAndRepeatedCallbacksAreRejected() {
        let missing = FoodJournalWriterBoundary { _ in }
        XCTAssertThrowsError(try missing.withEffect { 42 })
        var mutations = 0
        let repeated = FoodJournalWriterBoundary { work in try work(); try work() }
        XCTAssertThrowsError(try repeated.withEffect { mutations += 1 })
        XCTAssertEqual(mutations, 1)
    }

    func testDeniedReflectionSaveDoesNotInsertOrCallSaveHook() throws {
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var saves = 0
        let journal = JournalStore(container: container, openState: .ok,
            writerBoundary: FoodJournalWriterBoundary { _ in throw Denied.stale },
            writeReflectionContext: { context in saves += 1; try context.save() })
        XCTAssertThrowsError(try journal.saveManual(text: "Keep my bytes safe"))
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
    }

    /// Matches the UI sequence behind JournalOpenStateUITests:233: an edited reflection is
    /// reloaded through history/detail readers before isolated deletion.
    func testEditedReflectionReloadThenDeleteDisappearsFromDiskAndUIReaders() throws {
        let journal = JournalStore(inMemory: true)
        let container = try XCTUnwrap(journal.container)
        let id = try journal.saveManual(text: "Reflection before edit")
        let loadedHistory = try journal.readReflections()
        let retainedRow = try XCTUnwrap(loadedHistory.first { $0.id == id })
        let originalDate = retainedRow.createdAt

        journal.update(retainedRow, text: "Reflection after edit")
        let reloadedHistory = try journal.readReflections()
        let reloadedRow = try XCTUnwrap(reloadedHistory.first { $0.id == id })
        let reloadedDetail = try XCTUnwrap(journal.readEntry(id))
        XCTAssertEqual(reloadedRow.text, "Reflection after edit")
        XCTAssertEqual(reloadedDetail.text, "Reflection after edit")
        XCTAssertEqual(reloadedDetail.createdAt, originalDate)

        XCTAssertTrue(journal.delete(reloadedDetail), "The deletion must report a committed write")
        let diskReader = ModelContext(container)
        diskReader.autosaveEnabled = false
        XCTAssertFalse(try diskReader.fetch(FetchDescriptor<Ate.JournalEntry>()).contains { $0.id == id },
            "An independent context must not find the deleted reflection")
        XCTAssertFalse(try journal.readReflections().contains { $0.id == id },
            "The history reader must not retain an edited row after committed deletion")
        XCTAssertNil(try journal.readEntry(id),
            "The detail reader must agree with the committed deletion")
    }

    func testEditReloadDeleteReadsCommittedStateWithoutTouchingPendingMainContextWork() throws {
        let journal = JournalStore(inMemory: true)
        let container = try XCTUnwrap(journal.container)
        let main = container.mainContext
        main.autosaveEnabled = false
        let unrelatedID = try journal.saveManual(text: "Unrelated committed reflection")
        let unrelated = try XCTUnwrap(try main.fetch(FetchDescriptor<Ate.JournalEntry>())
            .first { $0.id == unrelatedID })
        unrelated.text = "Unrelated pending edit"
        let pending = Ate.JournalEntry(prompt: "", text: "Unrelated pending insertion", state: nil)
        main.insert(pending)

        let id = try journal.saveManual(text: "Target before edit")
        let row = try XCTUnwrap(try journal.readReflections().first { $0.id == id })
        journal.update(row, text: "Target after edit")
        let detail = try XCTUnwrap(journal.readEntry(id))
        XCTAssertEqual(detail.text, "Target after edit")
        XCTAssertEqual(try journal.readReflections().first { $0.id == id }?.text, "Target after edit")
        XCTAssertTrue(journal.delete(detail))
        XCTAssertFalse(try journal.readReflections().contains { $0.id == id || $0.id == pending.id })
        XCTAssertNil(try journal.readEntry(id))
        XCTAssertEqual(try journal.readEntries().map(\.text), ["Unrelated committed reflection"])
        XCTAssertTrue(main.hasChanges, "Reads and target writes must leave unrelated edits pending")
        XCTAssertEqual(unrelated.text, "Unrelated pending edit")
        XCTAssertTrue(try main.fetch(FetchDescriptor<Ate.JournalEntry>()).contains { $0.id == pending.id })

        // Only the explicit owner save may commit those unrelated changes. It must not
        // resurrect the edited-and-deleted target through a dirty retained reader row.
        try main.save()
        let committed = try ModelContext(container).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(Set(committed.map(\.id)), Set([unrelatedID, pending.id]))
        XCTAssertEqual(committed.first { $0.id == unrelatedID }?.text, "Unrelated pending edit")
    }

    func testDeniedMaintenanceOpenDoesNotReturnUsableContainer() {
        let journal = JournalStore(inMemory: true,
            writerBoundary: FoodJournalWriterBoundary { _ in throw Denied.stale })
        XCTAssertNil(journal.container)
        guard case .unavailable = journal.openState else { return XCTFail("denied startup must stay unavailable") }
    }

    func testDeniedOutboxAcknowledgeAndPolicyKeepOriginalBytes() throws {
        let suite = "JournalWriterOutbox-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let event = CookCompletionEvent(recipeID: "recipe", recipeTitle: "Dinner", completedAt: Date(timeIntervalSince1970: 1_800_000_000), dayKey: "2027-01-15", id: "retained-cook")
        let raw = try JSONEncoder().encode([event])
        defaults.set(raw, forKey: CookCompletionOutbox.defaultsKey)
        defaults.set("retained-day", forKey: CookReflectionOfferPolicy.defaultsKey)
        let denied = FoodJournalWriterBoundary { _ in throw Denied.stale }
        let outbox = CookCompletionOutbox(defaults: defaults, writerBoundary: denied)
        XCTAssertThrowsError(try outbox.acknowledge(id: event.id))
        XCTAssertEqual(defaults.data(forKey: CookCompletionOutbox.defaultsKey), raw)
        CookReflectionOfferPolicy(defaults: defaults, writerBoundary: denied).markShown(on: .now)
        XCTAssertEqual(defaults.string(forKey: CookReflectionOfferPolicy.defaultsKey), "retained-day")
    }

    func testDeniedGoalsLoadDoesNotRetireLegacyGoals() throws {
        let suite = "JournalWriterGoals-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))
        let raw = Data("{\"energyKcal\":2000}".utf8)
        defaults.set(raw, forKey: DailyNutritionGoals.defaultsKey)
        let goals = NutritionGoalsRepository(defaults: defaults, storage: storage,
            writerBoundary: FoodJournalWriterBoundary { _ in throw Denied.stale })
        XCTAssertThrowsError(try goals.load())
        XCTAssertEqual(defaults.data(forKey: DailyNutritionGoals.defaultsKey), raw)
        XCTAssertNil(try storage.read())
    }

    func testDeniedCoordinatorReadCannotMigrateOrRetireLegacyBytes() throws {
        let suite = "JournalWriterMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let raw = Data("[]".utf8)
        defaults.set(raw, forKey: "ate.nutritionDiary.v1")
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let journal = JournalStore(container: container, openState: .ok)
        let coordinator = FoodJournalCoordinator(journal: journal,
            legacy: NutritionDiaryRepository(defaults: defaults),
            writerBoundary: FoodJournalWriterBoundary { _ in throw Denied.stale },
            markerDefaults: defaults)
        XCTAssertThrowsError(try coordinator.readMeals())
        XCTAssertEqual(defaults.data(forKey: "ate.nutritionDiary.v1"), raw)
        XCTAssertNil(defaults.object(forKey: "ate.foodJournal.diaryMigration.v1"))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
    }
}
