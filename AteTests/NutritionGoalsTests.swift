import XCTest
@testable import Ate

final class NutritionGoalsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repository: NutritionGoalsRepository!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "NutritionGoalsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        repository = NutritionGoalsRepository(defaults: defaults, storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json")))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        repository = nil
        super.tearDown()
    }

    func testGoalsRoundTripAndIndependentOptionalValues() throws {
        let expected = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: 100,
                                            carbohydratesGrams: nil, fatGrams: 65.5, fibreGrams: nil)
        try repository.save(expected)
        XCTAssertEqual(repository.load(), expected)
    }

    func testSavingEmptyConfigurationClearsPersistedGoals() throws {
        try repository.save(DailyNutritionGoals(energyKcal: 2_000, proteinGrams: nil,
                                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        try repository.save(DailyNutritionGoals(energyKcal: nil, proteinGrams: nil,
                                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        XCTAssertNil(try FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json")).read())
        XCTAssertTrue(repository.load().isEmpty)
    }

    func testFailedWriteThrowsAndPreservesPreviousConfiguration() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: 90,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let storage = FailingNutritionGoalsStorage(data: try JSONEncoder().encode(previous), failWrites: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try failingRepository.save(DailyNutritionGoals(
            energyKcal: 2_200, proteinGrams: 100, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )))
        XCTAssertEqual(failingRepository.load(), previous)
    }

    func testFailedClearThrowsAndPreservesPreviousConfiguration() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: nil,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let storage = FailingNutritionGoalsStorage(data: try JSONEncoder().encode(previous), failRemoves: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try failingRepository.save(DailyNutritionGoals(
            energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )))
        XCTAssertEqual(failingRepository.load(), previous)
    }

    func testFailedLegacyMigrationWriteKeepsPreviousGoalsVisibleAndLegacyCopy() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_100, proteinGrams: 85,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        defaults.set(try JSONEncoder().encode(previous), forKey: DailyNutritionGoals.defaultsKey)
        let failingStorage = FailingNutritionGoalsStorage(data: nil, failWrites: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: failingStorage)

        // A failed migration must still show the prior value and retain its only durable copy.
        XCTAssertEqual(failingRepository.load(), previous)
        let legacy = try XCTUnwrap(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertEqual(try JSONDecoder().decode(DailyNutritionGoals.self, from: legacy), previous)

        // A subsequent failed save must not remove the legacy value either.
        XCTAssertThrowsError(try failingRepository.save(DailyNutritionGoals(
            energyKcal: 2_200, proteinGrams: 100, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )))
        let retainedLegacy = try XCTUnwrap(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertEqual(try JSONDecoder().decode(DailyNutritionGoals.self, from: retainedLegacy), previous)
        XCTAssertEqual(failingRepository.load(), previous)
    }

    func testLegacyUserDefaultsConfigurationMigratesToFileStorage() throws {
        let expected = DailyNutritionGoals(energyKcal: 2_100, proteinGrams: 85,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        defaults.set(try JSONEncoder().encode(expected), forKey: DailyNutritionGoals.defaultsKey)
        XCTAssertEqual(repository.load(), expected)
        XCTAssertNil(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertEqual(repository.load(), expected)
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

    func testMalformedStoredDataFallsBackToEmptyGoals() throws {
        let storage = FailingNutritionGoalsStorage(data: Data("not-json".utf8))
        let invalidRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertTrue(invalidRepository.load().isEmpty)
    }
}

private final class FailingNutritionGoalsStorage: NutritionGoalsStorage {
    private(set) var data: Data?
    var failWrites: Bool
    var failRemoves: Bool

    init(data: Data?, failWrites: Bool = false, failRemoves: Bool = false) {
        self.data = data
        self.failWrites = failWrites
        self.failRemoves = failRemoves
    }

    func read() throws -> Data? { data }

    func write(_ data: Data) throws {
        if failWrites { throw TestStorageError.writeFailed }
        self.data = data
    }

    func remove() throws {
        if failRemoves { throw TestStorageError.removeFailed }
        data = nil
    }
}

private enum TestStorageError: Error {
    case writeFailed
    case removeFailed
}
