import XCTest
import SwiftData
@testable import Ate

/// The `JournalEntry` shape on main before `recipeSnapshotsRaw` (builds with kindRaw and dayKey, no snapshots),
/// as a NESTED versioned-schema fixture. It is nested on purpose: LegacyJournalStoreUpgradeTests.swift already
/// declares a top-level `JournalEntry` @Model in this test target (target-wide, so it shadows the app type in every
/// test file), and a second top-level one would be a redeclaration. It shares the app's unchanged
/// `JournalMealPayload`. Nothing below assumes the fixture and the app share an entity identity: the test inspects
/// the entity names and then requires the reopen under the app schema to actually find the rows.
enum JournalShapeBeforeSnapshots: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [JournalEntry.self, JournalMealPayload.self] }

    @Model
    final class JournalEntry {
        @Attribute(.unique) var id: String
        var createdAt: Date
        var prompt: String
        var text: String
        var stateRaw: String
        var recipeIDs: [String]
        var journalingSuggestionTitle: String? = nil
        var momentDate: Date? = nil
        var sourceRaw: String = "ate"
        var locationName: String? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var mediaFileNames: [String] = []
        var editedAt: Date? = nil
        var kindRaw: String = "reflection"
        var dayKey: String? = nil
        init(id: String = UUID().uuidString, createdAt: Date = .now, prompt: String, text: String,
             stateRaw: String, recipeIDs: [String] = []) {
            self.id = id; self.createdAt = createdAt; self.prompt = prompt; self.text = text
            self.stateRaw = stateRaw; self.recipeIDs = recipeIDs
        }
    }
}

/// #245 phase 5: a store written with the shape that shipped before `recipeSnapshotsRaw` must reopen under the
/// current app schema with every record intact, and snapshots must then write, save and reopen.
@MainActor
final class JournalCurrentShapeUpgradeTests: XCTestCase {
    private typealias OldEntry = JournalShapeBeforeSnapshots.JournalEntry
    private var dir: URL!
    private var storeURL: URL { dir.appendingPathComponent("journal.store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-current-shape-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    private func appContainer() throws -> ModelContainer {
        try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                           configurations: ModelConfiguration(url: storeURL))
    }

    func testStoreWrittenBeforeSnapshotsReopensIntactAndThenTakesSnapshots() throws {
        let mealID = UUID().uuidString
        let dayReflectionID = UUID().uuidString
        let plainID = UUID().uuidString
        let mealDate = Date(timeIntervalSince1970: 1_790_000_000)
        let reflectionDate = Date(timeIntervalSince1970: 1_790_100_000)

        // Entity identity is inspected, not assumed: the fixture's entity names must equal the app's.
        let fixtureNames = Set(Schema(JournalShapeBeforeSnapshots.models).entities.map(\.name))
        let appNames = Set(Schema([Ate.JournalEntry.self, JournalMealPayload.self]).entities.map(\.name))
        XCTAssertEqual(fixtureNames, appNames, "fixture and app entity names must match for the store to be the same entity")

        do {
            let old = try ModelContainer(for: Schema(versionedSchema: JournalShapeBeforeSnapshots.self),
                                         configurations: ModelConfiguration(url: storeURL))
            let ctx = old.mainContext
            let meal = OldEntry(id: mealID, createdAt: mealDate, prompt: "", text: "",
                                stateRaw: HealthState.balanced.rawValue)
            meal.kindRaw = JournalEntryKind.meal.rawValue
            meal.dayKey = "2026-11-01"
            let dayReflection = OldEntry(id: dayReflectionID, createdAt: reflectionDate, prompt: "Reflect on your day",
                                         text: "Cooked the bean curry", stateRaw: HealthState.performance.rawValue,
                                         recipeIDs: ["recipe-7", "recipe-9"])
            dayReflection.dayKey = "2026-11-02"
            dayReflection.mediaFileNames = ["img-1.jpg"]
            dayReflection.locationName = "Soweto"
            let plain = OldEntry(id: plainID, createdAt: reflectionDate, prompt: "", text: "Plain note",
                                 stateRaw: HealthState.balanced.rawValue)
            [meal, dayReflection, plain].forEach(ctx.insert)
            ctx.insert(JournalMealPayload(entryID: mealID, meal: .dinner, foodName: "Pap and wors", quantity: 250,
                                          quantityUnit: "g", servings: 1.5, source: .userProvided, sourceName: "Label",
                                          sourceIdentifier: "record-42", verificationNote: "cooked",
                                          nutrients: NutritionSnapshot(energyKcal: 320, proteinGrams: nil,
                                                                       carbohydratesGrams: 40, fatGrams: 8, fibreGrams: nil)))
            try ctx.save()
        }

        // Reopen under the CURRENT app schema with a plain `try`; zero rows would mean the entities differ.
        let cooked = JournalRecipeSnapshot(recipeID: "recipe-7", title: "Bean curry", cookedDayKey: "2026-11-02")
        do {
            let current = try appContainer()
            let ctx = current.mainContext
            let rows = try ctx.fetch(FetchDescriptor<Ate.JournalEntry>())
            XCTAssertEqual(rows.count, 3, "the reopen must find every row written with the previous shape")
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            let m = try XCTUnwrap(byID[mealID])
            XCTAssertEqual(m.kind, .meal)
            XCTAssertEqual(m.dayKey, "2026-11-01")
            let r = try XCTUnwrap(byID[dayReflectionID])
            XCTAssertEqual(r.kind, .reflection)
            XCTAssertEqual(r.dayKey, "2026-11-02")
            XCTAssertEqual(r.recipeIDs, ["recipe-7", "recipe-9"])
            XCTAssertEqual(r.text, "Cooked the bean curry")
            XCTAssertEqual(r.stateRaw, HealthState.performance.rawValue)
            XCTAssertEqual(r.mediaFileNames, ["img-1.jpg"])
            XCTAssertEqual(r.locationName, "Soweto")
            let p = try XCTUnwrap(byID[plainID])
            XCTAssertEqual(p.text, "Plain note")
            XCTAssertNil(p.dayKey)
            XCTAssertEqual(p.kind, .reflection)
            for row in rows {
                XCTAssertNil(row.recipeSnapshotsRaw)
                XCTAssertEqual(row.recipeSnapshotDecoding, .none)
            }

            // FoodJournalStore continuity: the meal and its payload still read as the same diary entry.
            let meals = FoodJournalStore(container: current).mealEntries()
            XCTAssertEqual(meals.count, 1)
            let diary = try XCTUnwrap(meals.first)
            XCTAssertEqual(diary.id.uuidString, mealID)
            XCTAssertEqual(diary.foodName, "Pap and wors")
            XCTAssertEqual(diary.dayKey, "2026-11-01")
            XCTAssertEqual(diary.date.timeIntervalSince1970, mealDate.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(diary.nutrientsPerServing.energyKcal, 320)
            XCTAssertNil(diary.nutrientsPerServing.proteinGrams, "unknown nutrient stays unknown")

            // Snapshot write, save.
            XCTAssertTrue(try r.setRecipeSnapshots([cooked]))
            try ctx.save()
        }

        // Reopen again: snapshot persisted, everything else unchanged, meal still continuous.
        let again = try appContainer()
        let rows = try again.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.count, 3)
        let r = try XCTUnwrap(rows.first { $0.id == dayReflectionID })
        XCTAssertEqual(r.recipeSnapshotDecoding, .snapshots([cooked]))
        XCTAssertEqual(r.recipeIDs, ["recipe-7", "recipe-9"])
        XCTAssertEqual(r.dayKey, "2026-11-02")
        XCTAssertEqual(rows.filter { $0.recipeSnapshotsRaw != nil }.count, 1, "only the written row has snapshots")
        XCTAssertEqual(FoodJournalStore(container: again).mealEntries().map { $0.id.uuidString }, [mealID])
    }
}
