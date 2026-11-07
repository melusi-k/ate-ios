import XCTest
import SwiftUI
@testable import Ate

final class AppAppearanceTests: XCTestCase {
    func testDefaultFollowsSystem() {
        XCTAssertEqual(AppSettings().appearance, .system)
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
    }
    func testLegacySettingsKeepPrivateModeAndUnits() throws {
        let settings = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"onDeviceOnly":true,"units":"imperial"}"#.utf8))
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.onDeviceOnly)
        XCTAssertEqual(settings.units, .imperial)
    }
    func testUnknownAppearanceFallsBackWithoutResettingOtherSettings() throws {
        let settings = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"onDeviceOnly":true,"units":"imperial","appearance":"future"}"#.utf8))
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.onDeviceOnly)
        XCTAssertEqual(settings.units, .imperial)
    }
    func testAllChoicesSurviveSettingsPersistence() throws {
        for mode in AppAppearance.allCases {
            let original = AppSettings(onDeviceOnly: true, units: .imperial, appearance: mode)
            let data = try JSONEncoder().encode(original)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), original)
        }
    }
    func testWrongTypeAppearanceDoesNotDiscardOtherPreferences() throws {
        for value in ["42", "true", "[]", "{}", "null"] {
            let raw = "{\"onDeviceOnly\":true,\"units\":\"imperial\",\"appearance\":\(value)}"
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(raw.utf8))
            XCTAssertEqual(settings.appearance, .system)
            XCTAssertTrue(settings.onDeviceOnly)
            XCTAssertEqual(settings.units, .imperial)
        }
    }

}
