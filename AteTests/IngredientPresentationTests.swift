import XCTest
@testable import Ate

final class IngredientPresentationTests: XCTestCase {
    func testIdenticalLemonServingRowsDisplayOnceIncludingWhitespaceAndPrepCase() {
        let first = Ingredient(name: "for serving", quantity: 1, unit: "lemon", notes: "sliced")
        let duplicate = Ingredient(name: " for  serving ", quantity: 1, unit: "lemon", notes: " SLICED ")
        XCTAssertEqual(IngredientPresentation.rows([first, duplicate], units: .metric), [first])
        let normal = Ingredient(name: "lemon, for serving", quantity: 1, unit: "pcs", notes: "sliced")
        XCTAssertEqual(IngredientPresentation.rows([normal, normal], units: .metric), [normal])
    }
    func testDifferentAmountsIngredientsAndUsesRemainSeparate() {
        let ingredients = [Ingredient(name: "lemon", quantity: 1, unit: "pcs", notes: "sliced"),
                           Ingredient(name: "lemon", quantity: 2, unit: "pcs", notes: "sliced"),
                           Ingredient(name: "lemon", quantity: 1, unit: "pcs", notes: "juiced"),
                           Ingredient(name: "lime", quantity: 1, unit: "pcs", notes: "sliced")]
        XCTAssertEqual(IngredientPresentation.rows(ingredients, units: .metric), ingredients)
        XCTAssertEqual(IngredientPresentation.rows(ingredients, units: .imperial), ingredients)
    }
    func testNutritionWarningNamesAppearOnceWithoutChangingCalculationInputs() {
        let names = ["lemon, for serving", " Lemon,  for serving ", "potatoes", "potatoes"]
        XCTAssertEqual(IngredientPresentation.uniqueNames(names), ["lemon, for serving", "potatoes"])
        let original = RecipeCard(ingredients: [.init(name: "unmapped lemon", quantity: 1, unit: "pcs"),
                                                .init(name: "unmapped lemon", quantity: 1, unit: "pcs")])
        let result = RecipeNutritionCalculator(foods: []).calculate(original)
        XCTAssertEqual(result.unmappedIngredients.count, 2, "Display cleanup must not alter calculation/source rows")
        XCTAssertEqual(IngredientPresentation.uniqueNames(result.unmappedIngredients), ["unmapped lemon"])
        XCTAssertEqual(original.ingredients.count, 2)
    }
    func testEmptyAndNilNotesAreTheSameVisibleRow() {
        let a = Ingredient(name: "lemon", quantity: 1, unit: "pcs", notes: nil)
        let b = Ingredient(name: "lemon", quantity: 1, unit: "pcs", notes: "")
        XCTAssertEqual(IngredientPresentation.rows([a, b], units: .metric), [a])
    }
    func testImperialRoundedConversionCollisionPreservesBothSourceQuantities() {
        let rows = [Ingredient(name: "lemon", quantity: 100, unit: "g", notes: "sliced"),
                    Ingredient(name: "lemon", quantity: 101, unit: "g", notes: "sliced")]
        let first = Units.convert(quantity: 100, unit: "g", to: .imperial)
        let second = Units.convert(quantity: 101, unit: "g", to: .imperial)
        XCTAssertEqual(Units.formatAmount(first.0, first.1), Units.formatAmount(second.0, second.1))
        for units in [UnitSystem.metric, .imperial] {
            XCTAssertEqual(IngredientPresentation.rows(rows, units: units), rows)
        }
    }
    func testMetricFormattedQuantityCollisionPreservesBothSourceQuantitiesAndUnits() {
        let rows = [Ingredient(name: "lemon", quantity: 1.001, unit: "g", notes: "sliced"),
                    Ingredient(name: "lemon", quantity: 1.002, unit: "g", notes: "sliced")]
        XCTAssertEqual(Units.formatAmount(1.001, "g"), Units.formatAmount(1.002, "g"))
        for units in [UnitSystem.metric, .imperial] {
            XCTAssertEqual(IngredientPresentation.rows(rows, units: units), rows)
        }
        let differentUnits = [Ingredient(name: "lemon", quantity: 1, unit: "g", notes: "sliced"),
                              Ingredient(name: "lemon", quantity: 1, unit: "kg", notes: "sliced")]
        XCTAssertEqual(IngredientPresentation.rows(differentUnits, units: .metric), differentUnits)
    }

}
