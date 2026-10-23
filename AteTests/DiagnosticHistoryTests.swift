import XCTest
@testable import Ate

final class DiagnosticHistoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "ate.diagnostic-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRecordsEventsAndRestoresThemFromDefaults() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let history = DiagnosticHistory(defaults: defaults, key: "events")
        history.record(.appLaunched, at: date)
        history.record(.saveFailed, at: date.addingTimeInterval(5))

        let restored = DiagnosticHistory(defaults: defaults, key: "events")
        XCTAssertEqual(restored.entries.map(\.kind), [.appLaunched, .saveFailed])
        XCTAssertEqual(restored.entries.first?.timestamp, date)
    }

    func testHistoryIsBoundedToMaximumEntries() {
        let history = DiagnosticHistory(defaults: defaults, key: "events")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<(DiagnosticHistory.maximumEntries + 25) {
            history.record(.appForegrounded, at: start.addingTimeInterval(TimeInterval(i)))
        }

        XCTAssertEqual(history.entries.count, DiagnosticHistory.maximumEntries)
        XCTAssertEqual(history.entries.first?.timestamp, start.addingTimeInterval(25))
    }

    func testExportContainsTypedEventsButNoArbitraryUserContent() {
        let history = DiagnosticHistory(defaults: defaults, key: "events")
        history.record(.storeRecovered, at: Date(timeIntervalSince1970: 1_800_000_000))
        let report = history.exportReport(appVersion: "1.2", buildNumber: "42", osVersion: "Test OS")

        XCTAssertTrue(report.contains("storeRecovered"))
        XCTAssertTrue(report.contains("App version: 1.2"))
        XCTAssertFalse(report.contains("recipe"))
        XCTAssertFalse(report.contains("account"))
    }

    func testClearRemovesPersistedHistory() {
        let history = DiagnosticHistory(defaults: defaults, key: "events")
        history.record(.appLaunched)
        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(defaults.data(forKey: "events"))
    }
    func testProductEventCategoriesHaveStableLabelsAndCodableNames() {
        let kinds: [DiagnosticEvent.Kind] = [
            .recipeImportSucceeded, .recipeImportFailed, .recipeSaved,
            .cookingSessionCompleted, .insightViewed, .insightActionSelected,
            .syncSucceeded, .syncFailed
        ]
        for kind in kinds {
            let event = DiagnosticEvent(kind: kind)
            XCTAssertFalse(event.title.isEmpty, "Missing title for \\(kind)")
            let data = try! JSONEncoder().encode(event)
            let restored = try! JSONDecoder().decode(DiagnosticEvent.self, from: data)
            XCTAssertEqual(restored.kind, kind)
        }
    }

    func testProductEventsRemainCategoryOnlyAndClearable() {
        let history = DiagnosticHistory(defaults: defaults, key: "events")
        history.record(.recipeSaved)
        history.record(.cookingSessionCompleted)

        XCTAssertEqual(history.entries.map(\\.kind), [.recipeSaved, .cookingSessionCompleted])
        let exported = history.exportReport(appVersion: "1", buildNumber: "1", osVersion: "Test")
        XCTAssertTrue(exported.contains("recipeSaved"))
        XCTAssertTrue(exported.contains("cookingSessionCompleted"))
        XCTAssertFalse(exported.contains("recipe title"))
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

}
