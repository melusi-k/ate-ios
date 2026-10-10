import XCTest
@testable import Ate

final class DurationTests: XCTestCase {
    func testSimpleMinutes() {
        XCTAssertEqual(Durations.seconds(in: "Simmer covered for 20 minutes"), 1200)
        XCTAssertEqual(Durations.seconds(in: "Fry 5 min."), 300)
        XCTAssertEqual(Durations.seconds(in: "Rest 30 seconds"), 30)
    }
    func testRangesUseUpperBound() {
        XCTAssertEqual(Durations.spans(in: "simmer 2 to 3 h until tender"), [.init(lower: 7200, upper: 10800)])
        XCTAssertEqual(Durations.seconds(in: "simmer 2 to 3 h until tender"), 10800)
        XCTAssertEqual(Durations.seconds(in: "Cook 2-3 hours"), 10800)
        XCTAssertEqual(Durations.seconds(in: "Bake 8–10 mins"), 600)
        XCTAssertEqual(Durations.rangeLabel(in: "simmer 2 to 3 h until tender"), "120–180 min")
        XCTAssertNil(Durations.rangeLabel(in: "simmer 20 minutes"))
    }
    func testCompoundAndDecimal() {
        XCTAssertEqual(Durations.seconds(in: "Roast 1 hr 15 min"), 4500)
        XCTAssertEqual(Durations.seconds(in: "Steam 1.5 h"), 5400)
        XCTAssertEqual(Durations.seconds(in: "Steam ½ hour"), 1800)
    }
    func testNoDuration() {
        XCTAssertNil(Durations.seconds(in: "Add chicken and cook until browned"))
        XCTAssertNil(Durations.seconds(in: "Heat oven to 200°C, add 350 g flour"))
    }
    func testSanitizeTrustsStepText() {
        let card = RecipeCard(servings: 4, timeMinutes: 3000, ingredients: [], steps: [
            Step(order: 1, instruction: "Add chicken and cook until browned", timeSeconds: 3000),
            Step(order: 2, instruction: "Stir in rice and broth", timeSeconds: 4500),
            Step(order: 3, instruction: "Simmer covered for 20 minutes", timeSeconds: 10000)])
        let r = Durations.sanitize(card)
        XCTAssertTrue(r.corrected)
        XCTAssertEqual(r.card.steps.map(\.timeSeconds), [nil, nil, 1200])  // model units broken → untimed guesses dropped
        XCTAssertEqual(r.card.timeMinutes, 20)
    }
    func testMogoduRangeAndTotal() {
        let card = RecipeCard(servings: 6, timeMinutes: 3000, ingredients: [], steps: [
            Step(order: 1, instruction: "Simmer 2 to 3 h until tender", timeSeconds: 180000)])
        let r = RecipeLogic.normalize(card)
        XCTAssertEqual(r.steps[0].timeSeconds, 10800)
        XCTAssertEqual(r.timeMinutes, 180)
        XCTAssertNotNil(r.aiNote)
    }
    func testPlausibleUntouched() {
        let card = RecipeCard(servings: 2, timeMinutes: 25, ingredients: [], steps: [
            Step(order: 1, instruction: "Fry the onion 5 min.", timeSeconds: 300),
            Step(order: 2, instruction: "Roast until golden", timeSeconds: 900)])
        let r = Durations.sanitize(card)
        XCTAssertFalse(r.corrected)
        XCTAssertEqual(r.card.steps.map(\.timeSeconds), [300, 900])
        XCTAssertEqual(r.card.timeMinutes, 25)
    }
    func testTimesNeverScaleWithServings() {
        let card = RecipeCard(servings: 6, timeMinutes: 180, ingredients: [Ingredient(name: "tripe", quantity: 1.2, unit: "kg", notes: nil)],
                              steps: [Step(order: 1, instruction: "Simmer 2 to 3 h", timeSeconds: 10800)])
        let s = RecipeLogic.scaled(card, factor: 3)
        XCTAssertEqual(s.servings, 18)
        XCTAssertEqual(s.ingredients[0].quantity, 3.6, accuracy: 0.001)
        XCTAssertEqual(s.timeMinutes, 180)
        XCTAssertEqual(s.steps[0].timeSeconds, 10800)
    }
}
