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
        XCTAssertEqual(try repository.load(), expected)
    }

    func testSavingEmptyConfigurationClearsPersistedGoals() throws {
        try repository.save(DailyNutritionGoals(energyKcal: 2_000, proteinGrams: nil,
                                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        try repository.save(DailyNutritionGoals(energyKcal: nil, proteinGrams: nil,
                                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        XCTAssertNil(try FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json")).read())
        XCTAssertTrue(try repository.load().isEmpty)
    }

    func testFailedWriteThrowsAndPreservesPreviousConfiguration() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: 90,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let storage = FailingNutritionGoalsStorage(data: try JSONEncoder().encode(previous), failWrites: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try failingRepository.save(DailyNutritionGoals(
            energyKcal: 2_200, proteinGrams: 100, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )))
        XCTAssertEqual(try failingRepository.load(), previous)
    }

    func testFailedClearThrowsAndPreservesPreviousConfiguration() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: nil,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let storage = FailingNutritionGoalsStorage(data: try JSONEncoder().encode(previous), failRemoves: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try failingRepository.save(DailyNutritionGoals(
            energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )))
        XCTAssertEqual(try failingRepository.load(), previous)
    }

    func testFailedLegacyMigrationWriteKeepsPreviousGoalsVisibleAndLegacyCopy() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_100, proteinGrams: 85,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        defaults.set(try JSONEncoder().encode(previous), forKey: DailyNutritionGoals.defaultsKey)
        let failingStorage = FailingNutritionGoalsStorage(data: nil, failWrites: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: failingStorage)

        XCTAssertThrowsError(try failingRepository.load()) { error in
            guard let loadError = error as? NutritionGoalsLoadError else {
                XCTFail("Expected explicit migration failure")
                return
            }
            XCTAssertEqual(loadError.fallbackGoals, previous)
        }
        let legacy = try XCTUnwrap(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertEqual(try JSONDecoder().decode(DailyNutritionGoals.self, from: legacy), previous)

        XCTAssertThrowsError(try failingRepository.save(DailyNutritionGoals(
            energyKcal: 2_200, proteinGrams: 100, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )))
        let retainedLegacy = try XCTUnwrap(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertEqual(try JSONDecoder().decode(DailyNutritionGoals.self, from: retainedLegacy), previous)

        XCTAssertThrowsError(try failingRepository.load()) { error in
            XCTAssertEqual((error as? NutritionGoalsLoadError)?.fallbackGoals, previous)
        }
    }

    func testLegacyUserDefaultsConfigurationMigratesToFileStorage() throws {
        let expected = DailyNutritionGoals(energyKcal: 2_100, proteinGrams: 85,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        defaults.set(try JSONEncoder().encode(expected), forKey: DailyNutritionGoals.defaultsKey)
        XCTAssertEqual(try repository.load(), expected)
        XCTAssertNil(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertEqual(try repository.load(), expected)
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

    func testStorageReadFailureIsNotTreatedAsEmptyGoals() throws {
        let existing = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: 90,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let storage = FailingNutritionGoalsStorage(data: try JSONEncoder().encode(existing), failReads: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)

        XCTAssertThrowsError(try failingRepository.load()) { error in
            guard let loadError = error as? NutritionGoalsLoadError else {
                XCTFail("Expected explicit storage-read failure")
                return
            }
            XCTAssertNil(loadError.fallbackGoals)
        }
    }

    func testStorageReadFailureExposesLegacyFallbackButStillRequiresRetry() throws {
        let previous = DailyNutritionGoals(energyKcal: 2_050, proteinGrams: 88,
                                           carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        defaults.set(try JSONEncoder().encode(previous), forKey: DailyNutritionGoals.defaultsKey)
        let storage = FailingNutritionGoalsStorage(data: nil, failReads: true)
        let failingRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)

        XCTAssertThrowsError(try failingRepository.load()) { error in
            XCTAssertEqual((error as? NutritionGoalsLoadError)?.fallbackGoals, previous)
        }
        XCTAssertEqual(try JSONDecoder().decode(
            DailyNutritionGoals.self,
            from: XCTUnwrap(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        ), previous)
    }

    func testMalformedStoredDataIsReportedInsteadOfTreatedAsEmpty() throws {
        let storage = FailingNutritionGoalsStorage(data: Data("not-json".utf8))
        let invalidRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try invalidRepository.load()) { error in
            guard let loadError = error as? NutritionGoalsLoadError else {
                XCTFail("Expected explicit corrupt-data error")
                return
            }
            XCTAssertNil(loadError.fallbackGoals)
            XCTAssertTrue(loadError.canRecoverCorruptData)
        }
    }

    func testFileStoragePreservesCorruptBytesInUniqueLocalBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NutritionGoalsBackup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("goals.json")
        let storage = FileNutritionGoalsStorage(fileURL: fileURL)
        let corrupt = Data("not-json".utf8)

        try storage.write(corrupt)
        try storage.preserveCorruptData(corrupt)

        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("nutrition-goals-corrupt-") }
        XCTAssertEqual(backupURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: backupURLs[0]), corrupt)

        try storage.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: backupURLs[0]), corrupt)
    }

    func testCorruptStoredDataIsBackedUpBeforeReset() throws {
        let corrupt = Data("not-json".utf8)
        let storage = FailingNutritionGoalsStorage(data: corrupt)
        let invalidRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try invalidRepository.load())

        try invalidRepository.recoverCorruptData()

        XCTAssertEqual(storage.backups, [corrupt])
        XCTAssertNil(storage.data)
        XCTAssertTrue(try invalidRepository.load().isEmpty)
    }

    func testCorruptLegacyDataIsBackedUpBeforeReset() throws {
        let corrupt = Data("legacy-not-json".utf8)
        defaults.set(corrupt, forKey: DailyNutritionGoals.defaultsKey)
        let storage = FailingNutritionGoalsStorage(data: nil)
        let invalidRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try invalidRepository.load())

        try invalidRepository.recoverCorruptData()

        XCTAssertEqual(storage.backups, [corrupt])
        XCTAssertNil(defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        XCTAssertTrue(try invalidRepository.load().isEmpty)
    }

    func testFailedCorruptDataBackupLeavesOriginalDataUntouched() throws {
        let corrupt = Data("not-json".utf8)
        let storage = FailingNutritionGoalsStorage(data: corrupt, failPreserve: true)
        let invalidRepository = NutritionGoalsRepository(defaults: defaults, storage: storage)
        XCTAssertThrowsError(try invalidRepository.load())

        XCTAssertThrowsError(try invalidRepository.recoverCorruptData())

        XCTAssertEqual(storage.data, corrupt)
        XCTAssertTrue(storage.backups.isEmpty)
    }
}

private final class FailingNutritionGoalsStorage: NutritionGoalsStorage {
    private(set) var data: Data?
    var failWrites: Bool
    var failRemoves: Bool
    var failReads: Bool
    var failPreserve: Bool
    private(set) var backups: [Data] = []

    init(data: Data?, failWrites: Bool = false, failRemoves: Bool = false,
         failReads: Bool = false, failPreserve: Bool = false) {
        self.data = data
        self.failWrites = failWrites
        self.failRemoves = failRemoves
        self.failReads = failReads
        self.failPreserve = failPreserve
    }

    func read() throws -> Data? {
        if failReads { throw TestStorageError.readFailed }
        return data
    }

    func write(_ data: Data) throws {
        if failWrites { throw TestStorageError.writeFailed }
        self.data = data
    }

    func preserveCorruptData(_ data: Data) throws {
        if failPreserve { throw TestStorageError.preserveFailed }
        backups.append(data)
    }

    func remove() throws {
        if failRemoves { throw TestStorageError.removeFailed }
        data = nil
    }
}

private enum TestStorageError: Error {
    case readFailed
    case writeFailed
    case removeFailed
    case preserveFailed
}
