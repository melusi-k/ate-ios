import XCTest
@testable import Ate

final class ScreenshotRecipeImportTests: XCTestCase {
    static let source = """
    Creamy Samp
    Share
    Download
    Serves:
    6
    Cooking Time:
    < 45 min
    About This Recipe
    A family recipe, served with a braai.
    Ingredients:
    800 g quick cooking samp
    2 litre(s) water
    1 onion(s), chopped
    60 ml margarine or butter
    5 ml Aromat
    45 ml Cremora
    230 g LANCEWOOD Medium Fat Plain
    Cream Cheese
    2 carrots, grated
    45 ml fresh parsley, chopped
    Convert Your Measurements
    View Full Conversion Table
    Method
    1. Bring the samp and water to the boil.
    Once boiling, lower the heat and
    simmer for 30 minutes or until soft.
    Drain off excess liquid if necessary.
    2. Fry the onion in the butter until just soft.
    3. Simmer over low heat for 5 minutes.
    4. Add the parsley and mix through.
    Serve warm.
    HINTS & TIPS:
    1. Fry bacon pieces and mushrooms until crispy.
    2. Add 250 ml peas and 100 g chopped ham.
    """
    func testSourcePrepAndFourStepsPreservedTipsRemainOutsideMethod() throws {
        let card = try ScreenshotRecipeImport.card(from: Self.source)
        XCTAssertEqual(card.source, .imported)
        XCTAssertEqual(card.servings, 6)
        XCTAssertEqual(card.ingredients.map(\.quantity), [800, 2, 1, 60, 5, 45, 230, 2, 45])
        XCTAssertEqual(card.ingredients.first?.name, "quick cooking samp")
        XCTAssertFalse(card.ingredients.contains { ($0.notes ?? "").contains("soaked") })
        XCTAssertEqual(card.steps.count, 4)
        XCTAssertEqual(card.steps.last?.instruction, "Add the parsley and mix through. Serve warm.")
        XCTAssertFalse(card.steps.contains { $0.instruction.contains("bacon") || $0.instruction.contains("peas") })
        XCTAssertTrue(card.aiNote?.contains("100 g chopped ham") == true)
        XCTAssertNil(card.timeMinutes, "Less-than source timing must not be fabricated as35min")
        XCTAssertNil(card.description, "Do not paraphrase the source description")
    }
    func testMissingBoundariesServingsOrNonSequentialStepsFailClosed() {
        for source in [Self.source.replacingOccurrences(of: "Method\n", with: ""),
                       Self.source.replacingOccurrences(of: "Serves:\n6", with: ""),
                       Self.source.replacingOccurrences(of: "3. Simmer", with: "7. Simmer"),
                       "Ingredients\n200 g flour\n2 eggs\nCook 2 minutes"] {
            XCTAssertThrowsError(try ScreenshotRecipeImport.card(from: source))
        }
    }
    func testServingsRequiresOneWholeSupportedValueNotNumericPrefix() {
        for value in ["6-8", "6.5", "6 to 8", "6/8", "6 plus 2", "6\n8", "6\nto 8", "6\nServes:8", "9999999999999999999999999"] {
            let source = Self.source.replacingOccurrences(of: "Serves:\n6", with: "Serves:" + value)
            XCTAssertThrowsError(try ScreenshotRecipeImport.card(from: source), value)
        }
    }
    func testTerminalSplitNumericMethodMarkerFailsInsteadOfMergingSteps() {
        for marker in ["4.\n", "4)\n", "4\n"] {
            let source = Self.source.replacingOccurrences(of: "4. Add the parsley", with: marker + "Add the parsley")
            XCTAssertThrowsError(try ScreenshotRecipeImport.card(from: source), marker)
        }
    }

    func testNoHintsDoesNotRequireOrInventThem() throws {
        let text = try XCTUnwrap(Self.source.components(separatedBy: "HINTS & TIPS:").first)
        let card = try ScreenshotRecipeImport.card(from: text)
        XCTAssertEqual(card.steps.count, 4)
        XCTAssertFalse(card.aiNote?.contains("bacon") == true)
    }
    func testScreenshotImportBypassesModelAndFallbackEvenWithDishHint() async throws {
        let fallback = OCRFallbackProbe()
        for available in [false, true] {
            let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { available },
                readImageText: { _ in Self.source })
            let card = try await backend.parseRecipe(ParseRequest(mode: .image, text: "samp", imageDataUrl: "fixture"))
            XCTAssertEqual(card.source, .imported)
            XCTAssertEqual(card.steps.count, 4)
        }
        let calls = await fallback.count()
        XCTAssertEqual(calls, 0)
    }
}
private actor OCRFallbackProbe: BackendService {
    var calls = 0
    func count() -> Int { calls }
    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard { calls += 1; return RecipeCard(title: "Demo") }
    func publish(_ card: RecipeCard) async throws -> String { "unused" }
    func fetchShared(slug: String) async throws -> RecipeCard? { nil }
}
