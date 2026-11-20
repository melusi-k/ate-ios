import XCTest

final class LibraryProteinGroupingUITests: XCTestCase {
    func testPorkLedRibsAppearUnderPorkAtNormalText() {
        let receipt = NamedRedReceipt(self, "protein-grouping")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaLibraryPorkGrouping", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        receipt.step("launch-normal-text-pork-fixture", pixels: true) { app.launch() }
        let pork = app.descendants(matching: .any)["section.Pork"].firstMatch
        let chicken = app.descendants(matching: .any)["section.Chicken"].firstMatch
        let ribs = app.staticTexts["Sticky Ribs and wings"]
        let wings = app.staticTexts["Lemon pepper wings"]
        receipt.step("resolve-headers-and-rows", pixels: true) {
        XCTAssertTrue(chicken.waitForExistence(timeout: 10))
        XCTAssertTrue(pork.waitForExistence(timeout: 5))
        XCTAssertTrue(ribs.exists); XCTAssertTrue(wings.exists)
        }
        receipt.inspect("chicken-heading", chicken)
        receipt.inspect("wings-row", wings)
        receipt.inspect("pork-heading", pork)
        receipt.inspect("ribs-row", ribs)
        receipt.step("assert-protein-section-order") {
        XCTAssertLessThan(chicken.frame.maxY, wings.frame.minY)
        XCTAssertLessThan(wings.frame.maxY, pork.frame.minY)
        XCTAssertLessThan(pork.frame.maxY, ribs.frame.minY,
                          "The pork-led ribs recipe belongs below Pork, not in Chicken")
        }
        receipt.step("assert-heading-visible-and-recipe-hittable", pixels: true) {
            // A section heading is read-only. Partial visibility is acceptable;
            // only the actual recipe row needs to be hittable.
            let window = app.windows.firstMatch.frame
            let navigation = app.navigationBars.firstMatch.frame
            let tabs = app.tabBars.firstMatch.frame
            XCTAssertFalse(window.isEmpty)
            XCTAssertFalse(navigation.isEmpty)
            XCTAssertFalse(tabs.isEmpty)
            var bottom = min(window.maxY, tabs.minY)
            let accessory = app.descendants(matching: .any)["bottomAccessory"].firstMatch
            if accessory.exists {
                let frame = accessory.frame
                XCTAssertFalse(frame.isEmpty)
                if frame.intersects(window) { bottom = min(bottom, frame.minY) }
            }
            let top = max(window.minY, navigation.maxY)
            XCTAssertGreaterThan(bottom, top)
            let band = CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
            let heading = pork.frame
            XCTAssertFalse(heading.isEmpty)
            let visible = band.intersection(heading)
            let fraction = heading.isEmpty || visible.isNull ? 0 : (visible.width * visible.height) / (heading.width * heading.height)
            print("UI-RED protein-heading frame=\(heading) clear=\(band) visible=\(visible) visibleFraction=\(fraction)")
            XCTAssertTrue(window.intersects(heading), "Pork heading must intersect the screen: \(heading)")
            XCTAssertFalse(visible.isNull, "Pork heading must intersect the visible content area")
            XCTAssertGreaterThan(fraction, 0, "Partial heading visibility is enough, fully hidden is not")
            XCTAssertTrue(ribs.isHittable, "The recipe below Pork must remain hittable")
        }
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "library-pork-led-ribs-normal-main-ingredient-groups"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
