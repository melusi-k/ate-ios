import XCTest
@testable import Ate

final class CookModeFeatureTests: XCTestCase {
    func testIndependentFlagDefaultsOnAndHonorsBuiltOffConfiguration() {
        XCTAssertTrue(CookModeFeature.enabled(configured: nil, isUITesting: false, arguments: []))
        XCTAssertFalse(CookModeFeature.enabled(configured: false, isUITesting: false, arguments: []))
        XCTAssertTrue(CookModeFeature.enabled(configured: true, isUITesting: false, arguments: []))
    }
    func testQAOffIsIgnoredOutsideUITestingAndDoesNotCoupleOtherScreens() {
        XCTAssertFalse(CookModeFeature.enabled(configured: nil, isUITesting: true, arguments: ["-qaStitchCookModeOff"]))
        XCTAssertTrue(CookModeFeature.enabled(configured: nil, isUITesting: false, arguments: ["-qaStitchCookModeOff"]))
        XCTAssertTrue(CookModeFeature.enabled(configured: nil, isUITesting: true, arguments: ["-qaStitchLibraryMultiSelectOff", "-qaStitchAddRecipeScanOff", "-qaStitchRecipeDetailOff"]))
    }
}
