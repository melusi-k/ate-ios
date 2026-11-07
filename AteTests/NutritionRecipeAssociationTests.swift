import XCTest
@testable import Ate

/// #179 recipe association and frequent-food reuse. Links are durable, snapshot the recipe
/// name, never touch entry nutrients or the legacy diary payload, and an unreadable link store
/// reports unavailable instead of pretending empty. Frequent foods come only from the diary's
/// own local entries and never carry verification into a new entry.
@MainActor
final class NutritionRecipeAssociationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var backup: URL!
    private var repository: NutritionDiaryRepository!
    private var repair: LegacyDiaryRepair!
    private var coordinator: FoodJournalCoordinator!
    private var linkStore: NutritionRecipeAssociationStore!

    override func setUp() async throws {
        try await super.setUp()
        suite = "NutritionRecipeAssociationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        backup = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        repository = NutritionDiaryRepository(defaults: defaults, backupDirectory: backup)
        repair = LegacyDiaryRepair(repository: repository, backupDirectory: backup)
        coordinator = FoodJournalCoordinator(journal: JournalStore(inMemory: true),
                                             legacy: repository,
                                             markerDefaults: defaults,
                                             backupDirectory: backup)
        linkStore = NutritionRecipeAssociationStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: backup)
        defaults = nil
        repository = nil
        repair = nil
        coordinator = nil
        linkStore = nil
        try await super.tearDown()
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeController() -> NutritionDiaryController {
        NutritionDiaryController(coordinator: coordinator,
                                 goalsRepository: NutritionGoalsRepository(defaults: defaults),
                                 repair: repair,
                                 associationStore: linkStore,
                                 selectedDayKey: "2026-11-04",
                                 calendar: testCalendar)
    }

    private func makeEntry(id: UUID = UUID(), foodName: String = "Pap", dayKey: String = "2026-11-04",
                           date: Date = Date(timeIntervalSince1970: 1_800_000_000),
                           quantity: Double = 1, servings: Double = 1,
                           energy: Double? = 200, protein: Double? = 10,
                           source: NutritionEntrySource = .userProvided,
                           sourceIdentifier: String = "", verificationNote: String = "") -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: foodName, date: date, meal: .lunch, quantity: quantity,
                            quantityUnit: "portion", servings: servings, source: source,
                            sourceName: "You", sourceIdentifier: sourceIdentifier,
                            verificationNote: verificationNote,
                            nutrientsPerServing: NutritionSnapshot(energyKcal: energy, proteinGrams: protein,
                                                                   carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
                            dayKey: dayKey)
    }

    func testLinkRoundTripsAcrossStoreInstances() throws {
        let entryID = UUID()
        try linkStore.associate(entryID: entryID, recipeID: "recipe-1", recipeName: "Miso salmon",
                                at: Date(timeIntervalSince1970: 1_800_100_000))
        let reloaded = NutritionRecipeAssociationStore(defaults: defaults)
        let link = try XCTUnwrap(reloaded.association(forEntryID: entryID.uuidString))
        XCTAssertEqual(link.recipeID, "recipe-1")
        XCTAssertEqual(link.recipeName, "Miso salmon")
        XCTAssertEqual(link.linkedAt, Date(timeIntervalSince1970: 1_800_100_000))
    }

    func testLinkKeepsRecipeNameSnapshotIndependentOfLaterRecipeChanges() throws {
        let entryID = UUID()
        try linkStore.associate(entryID: entryID, recipeID: "recipe-1", recipeName: "Miso salmon")
        // The store holds no recipe reference; a later rename or deletion cannot reach the
        // snapshot the diary shows.
        let link = try XCTUnwrap(linkStore.association(forEntryID: entryID.uuidString))
        XCTAssertEqual(link.recipeName, "Miso salmon")
        XCTAssertEqual(link.recipeID, "recipe-1")
    }

    func testRelinkReplacesPreviousLinkForSameEntryOnly() throws {
        let first = UUID()
        let second = UUID()
        try linkStore.associate(entryID: first, recipeID: "r1", recipeName: "Old recipe")
        try linkStore.associate(entryID: second, recipeID: "r2", recipeName: "Other entry recipe")
        try linkStore.associate(entryID: first, recipeID: "r3", recipeName: "New recipe")
        XCTAssertEqual(linkStore.association(forEntryID: first.uuidString)?.recipeName, "New recipe")
        XCTAssertEqual(linkStore.association(forEntryID: second.uuidString)?.recipeName, "Other entry recipe")
        XCTAssertEqual(linkStore.associations().count, 2)
    }

    func testDissociateRemovesOnlyThatEntryLink() throws {
        let first = UUID()
        let second = UUID()
        try linkStore.associate(entryID: first, recipeID: "r1", recipeName: "One")
        try linkStore.associate(entryID: second, recipeID: "r2", recipeName: "Two")
        try linkStore.dissociate(entryID: first)
        XCTAssertNil(linkStore.association(forEntryID: first.uuidString))
        XCTAssertNotNil(linkStore.association(forEntryID: second.uuidString))
    }

    func testCorruptLinkStoreReportsUnavailableAndRefusesOverwrite() throws {
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: NutritionRecipeAssociationStore.storageKey)
        XCTAssertEqual(linkStore.loadState(), .corrupt)
        XCTAssertEqual(linkStore.associations(), [])
        XCTAssertThrowsError(try linkStore.associate(entryID: UUID(), recipeID: "r1", recipeName: "X")) { error in
            XCTAssertEqual(error as? NutritionRecipeAssociationError, .storeUnreadable)
            // The failure is human-readable with the correct cause, never a raw enum dump.
            XCTAssertTrue(error.localizedDescription.contains("couldn't be read"))
        }
        // The only copy of the unreadable payload is never destroyed implicitly.
        XCTAssertEqual(defaults.data(forKey: NutritionRecipeAssociationStore.storageKey), garbage)
    }

    func testPruneOrphansKeepsOnlyLiveEntries() throws {
        let live = UUID()
        let gone = UUID()
        try linkStore.associate(entryID: live, recipeID: "r1", recipeName: "Kept")
        try linkStore.associate(entryID: gone, recipeID: "r2", recipeName: "Orphaned")
        try linkStore.pruneOrphans(keepingEntryIDs: [live.uuidString])
        XCTAssertNotNil(linkStore.association(forEntryID: live.uuidString))
        XCTAssertNil(linkStore.association(forEntryID: gone.uuidString))
    }

    func testFrequentFoodsCountsLocalEntriesAndPrefersMostRecentValues() {
        let entries = [
            makeEntry(foodName: "Pap", dayKey: "2026-11-01", date: Date(timeIntervalSince1970: 1_800_000_000), energy: 200),
            makeEntry(foodName: " pap ", dayKey: "2026-11-03", date: Date(timeIntervalSince1970: 1_800_100_000), energy: 250),
            makeEntry(foodName: "Rice", dayKey: "2026-11-02", date: Date(timeIntervalSince1970: 1_800_050_000), energy: 300)
        ]
        let foods = NutritionFrequentFoods.topFoods(in: entries)
        XCTAssertEqual(foods.count, 2)
        // Display/prefill names are trimmed for presentation; the stored entries keep exactly
        // what was typed.
        XCTAssertEqual(foods[0].foodName, "pap")
        XCTAssertEqual(foods[0].timesLogged, 2)
        XCTAssertEqual(entries[1].foodName, " pap ")
        XCTAssertEqual(NutritionFrequentFoods.draft(from: foods[0], dayKey: "2026-11-04").foodName, "pap")
        // Values come from the most recent entry; unknowns stay unknown, never zero.
        XCTAssertEqual(foods[0].nutrientsPerServing.energyKcal, 250)
        XCTAssertNil(foods[0].nutrientsPerServing.carbohydratesGrams)
        XCTAssertEqual(foods[1].foodName, "Rice")
        XCTAssertEqual(foods[1].timesLogged, 1)
    }

    func testFrequentDraftNeverCarriesVerificationOrExternalProvenance() {
        let prior = makeEntry(foodName: "Pap", quantity: 2, servings: 1.5, energy: 200,
                              source: .externalFoodRecord, sourceIdentifier: "ext-99",
                              verificationNote: "From a label photo")
        let food = NutritionFrequentFoods.topFoods(in: [prior])[0]
        let draft = NutritionFrequentFoods.draft(from: food, dayKey: "2026-11-05")
        XCTAssertEqual(draft.foodName, "Pap")
        XCTAssertEqual(draft.quantity, "2")
        XCTAssertEqual(draft.servings, "1.5")
        XCTAssertEqual(draft.nutrientText[.energy], "200")
        XCTAssertEqual(draft.dayKey, "2026-11-05")
        // A repeated entry is the person's own entry again: no external source, no verification.
        XCTAssertEqual(draft.source, .userProvided)
        XCTAssertEqual(draft.sourceIdentifier, "")
        XCTAssertEqual(draft.verificationNote, "")
    }

    func testControllerLinksEntryAndDeleteDropsLinkWhileDiaryKeepsWorking() throws {
        let controller = makeController()
        let entry = makeEntry()
        try controller.add(entry)
        try controller.associate(entry: entry, recipe: RecipeCard(id: "r1", title: "Miso salmon"))
        XCTAssertEqual(controller.association(for: entry)?.recipeName, "Miso salmon")
        try controller.delete(id: entry.id)
        XCTAssertNil(controller.association(for: entry))
        XCTAssertTrue(controller.dayEntries.isEmpty)
        XCTAssertNil(controller.issue)
        XCTAssertFalse(controller.associationsUnreadable)

        // An unwired controller refuses with its own cause - not mislabeled "unreadable" -
        // and the refusal is human-readable.
        let unwired = NutritionDiaryController(coordinator: coordinator,
                                               goalsRepository: NutritionGoalsRepository(defaults: defaults),
                                               repair: repair, selectedDayKey: "2026-11-04",
                                               calendar: testCalendar)
        XCTAssertThrowsError(try unwired.associate(entry: entry, recipe: RecipeCard(id: "r1", title: "Miso salmon"))) { error in
            XCTAssertEqual(error as? NutritionRecipeAssociationError, .storeNotWired)
            XCTAssertTrue(error.localizedDescription.contains("isn't available"))
        }
        XCTAssertThrowsError(try unwired.dissociate(entry: entry)) { error in
            XCTAssertEqual(error as? NutritionRecipeAssociationError, .storeNotWired)
        }
    }

    func testControllerReloadNeverPrunesLinksAgainstPossiblyPartialEntrySet() throws {
        // A link whose entry is not currently loaded must survive reloads: pruning against the
        // current entry set could destroy links belonging to entries outside it.
        let unlinked = UUID()
        try linkStore.associate(entryID: unlinked, recipeID: "r9", recipeName: "Not in this load")
        let controller = makeController()
        controller.reload()
        XCTAssertNotNil(linkStore.association(forEntryID: unlinked.uuidString))
        XCTAssertFalse(controller.associationsUnreadable)
        // Explicit prune remains available and owner-scoped for a deliberate cleanup only.
        try linkStore.pruneOrphans(keepingEntryIDs: [])
        XCTAssertNil(linkStore.association(forEntryID: unlinked.uuidString))
    }
}
