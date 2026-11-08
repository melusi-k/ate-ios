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
        let previousCurrent = AppStore.current
        defer { AppStore.current = previousCurrent }
        let suite = "CanonicalBinding-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = UserDefaults.standard.object(forKey: "ate.settings.v1")
        let timers = UserDefaults.standard.object(forKey: "ate.timerprefs.v1")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
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
        var isolatedGoals = DailyNutritionGoals()
        isolatedGoals.energyKcal = 2345
        try runtime.goalsRepository.save(isolatedGoals)
        XCTAssertEqual(try store.journalGoalsRepository.load(), isolatedGoals,
                       "Typed goals route must read the isolated runtime domain, not defaults")
        XCTAssertTrue(try AppStore.journalStoreForIntent() === runtime.journal,
                      "Intent lookup must use the actual injected app owner, never JournalStore.shared")
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
    func testIntentOwnerCannotFallBackToSingletonWhenAppCompositionIsMissing() {
        let previous = AppStore.current
        defer { AppStore.current = previous }
        AppStore.current = nil
        XCTAssertThrowsError(try AppStore.journalStoreForIntent()) { error in
            guard case JournalIntentOwnerError.appNotOpen = error else {
                return XCTFail("Expected explicit app-not-open failure, got \(error)")
            }
        }
    }

    func testIntentOwnerRejectsFallbackAndUnavailableBoundCompositions() throws {
        let previous = AppStore.current
        let settings = UserDefaults.standard.object(forKey: "ate.settings.v1")
        let timers = UserDefaults.standard.object(forKey: "ate.timerprefs.v1")
        defer {
            AppStore.current = previous
            if let settings { UserDefaults.standard.set(settings, forKey: "ate.settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.settings.v1") }
            if let timers { UserDefaults.standard.set(timers, forKey: "ate.timerprefs.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.timerprefs.v1") }
        }
        for state in [JournalOpenState.inMemoryFallback(error: "fixture"), .unavailable(error: "fixture")] {
            let suite = "IntentOwner-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let journal = JournalStore(container: nil, openState: state)
            let runtime = FoodJournalRuntime(journal: journal,
                goalsRepository: goals(defaults, suite: suite), defaults: defaults)
            let store = AppStore(context: nil, backend: MockBackend(),
                nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults), foodJournalRuntime: runtime)
            XCTAssertTrue(store.journalStore === journal)
            XCTAssertThrowsError(try AppStore.journalStoreForIntent()) { error in
                guard case JournalIntentOwnerError.notDurable = error else {
                    return XCTFail("Expected notDurable, got \(error)")
                }
            }
        }
    }

    func testRootReflectionUsesInjectedOwnerAndKeepsDraftWhenThatOwnerIsUnavailable() throws {
        let previous = AppStore.current
        let settings = UserDefaults.standard.object(forKey: "ate.settings.v1")
        let timers = UserDefaults.standard.object(forKey: "ate.timerprefs.v1")
        defer {
            AppStore.current = previous
            if let settings { UserDefaults.standard.set(settings, forKey: "ate.settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.settings.v1") }
            if let timers { UserDefaults.standard.set(timers, forKey: "ate.timerprefs.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.timerprefs.v1") }
        }
        let suite = "ReflectionOwner-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        }
        let journal = JournalStore(inMemory: true)
        let otherOwner = JournalStore(inMemory: true)
        let marker = "Injected owner reflection \(UUID().uuidString)"
        for unavailable in [false, true] {
            let owner = unavailable ? JournalStore(container: nil, openState: .unavailable(error: "fixture")) : journal
            let runtime = FoodJournalRuntime(journal: owner,
                goalsRepository: goals(defaults, suite: suite), defaults: defaults)
            let store = AppStore(context: nil, backend: MockBackend(),
                nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults), foodJournalRuntime: runtime)
            let draft = store.journalReflection
            draft.text = marker
            draft.prompt = JournalPrompt(text: "Owner-bound prompt", state: .balanced)
            draft.pendingMoment = ("Owner-bound moment", .distantPast)
            XCTAssertTrue(store.journalStore === owner)
            XCTAssertEqual(draft.save(context: nil, journal: store.journalStore), !unavailable)
            XCTAssertTrue(try otherOwner.readReflections().isEmpty, "A different owner must not receive the reflection")
            if unavailable {
                XCTAssertEqual(draft.text, marker)
                XCTAssertEqual(draft.prompt?.text, "Owner-bound prompt")
                XCTAssertEqual(draft.pendingMoment?.title, "Owner-bound moment")
                XCTAssertNotNil(draft.saveError)
                XCTAssertThrowsError(try owner.readReflections())
            } else {
                let row = try XCTUnwrap(try journal.readReflections().first { $0.text == marker })
                XCTAssertEqual(row.prompt, "Owner-bound prompt")
                XCTAssertEqual(row.journalingSuggestionTitle, "Owner-bound moment")
                XCTAssertNil(row.recordedHealthState)
                XCTAssertTrue(draft.text.isEmpty)
                XCTAssertNil(draft.saveError)
            }
        }
        XCTAssertEqual(try journal.readReflections().filter { $0.text == marker }.count, 1,
                       "The failed bound-owner attempt must not fall back to the earlier readable owner")
    }

}
