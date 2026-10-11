import XCTest
@testable import Ate

/// C-FIX-01 / C-FIX-02: implausible step times and blank steps (build 81 feedback).
final class RecipeCleanupTests: XCTestCase {
    private func nyama() -> RecipeCard {
        RecipeCard(title: "Nyama yenkomo with pap, spinach and cabbage", servings: 4, timeMinutes: 10,
                   ingredients: [.init(name: "beef", quantity: 800, unit: "g")],
                   steps: [.init(order: 1, instruction: "Brown the beef in oil", timeSeconds: 120),
                           .init(order: 2, instruction: "Add water and simmer", timeSeconds: 240),
                           .init(order: 3, instruction: "Cook the pap until soft", timeSeconds: 180),
                           .init(order: 4, instruction: "Steam the spinach", timeSeconds: 60),
                           .init(order: 5, instruction: "Simmer for 45 minutes", timeSeconds: 240),
                           .init(order: 6, instruction: "   ", timeSeconds: nil),
                           .init(order: 7, instruction: "", timeSeconds: 60)],
                   source: .appleIntelligence)
    }
    func testMinimumsByKeyword() {
        XCTAssertEqual(Durations.minimumSeconds(for: "Add water and simmer"), 1200)
        XCTAssertEqual(Durations.minimumSeconds(for: "Cook pap until soft"), 900)
        XCTAssertEqual(Durations.minimumSeconds(for: "Brown beef in oil"), 300)
        XCTAssertEqual(Durations.minimumSeconds(for: "Braise the oxtail"), 3600)
        XCTAssertNil(Durations.minimumSeconds(for: "Season with salt"))
        XCTAssertNil(Durations.minimumSeconds(for: "Add the papaya"), "word boundary: 'pap' must not match 'papaya'")
    }
    func testImplausibleModelTimesAreDroppedAndFlagged() {
        let c = RecipeLogic.normalize(nyama())
        XCTAssertNil(c.steps[0].timeSeconds); XCTAssertNil(c.steps[1].timeSeconds)
        XCTAssertNil(c.steps[2].timeSeconds); XCTAssertEqual(c.steps[3].timeSeconds, nil)
        XCTAssertEqual(c.steps[4].timeSeconds, 45 * 60, "time written in the text wins")
        XCTAssertTrue(c.aiNote?.contains("cooking times") == true)
    }
    func testPlausibleModelTimeKept() {
        let c = Durations.sanitize(RecipeCard(steps: [.init(order: 1, instruction: "Simmer", timeSeconds: 1800)])).card
        XCTAssertEqual(c.steps[0].timeSeconds, 1800)
    }
    func testBlankStepsRemovedEverywhere() {
        let n = RecipeLogic.normalize(nyama())
        XCTAssertEqual(n.steps.count, 5); XCTAssertEqual(n.steps.map(\.order), [1, 2, 3, 4, 5])
        XCTAssertEqual(RecipeLogic.scaled(nyama(), factor: 3).steps.count, 5)
        let data = try! JSONEncoder().encode(nyama())
        XCTAssertEqual(try! JSONDecoder().decode(RecipeCard.self, from: data).steps.count, 5, "saved data is cleaned on decode")
    }
}
