import XCTest
@testable import Ate

final class PhotoQuestionChoiceTests: XCTestCase {
    func testScallopFamilyCannotConsumeAllQuestionChoices() {
        let options = PhotoGuess.questionSuggestions(["Scallop", "Shellfish", "Seafood with scallop", "Seafood", "Scallops"])
        XCTAssertEqual(options.first, "Scallop")
        XCTAssertTrue(options.contains("Fish"))
        XCTAssertTrue(options.contains("Vegetable dish"))
        XCTAssertLessThanOrEqual(options.count, 5)
    }
    func testGeneratedCardQuestionUsesTheSameDiverseChoices() {
        var card = RecipeCard(title: "Scallop", source: .photoGuess)
        card.aiAlternatives = ["Shellfish", "Seafood with scallop", "Seafood", "Scallops"]
        XCTAssertTrue(RecipeQuality.guesses(card).contains("Fish"))
        XCTAssertTrue(RecipeQuality.guesses(card).contains("Vegetable dish"))
    }
    func testGenericChoicesAreUniqueAndNotUsedAsConfidenceEvidence() {
        let result = PhotoGuess.questionSuggestions(["Fish", "fish", " Fish ", "Salmon"])
        XCTAssertEqual(result.filter { $0.lowercased() == "fish" }.count, 1)
        XCTAssertTrue(result.contains("Vegetable dish"))
        // Choice list construction must never mutate the classifier's evidence.
        XCTAssertTrue(PhotoGuess.questionSuggestions([]).contains("Fish"))
    }
    func testTextPromptQuestionKeepsItsOwnAlternativesWithoutPhotoClasses() {
        var card = RecipeCard(title: "Mogodu", source: .appleIntelligence)
        card.aiAlternatives = ["Ulusu", "Tripe curry", "Stew", "Beef stew", "Extra"]
        XCTAssertEqual(RecipeQuality.guesses(card), ["Mogodu", "Ulusu", "Tripe curry", "Stew", "Beef stew"])
        XCTAssertFalse(RecipeQuality.guesses(card).contains("Fish"))
        XCTAssertFalse(RecipeQuality.guesses(card).contains("Vegetable dish"))
    }

    func testWholePlateLimitIsExplicitRatherThanImpliedFidelity() {
        XCTAssertTrue(PhotoGuess.plateLimitNote.contains("not a reconstruction"))
        XCTAssertTrue(PhotoGuess.plateLimitNote.contains("garnishes, sauces and sides were left out"))
    }
}
