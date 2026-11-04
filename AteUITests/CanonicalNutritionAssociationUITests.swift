import XCTest

/// Real candidate view + real coordinator, with DEBUG-only ephemeral fixture composition.
/// This is UI behavior evidence, not production persistence or migration acceptance.
final class CanonicalNutritionAssociationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let entryID = "17900000-0000-4000-8000-000000000001"

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(corrupt: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaCanonicalNutrition"]
        if corrupt { app.launchArguments.append("-qaCanonicalNutritionCorruptLinks") }
        app.launch()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 20))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Bounded scrolling over the real List/Form. A missing control fails, never silently skips.
    @discardableResult
    private func reveal(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let target = element(identifier)
        for _ in 0..<12 {
            if target.exists && target.isHittable { return target }
            app.swipeUp()
        }
        XCTFail("Missing or unreachable control: \(identifier)", file: file, line: line)
        return target
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let b64 = screenshot.pngRepresentation.base64EncodedString()
        print("SNAPSHOT-BEGIN \(name) \(b64.count)")
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 4000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("SNAPSHOT-CHUNK \(name) \(b64[i..<j])")
            i = j
        }
        print("SNAPSHOT-END \(name)")
    }

    func testLinkSnapshotThenUnlinkKeepsEntryValues() {
        launch()
        reveal("nutritionDiary.entry.\(entryID)").tap()
        reveal("nutritionDiary.linkRecipe").tap()
        let recipe = app.buttons["Miso salmon"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        XCTAssertTrue(element("nutritionDiary.linkedRecipe").waitForExistence(timeout: 5))
        XCTAssertEqual(element("nutritionDiary.linkedRecipe").label, "Miso salmon")
        shot("nutrition-linked-recipe")
        // Reopen the sheet: the snapshot must come back from the controller/store, not only UI state.
        app.buttons["Cancel"].tap()
        let row = reveal("nutritionDiary.entry.\(entryID)")
        XCTAssertTrue(row.label.contains("Recipe: Miso salmon"))
        row.tap()
        reveal("nutritionDiary.unlinkRecipe").tap()
        XCTAssertFalse(element("nutritionDiary.linkedRecipe").exists)
        XCTAssertTrue(element("nutritionDiary.linkRecipe").exists)
        shot("nutrition-unlinked-recipe")
        app.buttons["Cancel"].tap()
        let unlinkedRow = reveal("nutritionDiary.entry.\(entryID)")
        XCTAssertFalse(unlinkedRow.label.contains("Recipe: Miso salmon"))
        unlinkedRow.tap()
        XCTAssertEqual(element("nutritionDiary.quantity").value as? String, "2")
        XCTAssertEqual(element("nutritionDiary.servings").value as? String, "1.5")
        reveal("nutritionDiary.nutrient.energy")
        XCTAssertEqual(element("nutritionDiary.nutrient.energy").value as? String, "200")
    }

    func testCorruptLinksAreUnavailableWhileEntryRemainsReadable() {
        launch(corrupt: true)
        reveal("nutritionDiary.linksUnavailableSummary")
        let row = reveal("nutritionDiary.entry.\(entryID)")
        XCTAssertTrue(row.label.contains("Pap"))
        row.tap()
        reveal("nutritionDiary.linksUnavailable")
        XCTAssertFalse(element("nutritionDiary.linkRecipe").exists)
        XCTAssertFalse(element("nutritionDiary.unlinkRecipe").exists)
        shot("nutrition-corrupt-links")
    }

    func testFrequentPrefillValidationFailureRetainsDraftAndPriorProvenance() {
        launch()
        element("nutritionDiary.add").tap()
        reveal("nutritionDiary.frequent.0").tap()
        XCTAssertEqual(element("nutritionDiary.foodName").value as? String, "Pap")
        XCTAssertEqual(element("nutritionDiary.quantity").value as? String, "2")
        XCTAssertEqual(element("nutritionDiary.servings").value as? String, "1.5")
        reveal("nutritionDiary.sourceName")
        XCTAssertEqual(element("nutritionDiary.sourceName").value as? String, "You")
        XCTAssertTrue(element("nutritionDiary.source").label.contains("Entered by you") || (element("nutritionDiary.source").value as? String) == "Entered by you")
        XCTAssertEqual(element("nutritionDiary.sourceIdentifier").value as? String, "")
        XCTAssertEqual(element("nutritionDiary.sourceIdentifier").placeholderValue, "Source record ID (optional)")
        XCTAssertEqual(element("nutritionDiary.verificationNote").value as? String, "")
        XCTAssertEqual(element("nutritionDiary.verificationNote").placeholderValue, "Preparation or source-match note (optional)")
        reveal("nutritionDiary.nutrient.energy")
        XCTAssertEqual(element("nutritionDiary.nutrient.energy").value as? String, "200")
        // Empty values and their separate placeholders prove nil was not converted to zero.
        XCTAssertEqual(element("nutritionDiary.nutrient.carbohydrates").value as? String, "")
        XCTAssertEqual(element("nutritionDiary.nutrient.carbohydrates").placeholderValue, "Carbohydrates per serving")
        shot("nutrition-prefill-reviewed-values")
        // Change a real draft field to an invalid amount, then save through real validation.
        for _ in 0..<10 { if element("nutritionDiary.quantity").isHittable { break }; app.swipeDown() }
        let quantity = element("nutritionDiary.quantity")
        quantity.tap()
        let oldValue = quantity.value as? String ?? ""
        quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "0")
        element("nutritionDiary.save").tap()
        reveal("nutritionDiary.formError")
        XCTAssertTrue(element("nutritionDiary.formError").label.contains("greater than zero"))
        shot("nutrition-prefill-failed-draft")
        for _ in 0..<10 { if element("nutritionDiary.quantity").isHittable { break }; app.swipeDown() }
        XCTAssertEqual(element("nutritionDiary.quantity").value as? String, "0")
        XCTAssertEqual(element("nutritionDiary.foodName").value as? String, "Pap")
        app.buttons["Cancel"].tap()
        reveal("nutritionDiary.entry.\(entryID)").tap()
        reveal("nutritionDiary.sourceIdentifier")
        XCTAssertEqual(element("nutritionDiary.sourceIdentifier").value as? String, "ext-99")
        XCTAssertEqual(element("nutritionDiary.verificationNote").value as? String, "From a label photo")
    }
}
