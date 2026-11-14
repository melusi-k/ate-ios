import XCTest
@testable import Ate
#if canImport(FoundationModels)
import FoundationModels
#endif

final class RecipeGenerationToolTests: XCTestCase {
    private var ingredients: [Ingredient] {
        [.init(name: "onion", quantity: 1, unit: "pcs", notes: "diced"),
         .init(name: "garlic", quantity: 2, unit: "cloves", notes: "crushed")]
    }
    private var steps: [Step] {
        [.init(order: 1, instruction: "Chop the onion and garlic.", timeSeconds: nil)]
    }
    func testGateDefaultsOffAndOnlyPromptSocialCanOptIn() {
        XCTAssertFalse(RecipeGenerationToolGate.applies(enabled: false, input: .prompt))
        for input in [RecipePrompt.Input.link, .photo, .screenshot, .rewrite] {
            XCTAssertFalse(RecipeGenerationToolGate.applies(enabled: true, input: input))
        }
        XCTAssertTrue(RecipeGenerationToolGate.applies(enabled: true, input: .prompt))
        XCTAssertTrue(RecipeGenerationToolGate.applies(enabled: true, input: .social))
    }
    func testDeterministicValidatedFieldsAndUnitPlacement() throws {
        XCTAssertEqual(try RecipeStructureValidation.validate(ingredients: ingredients, steps: steps),
                       try RecipeStructureValidation.signature(ingredients: ingredients, steps: steps))
        for bad in [Ingredient(name: "diced", quantity: 1, unit: "onion"),
                    Ingredient(name: "onion", quantity: .infinity, unit: "pcs"),
                    Ingredient(name: "onion", quantity: -1, unit: "pcs"),
                    Ingredient(name: "onion", quantity: 0, unit: "pcs"),
                    Ingredient(name: "onion", quantity: 1, unit: "imaginary-unit"),
                    Ingredient(name: "", quantity: 1, unit: "pcs")] {
            XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: [bad], steps: steps))
        }
        XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: [], steps: steps))
        XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: ingredients, steps: []))
        XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: ingredients,
            steps: [.init(order: 2, instruction: "Chop the onion and garlic.", timeSeconds: nil)]))
        XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: ingredients,
            steps: [.init(order: 1, instruction: "...", timeSeconds: -1)]))
    }
    func testKnownPreparationOnlyNamesAreRejectedWithoutGuessingFood() throws {
        let collective = [Step(order: 1, instruction: "Mix all ingredients.", timeSeconds: nil)]
        for name in ["diced", "finely chopped", "  FINELY, chopped!  "] {
            let ingredient = Ingredient(name: name, quantity: 1, unit: "pcs")
            XCTAssertTrue(IngredientFieldNormalization.isPreparationOnly(name))
            XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: [ingredient], steps: collective))
            XCTAssertEqual(ingredient.name, name)
        }
        XCTAssertFalse(IngredientFieldNormalization.isPreparationOnly("onion"))
        XCTAssertNoThrow(try RecipeStructureValidation.validate(ingredients: ingredients, steps: collective))
    }
    func testAchariPasteMustBeListedNotInventedByValidator() {
        let before = ingredients
        XCTAssertThrowsError(try RecipeStructureValidation.validate(ingredients: before,
            steps: [.init(order: 1, instruction: "Add the onion, garlic and achari paste.", timeSeconds: nil)]))
        XCTAssertEqual(before, ingredients)
    }
    func testReceiptFailsClosedWithoutCallOnMismatchAndAfterInvalidCall() async throws {
        let signature = try RecipeStructureValidation.validate(ingredients: ingredients, steps: steps)
        let receipt = RecipeStructureReceipt()
        do { try await receipt.require(signature); XCTFail("No tool call must fail") } catch {}
        try await receipt.record(signature)
        try await receipt.require(signature)
        do { try await receipt.require("different"); XCTFail("Mismatched final fields must fail") } catch {}
        await receipt.reject()
        do { try await receipt.require(signature); XCTFail("Any invalid call poisons this request") } catch {}
    }
    func testRepeatedCallsAreBoundedAndCannotBypassRejection() async throws {
        let receipt = RecipeStructureReceipt()
        for i in 0..<8 { try await receipt.record("structure-\(i)") }
        try await receipt.require("structure-7")
        do { try await receipt.record("ninth"); XCTFail("Calls are bounded") } catch {}
        do { try await receipt.require("structure-7"); XCTFail("Over-limit request must fail closed") } catch {}
    }
#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func testTypedToolRejectsPrepOnlyNameAndPoisonsPriorReceipt() async throws {
        for name in ["diced", "finely chopped"] {
            let receipt = RecipeStructureReceipt()
            let tool = RecipeGenerationTool(receipt: receipt)
            let valid = RecipeGenerationTool.Arguments(
                ingredients: [.init(quantity: 1, unit: "pcs", name: "onion", prep: nil)],
                steps: [.init(instruction: "Mix all ingredients.", minutes: nil, temperatureC: nil)])
            let accepted = try await tool.call(arguments: valid)
            try await receipt.require(accepted)
            var invalid = valid
            invalid.ingredients[0].name = name
            do { _ = try await tool.call(arguments: invalid); XCTFail("Prep-only name must fail even with valid unit") } catch {}
            do { try await receipt.require(accepted); XCTFail("Prep-only call must poison the previous receipt") } catch {}
        }
    }
    @available(iOS 26.0, *)
    func testActualToolCallValidatesTypedArgumentsAndReceiptWithoutModel() async throws {
        let receipt = RecipeStructureReceipt()
        let tool = RecipeGenerationTool(receipt: receipt)
        let arguments = RecipeGenerationTool.Arguments(
            ingredients: [.init(quantity: 1, unit: "pcs", name: "onion", prep: "diced"),
                          .init(quantity: 2, unit: "cloves", name: "garlic", prep: "crushed")],
            steps: [.init(instruction: "Chop the onion and garlic.", minutes: nil, temperatureC: nil)])
        let result = try await tool.call(arguments: arguments)
        try await receipt.require(result)
        var invalid = arguments
        invalid.steps[0].minutes = -1
        do { _ = try await tool.call(arguments: invalid); XCTFail("Invalid raw minutes must fail") } catch {}
        do { try await receipt.require(result); XCTFail("Invalid call cannot leave an accepted receipt") } catch {}
    }
#endif
}
