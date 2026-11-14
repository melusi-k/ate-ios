import XCTest
@testable import Ate

final class AccessibilityTests: XCTestCase {
    func testColourPairsMeetWCAGAA() {
        for p in Palette.pairs {
            XCTAssertGreaterThanOrEqual(Palette.contrast(p.fg, p.bg), 4.5, "\(p.name) contrast too low")
        }
    }

    func testFilledPrimaryControlsHaveAccessibleLightAndDarkThemePairings() {
        let required = ["primaryForeground/primary", "dark primaryForeground/primary"]
        for name in required {
            let pair = Palette.pairs.first { $0.name == name }
            XCTAssertNotNil(pair, name)
            if let pair { XCTAssertGreaterThanOrEqual(Palette.contrast(pair.fg, pair.bg), 4.5, name) }
        }
    }

    func testFontsScaleWithTextStyle() {
        XCTAssertEqual(AteFont.style(for: 36), .largeTitle)
        XCTAssertEqual(AteFont.style(for: 15), .body)
        XCTAssertEqual(AteFont.style(for: 12), .caption)
    }

    func testStringCatalogHasEnglishSource() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(L10n.libraryTitle, "Your Kitchen")
    }
}
