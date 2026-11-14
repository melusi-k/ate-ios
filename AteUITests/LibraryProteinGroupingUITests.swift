import XCTest

final class LibraryProteinGroupingUITests: XCTestCase {
    func testPorkLedRibsAppearUnderPorkAtNormalText() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaLibraryPorkGrouping", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let pork = app.descendants(matching: .any)["section.Pork"].firstMatch
        let chicken = app.descendants(matching: .any)["section.Chicken"].firstMatch
        let ribs = app.staticTexts["Sticky Ribs and wings"]
        let wings = app.staticTexts["Lemon pepper wings"]
        XCTAssertTrue(chicken.waitForExistence(timeout: 10))
        XCTAssertTrue(pork.waitForExistence(timeout: 5))
        XCTAssertTrue(ribs.exists); XCTAssertTrue(wings.exists)
        XCTAssertLessThan(chicken.frame.maxY, wings.frame.minY)
        XCTAssertLessThan(wings.frame.maxY, pork.frame.minY)
        XCTAssertLessThan(pork.frame.maxY, ribs.frame.minY,
                          "The pork-led ribs recipe belongs below Pork, not in Chicken")
        XCTAssertTrue(pork.isHittable); XCTAssertTrue(ribs.isHittable)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "library-pork-led-ribs-normal-main-ingredient-groups"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
