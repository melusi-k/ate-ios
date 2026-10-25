import XCTest
@testable import Ate

final class NutritionDiaryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repository: NutritionDiaryRepository!

    override func setUp() {
        super.setUp()
        suiteName = "NutritionDiaryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        repository = NutritionDiaryRepository(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        repository = nil
        super.tearDown()
    }

    func testDiaryRoundTripsEntryDateMealQuantityServingsAndProvenance() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let entry = NutritionDiaryEntry(foodName: "User's meal", date: date, meal: .dinner, quantity: 250,
                                        quantityUnit: "g", servings: 1.5, source: .userProvided,
                                        sourceName: "Label", sourceIdentifier: "record-42", verificationNote: "cooked",
                                        nutrientsPerServing: NutritionSnapshot(energyKcal: 320, proteinGrams: nil,
                                                                               carbohydratesGrams: 40, fatGrams: 8, fibreGrams: nil))
        try repository.save([entry])
        XCTAssertEqual(repository.load(), [entry])
    }

    func testLoggedCalendarDaySurvivesTimeZoneChangesAndPersistence() throws {
        var loggingCalendar = Calendar(identifier: .gregorian)
        loggingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var viewingCalendar = Calendar(identifier: .gregorian)
        viewingCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = loggingCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 23, minute: 30))!
        let loggedDay = NutritionDiaryDayKey.make(date, calendar: loggingCalendar)

        XCTAssertEqual(loggedDay, "2026-01-15")
        XCTAssertEqual(NutritionDiaryDayKey.make(date, calendar: viewingCalendar), "2026-01-16")

        let loggedEntry = NutritionDiaryEntry(foodName: "Late meal", date: date, meal: .dinner, quantity: 1,
                                              quantityUnit: "serving", servings: 1, source: .userProvided,
                                              sourceName: "You", nutrientsPerServing: NutritionSnapshot(
                                                energyKcal: 400, proteinGrams: nil, carbohydratesGrams: nil,
                                                fatGrams: nil, fibreGrams: nil), dayKey: loggedDay)
        try repository.save([loggedEntry])

        let restoredEntry = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(restoredEntry.dayKey, "2026-01-15")
        XCTAssertEqual([restoredEntry].filter { $0.dayKey == "2026-01-15" }.count, 1)
        XCTAssertEqual([restoredEntry].filter { $0.dayKey == "2026-01-16" }.count, 0)

        var legacyRecord = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(loggedEntry)) as? [String: Any])
        legacyRecord.removeValue(forKey: "dayKey")
        defaults.set(try JSONSerialization.data(withJSONObject: [legacyRecord]), forKey: NutritionDiaryRepository.storageKey)
        let migratedEntry = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(migratedEntry.dayKey, NutritionDiaryDayKey.make(date))
        let migratedPayload = try XCTUnwrap(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        let persistedLegacyRecord = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedPayload) as? [[String: Any]])
        XCTAssertNotNil(persistedLegacyRecord.first?["dayKey"])
    }

    func testTotalsScaleByServingsAndKeepUnknownFieldsUnavailable() {
        let entries = [
            entry(servings: 1.5, nutrients: NutritionSnapshot(energyKcal: 100, proteinGrams: 10,
                                                              carbohydratesGrams: nil, fatGrams: 4, fibreGrams: 2)),
            entry(servings: 2, nutrients: NutritionSnapshot(energyKcal: 80, proteinGrams: 8,
                                                            carbohydratesGrams: 20, fatGrams: nil, fibreGrams: 1))
        ]
        let totals = NutritionDayTotals.calculate(entries: entries)
        XCTAssertEqual(totals.value(for: .energy), 310)
        XCTAssertEqual(totals.value(for: .protein), 31)
        XCTAssertNil(totals.value(for: .carbohydrates))
        XCTAssertNil(totals.value(for: .fat))
        XCTAssertEqual(totals.value(for: .fibre), 5)
    }

    func testEmptyDayHasNoFabricatedZeroTotals() {
        XCTAssertTrue(NutritionGoalField.allCases.allSatisfy { NutritionDayTotals.calculate(entries: []).value(for: $0) == nil })
    }

    func testCookingEventIsNotAValidDiaryEntryWithoutExplicitConsumptionDetails() {
        let invalid = NutritionDiaryEntry(foodName: "Dinner", date: .now, meal: .dinner, quantity: 0,
                                          quantityUnit: "serving", servings: 1, source: .userProvided,
                                          sourceName: "You", nutrientsPerServing: NutritionSnapshot(
                                            energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        XCTAssertFalse(NutritionDiaryValidation.isValid(invalid))
    }

    func testSourceNameDefaultsAndValidationStayAlignedWithSelectedSource() {
        XCTAssertEqual(NutritionEntrySource.userProvided.suggestedSourceName, "You")
        XCTAssertEqual(NutritionEntrySource.recipeSnapshot.suggestedSourceName, "Recipe snapshot")
        XCTAssertEqual(NutritionEntrySource.externalFoodRecord.suggestedSourceName, "")

        XCTAssertFalse(NutritionEntrySource.recipeSnapshot.accepts(sourceName: "You"))
        XCTAssertFalse(NutritionEntrySource.externalFoodRecord.accepts(sourceName: "You"))
        XCTAssertFalse(NutritionEntrySource.externalFoodRecord.accepts(sourceName: "  "))
        XCTAssertTrue(NutritionEntrySource.externalFoodRecord.accepts(sourceName: "Food database"))
    }

    func testDiaryDecimalInputUsesTheActiveLocaleSeparator() {
        let commaDecimal = Locale(identifier: "de_DE")
        XCTAssertEqual(NutritionDiaryNumber.parse("1,5", locale: commaDecimal), 1.5)
        XCTAssertEqual(NutritionDiaryNumber.parse("0,75", locale: commaDecimal), 0.75)
        XCTAssertEqual(NutritionDiaryNumber.parse("1.5", locale: commaDecimal), 1.5)
        XCTAssertNil(NutritionDiaryNumber.parse("1,5", locale: Locale(identifier: "en_US")))
        XCTAssertNil(NutritionDiaryNumber.parse("nan", locale: commaDecimal))
    }

    private func entry(servings: Double, nutrients: NutritionSnapshot) -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Food", date: .now, meal: .lunch, quantity: servings,
                            quantityUnit: "serving", servings: servings, source: .userProvided,
                            sourceName: "You", nutrientsPerServing: nutrients)
    }
}
