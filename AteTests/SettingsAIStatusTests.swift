import XCTest
@testable import Ate

final class SettingsAIStatusTests: XCTestCase {
    func testPrivateModeTakesPrecedenceOverEveryModelState() {
        for status in SettingsAIStatus.allCases {
            XCTAssertEqual(SettingsCopy.aiStatusTitle(privateMode: true, status: status), "Private mode is blocking new AI recipes")
            let guidance = SettingsCopy.aiStatusGuidance(privateMode: true, status: status)
            XCTAssertTrue(guidance.contains("Turn off Private mode above"))
            XCTAssertTrue(guidance.contains("including demo recipes"))
            XCTAssertTrue(guidance.contains("saved recipes remain available"))
        }
    }
    func testEveryUnavailableStateExplainsDemoFallbackWithoutRawSDKReason() {
        for status in SettingsAIStatus.allCases where status != .ready {
            XCTAssertTrue(status.guidance.contains("Demo"), "\(status)")
            XCTAssertFalse(status.title.contains("deviceNotEligible"))
            XCTAssertFalse(status.title.contains("modelNotReady"))
        }
    }
    func testHardwareAndOSRequirementsAreNotConflated() {
        XCTAssertTrue(SettingsAIStatus.unsupportedDevice.guidance.contains("Updating iOS alone won't"))
        XCTAssertTrue(SettingsAIStatus.needsOSUpdate.guidance.contains("compatible Apple Intelligence device"))
    }
    func testExportExplicitlyDisclosesJournalExclusionAndNoSync() {
        XCTAssertTrue(SettingsCopy.toolsFooter.contains("Journal entries and their photos and locations are not included yet"))
        XCTAssertTrue(SettingsCopy.toolsFooter.contains("does not sync"))
    }
    func testReadyStateDoesNotSuggestDemoOrTurningOnAI() {
        XCTAssertEqual(SettingsCopy.aiStatusTitle(privateMode: false, status: .ready), "Apple Intelligence ready")
        XCTAssertFalse(SettingsAIStatus.ready.guidance.contains("Demo"))
    }
}
