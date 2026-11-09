import XCTest
@testable import Ate

@MainActor
final class ArchiveNutritionParticipantTests: XCTestCase {
    enum Injected: Error { case failure }
    private var emptyGoals: DailyNutritionGoals {
        DailyNutritionGoals(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
    }

    func testEveryBoundaryRestoresExactRawBytesAndAbsentKeys() throws {
        for boundary in ArchiveNutritionParticipant.Boundary.allCases {
            let suite = "ArchiveNutrition-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let oldDiary = Data(" [ ] \n".utf8)
            defaults.set(oldDiary, forKey: NutritionDiaryRepository.storageKey)
            let oldGoals = try JSONEncoder().encode(emptyGoals)
            defaults.set(oldGoals, forKey: DailyNutritionGoals.defaultsKey)
            let storage = TestGoalStorage()
            let adapter = try ArchiveNutritionParticipant(diary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults, storage: storage), incomingDiary: [], incomingGoals: emptyGoals,
                checkpoint: { if $0 == boundary { throw Injected.failure } })
            // Creating the participant must not migrate legacy goals or normalize diary bytes.
            XCTAssertNil(storage.data)
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), oldDiary)
            XCTAssertEqual(defaults.data(forKey: DailyNutritionGoals.defaultsKey), oldGoals)
            let participant = adapter.participant()
            XCTAssertThrowsError(try { try participant.apply(); try participant.verify() }())
            try participant.rollback()
            XCTAssertNil(storage.data)
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), oldDiary)
            XCTAssertEqual(defaults.data(forKey: DailyNutritionGoals.defaultsKey), oldGoals)
        }
    }

    func testGoalsDurableWriteThenThrowCompensatesExactBeforeImage() throws {
        let suite = "ArchiveNutrition-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldBytes = try JSONEncoder().encode(emptyGoals)
        let storage = TestGoalStorage(); storage.data = oldBytes
        var incoming = emptyGoals; incoming.energyKcal = 2000
        let adapter = try ArchiveNutritionParticipant(diary: NutritionDiaryRepository(defaults: defaults),
            goals: NutritionGoalsRepository(defaults: defaults, storage: storage), incomingDiary: [], incomingGoals: incoming)
        storage.failAfterWrite = true
        let participant = adapter.participant()
        XCTAssertThrowsError(try participant.apply())
        storage.failAfterWrite = false
        try participant.rollback()
        XCTAssertEqual(storage.data, oldBytes)
        XCTAssertNil(defaults.object(forKey: NutritionDiaryRepository.storageKey))
    }

    func testChangedSourceRefusesBeforeWriteAndRollbackDoesNotEraseNewValue() throws {
        let suite = "ArchiveNutrition-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = TestGoalStorage()
        let adapter = try ArchiveNutritionParticipant(diary: NutritionDiaryRepository(defaults: defaults),
            goals: NutritionGoalsRepository(defaults: defaults, storage: storage), incomingDiary: [], incomingGoals: emptyGoals)
        let changed = Data("[]".utf8)
        defaults.set(changed, forKey: NutritionDiaryRepository.storageKey)
        let participant = adapter.participant()
        XCTAssertThrowsError(try participant.apply()); try participant.rollback()
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), changed)
    }
}

private final class TestGoalStorage: NutritionGoalsStorage {
    var data: Data?
    var failAfterWrite = false
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value; if failAfterWrite { throw TestStorageError.injected } }
    func remove() throws { data = nil }
    func preserveCorruptData(_ data: Data) throws {}
}

private enum TestStorageError: Error { case injected }

@MainActor
final class ArchiveNutritionOwnershipTests: XCTestCase {
    private var goalsValue: DailyNutritionGoals {
        DailyNutritionGoals(energyKcal: 2000, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
    }
    func testForeignDiaryMutationOrDeletionSurvivesCompensation() throws {
        for delete in [false, true] {
            let suite = "ArchiveNutritionOwnership-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
            let original = Data(" [] \n".utf8)
            defaults.set(original, forKey: NutritionDiaryRepository.storageKey)
            let storage = TestGoalStorage()
            let adapter = try ArchiveNutritionParticipant(diary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults, storage: storage), incomingDiary: [], incomingGoals: goalsValue)
            let participant = adapter.participant(); try participant.apply()
            let foreign = Data("[ ]  ".utf8)
            if delete { defaults.removeObject(forKey: NutritionDiaryRepository.storageKey) }
            else { defaults.set(foreign, forKey: NutritionDiaryRepository.storageKey) }
            XCTAssertThrowsError(try participant.rollback())
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), delete ? nil : foreign)
            XCTAssertNil(storage.data) // independent safe component still compensated.
        }
    }
    func testLostLeaseDoesNotOverwriteAnyComponent() throws {
        let suite = "ArchiveNutritionOwnership-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let storage = TestGoalStorage(); var held = true
        let adapter = try ArchiveNutritionParticipant(diary: NutritionDiaryRepository(defaults: defaults),
            goals: NutritionGoalsRepository(defaults: defaults, storage: storage), incomingDiary: [], incomingGoals: goalsValue,
            validateLease: { if !held { throw TestStorageError.injected } })
        let participant = adapter.participant(); try participant.apply()
        let appliedGoal = storage.data; let appliedDiary = defaults.data(forKey: NutritionDiaryRepository.storageKey)
        held = false
        XCTAssertThrowsError(try participant.rollback())
        XCTAssertEqual(storage.data, appliedGoal)
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), appliedDiary)
    }
}
