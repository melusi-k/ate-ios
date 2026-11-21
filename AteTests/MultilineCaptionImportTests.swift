import XCTest
import SwiftUI
@testable import Ate

@MainActor
final class MultilineCaptionImportTests: XCTestCase {
    // Exact build456 device-test paste, including the presentation framing line.
    private let caption = """
    Sample caption, paste as is:

    Garlic butter chicken thighs 🍗
    4 chicken thighs
    2 tbsp butter
    3 cloves garlic, minced
    1 tsp paprika
    salt and pepper
    Method: Pat thighs dry and season. Sear skin side down in a hot pan 6 min, flip, cook 5 min. Add butter and garlic, baste 2 min. Rest 5 min and serve.
    """
    private let ingredientRows = ["4 chicken thighs", "2 tbsp butter", "3 cloves garlic, minced", "1 tsp paprika", "salt and pepper"]
    private let method = "Method: Pat thighs dry and season. Sear skin side down in a hot pan 6 min, flip, cook 5 min. Add butter and garlic, baste 2 min. Rest 5 min and serve."

    private func assertExact(_ card: RecipeCard, raw: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(card.title, "Garlic butter chicken thighs 🍗", file: file, line: line)
        XCTAssertEqual(card.ingredients.map(\.name), ingredientRows, file: file, line: line)
        // Same lossless source-row representation as classified imports. Do not
        // invent structured amounts/units alongside quantities already in names.
        XCTAssertEqual(card.ingredients.map(\.quantity), [0, 0, 0, 0, 0], file: file, line: line)
        XCTAssertEqual(card.ingredients.map(\.unit), ["", "", "", "", ""], file: file, line: line)
        XCTAssertTrue(card.ingredients.allSatisfy { $0.notes == nil }, file: file, line: line)
        XCTAssertEqual(card.steps.map(\.instruction), [method], file: file, line: line)
        XCTAssertEqual(card.steps.map(\.order), [1], file: file, line: line)
        XCTAssertTrue(card.steps.allSatisfy { $0.timeSeconds == nil }, file: file, line: line)
        XCTAssertEqual(card.servings, 0, file: file, line: line)
        XCTAssertNil(card.timeMinutes, file: file, line: line)
        XCTAssertEqual(card.source, .imported, file: file, line: line)
        XCTAssertTrue(card.isEditableDraft, file: file, line: line)
        XCTAssertEqual(card.sourceDraft?.text, raw, file: file, line: line)
        XCTAssertEqual(card.sourceDraft?.unknownServings, true, file: file, line: line)
        XCTAssertNil(card.pastedSource, file: file, line: line)
    }

    func testExactDeviceCaptionKeepsAllFiveIngredientsAndOnlyWrittenMethod() throws {
        let card = try XCTUnwrap(MultilineCaptionImport.card(caption))
        assertExact(card, raw: caption)
        let unframed = caption.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        assertExact(try XCTUnwrap(MultilineCaptionImport.card(unframed)), raw: unframed)
        let restored = try JSONDecoder().decode(RecipeCard.self, from: JSONEncoder().encode(card))
        assertExact(restored, raw: caption)
    }

    func testExactCaptionBypassesTruncatedClassifierAndUnavailableModel() async throws {
        let unframed = caption.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        for (raw, titleIndex, firstIngredient) in [(caption, 1, 2), (unframed, 0, 1)] {
            for count in [2, 3] {
                for available in [true, false] {
                    var modelCalls = 0, classifierCalls = 0
                    let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { available },
                        modelWillGenerate: { modelCalls += 1 }, selectSourceLines: { _ in
                            classifierCalls += 1
                            // The incomplete selection matching the device failure shape.
                            return .init(title: titleIndex, ingredients: Array(firstIngredient..<(firstIngredient + count)), method: [firstIngredient + 5])
                        })
                    let card = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: raw), using: backend).card
                    assertExact(card, raw: raw)
                    XCTAssertEqual(modelCalls, 0)
                    XCTAssertEqual(classifierCalls, 0)
                }
            }
        }
    }

    func testExactCaptionDoesNotInventGeneratedThinnessOrOfferImpossibleRepair() throws {
        let card = try XCTUnwrap(MultilineCaptionImport.card(caption))
        let restored = try JSONDecoder().decode(RecipeCard.self, from: JSONEncoder().encode(card))
        XCTAssertFalse(RecipeQuality.issues(restored).contains { $0.contains("ingredients with quantities") })
        XCTAssertFalse(RecipeDraftRepair.canRepair(restored))
        XCTAssertThrowsError(try RecipeDraftRepair.instruction(for: restored))
        assertExact(restored, raw: caption)
        var generated = restored
        generated.source = .appleIntelligence
        generated.sourceDraft = nil
        XCTAssertTrue(RecipeQuality.issues(generated).contains { $0.contains("ingredients with quantities (has 0)") })
        XCTAssertTrue(RecipeDraftRepair.canRepair(generated))
        XCTAssertNoThrow(try RecipeDraftRepair.instruction(for: generated))
    }

    func testExactCaptionUnspecifiedServingsNeedInputAndNutritionStaysUnavailable() throws {
        let card = try XCTUnwrap(MultilineCaptionImport.card(caption))
        let calculator = RecipeNutritionCalculator(foods: NutritionFoodCatalogue.records)
        XCTAssertTrue(RecipeNutritionCalculator.servingsAreUnspecified(card))
        let result = calculator.calculate(card)
        XCTAssertEqual(result.incompleteIngredients, [card.title + " (servings needed)"])
        XCTAssertFalse(result.isComplete)
        XCTAssertNil(result.perServing)
        XCTAssertNil(result.totalRecipe)
        XCTAssertTrue(result.contributions.isEmpty)
        var invalid = card
        invalid.servings = -1
        XCTAssertFalse(RecipeNutritionCalculator.servingsAreUnspecified(invalid))
        XCTAssertEqual(calculator.calculate(invalid).incompleteIngredients, [card.title + " (invalid servings)"])
        var supplied = card
        supplied.servings = 4
        XCTAssertFalse(RecipeNutritionCalculator.servingsAreUnspecified(supplied))
        XCTAssertNil(calculator.calculate(supplied).perServing, "Servings alone cannot supply missing structured quantities or verified nutrient data")
        assertExact(card, raw: caption)
    }

    func testExactCaptionNutritionNeedsServingsMessageRetainsNativeScreenshot() throws {
        let card = try XCTUnwrap(MultilineCaptionImport.card(caption))
        let renderer = ImageRenderer(content: RecipeNutritionView(recipe: card)
            .frame(width: 361).environment(\.dynamicTypeSize, .large))
        renderer.scale = 2
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "caption-nutrition-servings-needed-no-guessed-values"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAmbiguousOrUnboundedCaptionIsNotDeterministicallyRegrouped() {
        for text in [
            caption.replacingOccurrences(of: "Method:", with: "Then"),
            caption.replacingOccurrences(of: "1 tsp paprika", with: "Method: Fry paprika."),
            caption.replacingOccurrences(of: "salt and pepper", with: "Please read the agenda."),
            caption.replacingOccurrences(of: "4 chicken thighs", with: "chicken thighs"),
            "Beef stroganoff",
            "The quarterly report is due Friday. Please send the updated figures to the team before the meeting."
        ] {
            XCTAssertNil(MultilineCaptionImport.card(text), text)
        }
    }
}
