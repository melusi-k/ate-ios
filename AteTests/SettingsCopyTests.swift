import XCTest
@testable import Ate

/// #74: the truthful local-only versus synced copy behind Settings organisation.
/// Sync truth: AppStore.syncNow pushes/pulls only `recipe` and `shopping` records;
/// AteDataArchive carries recipes, shopping items, nutrition diary entries,
/// nutrition goals, app settings and timer preferences (no Journal yet).
final class SettingsCopyTests: XCTestCase {
    func testSyncSummarySignedInSeparatesSyncedFromLocalOnly() {
        let copy = SettingsCopy.syncSummary(accountAvailable: true, signedIn: true)
        XCTAssertTrue(copy.contains("recipes"))
        XCTAssertTrue(copy.contains("shopping list"))
        XCTAssertTrue(copy.contains("food diary"))
        XCTAssertTrue(copy.contains("nutrition goals"))
        XCTAssertTrue(copy.contains("Journal"))
        XCTAssertTrue(copy.contains("Stays on this iPhone only"))
    }

    func testSyncSummarySignedOutKeepsEverythingLocal() {
        let copy = SettingsCopy.syncSummary(accountAvailable: true, signedIn: false)
        XCTAssertTrue(copy.contains("stored on this iPhone"))
        XCTAssertTrue(copy.contains("Sign in"))
    }

    func testSyncSummaryUnavailableSaysNotConfigured() {
        let copy = SettingsCopy.syncSummary(accountAvailable: false, signedIn: false)
        XCTAssertTrue(copy.contains("isn't configured"))
        XCTAssertTrue(copy.contains("stays on this iPhone"))
    }

    func testDataFooterMatchesSyncTruth() {
        let signedIn = SettingsCopy.dataFooter(signedIn: true)
        XCTAssertTrue(signedIn.contains("shopping list sync"))
        XCTAssertFalse(signedIn.contains("diary sync"))
        XCTAssertTrue(SettingsCopy.dataFooter(signedIn: false).contains("this iPhone only"))
    }

    func testToolsFooterListsCurrentExportContents() {
        let copy = SettingsCopy.toolsFooter
        for expected in ["recipes", "shopping list", "food diary", "nutrition goals", "app preferences"] {
            XCTAssertTrue(copy.contains(expected), "toolsFooter should mention \(expected)")
        }
    }

    func testAIExplanationNamesRequirementAndDemoFallback() {
        let copy = SettingsCopy.aiExplanation
        XCTAssertTrue(copy.contains("Apple Intelligence"))
        XCTAssertTrue(copy.contains("iOS 26"))
        XCTAssertTrue(copy.contains("demo"))
    }

    func testNutritionFooterStatesLocalOnlyAndExport() {
        let copy = SettingsCopy.nutritionFooter
        XCTAssertTrue(copy.contains("this iPhone only"))
        XCTAssertTrue(copy.contains("export"))
    }
}
