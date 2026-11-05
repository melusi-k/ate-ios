import XCTest
@testable import Ate

@MainActor
final class CanonicalConsumerBindingTests: XCTestCase {
    private func goals(_ defaults: UserDefaults, suite: String) -> NutritionGoalsRepository {
        NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suite).appendingPathComponent("goals.json")))
    }

    func testInjectedCanonicalGraphRefusesLegacyArchiveReadsAndWritesBeforeDecode() throws {
        let suite = "CanonicalBinding-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = UserDefaults.standard.object(forKey: "ate.settings.v1")
        let timers = UserDefaults.standard.object(forKey: "ate.timerprefs.v1")
        defer {
            defaults.removePersistentDomain(forName: suite)
            if let settings { UserDefaults.standard.set(settings, forKey: "ate.settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.settings.v1") }
            if let timers { UserDefaults.standard.set(timers, forKey: "ate.timerprefs.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.timerprefs.v1") }
        }
        let raw = Data("legacy bytes must remain unchanged".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let runtime = FoodJournalRuntime(journal: JournalStore(inMemory: true), goalsRepository: goals(defaults, suite: suite), defaults: defaults)
        let store = AppStore(context: nil, backend: MockBackend(),
            nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults), foodJournalRuntime: runtime)
        XCTAssertTrue(store.foodJournalRuntime === runtime)
        XCTAssertThrowsError(try store.exportJSON()) { error in
            XCTAssertTrue(error is CanonicalConsumerBindingError)
        }
        XCTAssertThrowsError(try store.importJSON(Data("not an archive".utf8))) { error in
            XCTAssertTrue(error is CanonicalConsumerBindingError)
        }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertNil(store.nutritionEntriesForInsights(), "Unreadable must not be reported as an empty diary")
        XCTAssertTrue(store.recipes.isEmpty)
        XCTAssertTrue(store.shopping.isEmpty)
    }
}
