import XCTest
@testable import Ate

final class NutritionGoalsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repository: NutritionGoalsRepository!

    override func setUp() {
        super.setUp()
        suiteName = "NutritionGoalsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        repository = NutritionGoalsRepository(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        repository = nil
        super.tearDown()
    }

    func testGoalsRoundTripAndIndependentOptionalValues() throws {
        let expected = DailyNutritionGoals(
            energyKcal: 2_000,
            proteinGrams: 100,
            carbohydratesGrams: nil,
            fatGrams: 65.5,
            fibreGrams: nil
        )
        try repository.save(expected)
        XCTAssertEqual(repository.load(), expected)
    }

    func testSavingEmptyConfigurationClearsPersistedGoals() throws {
        try repository.save(DailyNutritionGoals(
            energyKcal: 2_000, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        ))
        try repository.save(DailyNutritionGoals(
            energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        ))
        XCTAssertNil(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertTrue(repository.load().isEmpty)
    }

    func testValidationRejectsMissingZeroNegativeAndOutOfRangeValues() {
        XCTAssertNotNil(NutritionGoalValidation.error(for: .protein, text: ""))
        XCTAssertNotNil(NutritionGoalValidation.error(for: .protein, text: "0"))
        XCTAssertNotNil(NutritionGoalValidation.error(for: .protein, text: "-1"))
        XCTAssertNotNil(NutritionGoalValidation.error(for: .protein, text: "10001"))
        XCTAssertNotNil(NutritionGoalValidation.error(for: .energy, text: "2000.5"))
        XCTAssertNotNil(NutritionGoalValidation.error(for: .fat, text: "20.55"))
        XCTAssertNotNil(NutritionGoalValidation.error(for: .fibre, text: "NaN"))
    }

    func testValidationAcceptsWholeEnergyAndOneDecimalNutrientValues() {
        XCTAssertNil(NutritionGoalValidation.error(for: .energy, text: "2000"))
        XCTAssertNil(NutritionGoalValidation.error(for: .protein, text: "100"))
        XCTAssertNil(NutritionGoalValidation.error(for: .fat, text: "65.5"))
        XCTAssertNil(NutritionGoalValidation.error(for: .fibre, text: "0.5"))
    }

    func testMalformedStoredDataFallsBackToEmptyGoals() {
        defaults.set(Data("not-json".utf8), forKey: DailyNutritionGoals.defaultsKey)
        XCTAssertTrue(repository.load().isEmpty)
    }
}
