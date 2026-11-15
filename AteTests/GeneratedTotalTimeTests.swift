import XCTest
@testable import Ate

final class GeneratedTotalTimeTests: XCTestCase {
    private func card(stepMinutes: Int, prep: Int?, total: Int?) -> RecipeCard {
        var card = RecipeCard(title: "Fixture recipe", timeMinutes: total,
            ingredients: [.init(name: "onion", quantity: 1, unit: "pcs")],
            steps: [.init(order: 1, instruction: "Simmer until tender for \(stepMinutes) minutes.", timeSeconds: stepMinutes * 60)],
            source: .appleIntelligence)
        card.aiNote = prep.map { "Prep: \($0) min" }
        return card
    }

    func testFourDeviceRegressionsMatchWrittenStepSumPlusPrep() {
        for (steps, prep, wrong, expected) in [(93, 25, 111, 118), (10, 10, 10, 20),
                                             (23, 10, 23, 33), (140, 12, 150, 152)] {
            let result = RecipeLogic.normalize(card(stepMinutes: steps, prep: prep, total: wrong))
            XCTAssertEqual(result.timeMinutes, expected)
            XCTAssertFalse(GeneratedRecipeConsistency.issues(result).contains { $0.contains("Total time") })
            XCTAssertEqual(RecipeLogic.normalize(result).timeMinutes, expected, "Normalization must be idempotent")
        }
    }

    func testWrittenTimeCorrectionAlsoRewritesTotalUsingPrepNotOldModelValue() {
        var original = card(stepMinutes: 20, prep: 12, total: 99)
        original.steps[0].timeSeconds = 20
        let result = RecipeLogic.normalize(original)
        XCTAssertEqual(result.steps[0].timeSeconds, 1200)
        XCTAssertEqual(result.timeMinutes, 32)
        XCTAssertTrue(result.aiNote?.contains("cooking times") == true)
        XCTAssertFalse(GeneratedRecipeConsistency.issues(result).contains { $0.contains("Total time") })
    }

    func testNoSeparatePrepUsesOnlyStepSumAndNoInventedPrep() {
        let result = RecipeLogic.normalize(card(stepMinutes: 20, prep: nil, total: 40))
        XCTAssertEqual(result.timeMinutes, 20)
        XCTAssertFalse(result.aiNote?.contains("Prep:") == true)
    }

    func testExplicitPrepIsNotTruncatedByIngredientCountCap() {
        let result = RecipeLogic.normalize(card(stepMinutes: 93, prep: 25, total: 111))
        XCTAssertEqual(result.timeMinutes, 118)
    }

    func testFractionalStepMinutesRoundOnceAfterSummingSeconds() {
        var original = card(stepMinutes: 1, prep: 10, total: nil)
        original.steps = [.init(order: 1, instruction: "Wait 30 seconds.", timeSeconds: 30),
                          .init(order: 2, instruction: "Wait 30 seconds.", timeSeconds: 30)]
        XCTAssertEqual(RecipeLogic.normalize(original).timeMinutes, 11)
    }

    func testNonGeneratedCardsRetainLegacyNormalizationContract() {
        var original = card(stepMinutes: 20, prep: 25, total: 22)
        original.source = .manual
        XCTAssertEqual(Durations.sanitize(original).card.timeMinutes, 22)
        original.source = .jsonLD
        XCTAssertEqual(Durations.sanitize(original).card.timeMinutes, 22)
    }

    func testAmbiguousPrepIsNotSilentlyDroppedToForceAConsistentTotal() {
        var original = card(stepMinutes: 20, prep: nil, total: 35)
        original.aiNote = "Prep: 10-15 min"
        let result = RecipeLogic.normalize(original)
        XCTAssertEqual(result.timeMinutes, 35)
        XCTAssertTrue(GeneratedRecipeConsistency.issues(result).contains { $0.contains("Clarify one explicit") })
    }

    func testMixedValidMalformedDeclarationsAndPartialValuesFailClosed() {
        for note in ["Prep:10min. Prep:10-15min", "Prep:10min. Prep :12min",
                     "Prep:10min plus30seconds", "Prep : 10 min and 30 seconds",
                     "Prep:10min30seconds", "Prep:10min.5seconds", "Prep:10min; plus30seconds",
                     "Prep:10min. plus 30 seconds", "Prep:10min, 30seconds"] {
            XCTAssertNil(GeneratedRecipeConsistency.prepMinutes(in: note), note)
            var original = card(stepMinutes: 20, prep: nil, total: 35)
            original.aiNote = note
            let result = RecipeLogic.normalize(original)
            XCTAssertEqual(result.timeMinutes, 35, note)
            XCTAssertTrue(GeneratedRecipeConsistency.issues(result).contains { $0.contains("Clarify one explicit") }, note)
        }
        XCTAssertEqual(GeneratedRecipeConsistency.prepMinutes(in: "Prep :12min. Check doneness."), 12)
    }

    func testUntrustedPrepIsBoundedBeforeAnyAddition() {
        for value in [String(Int.max), String(Int.max - 1), "9223372036854775808",
                      "9999999999999999999999999999999999999", String(Durations.maxTotalMinutes + 1)] {
            let note = "Prep:\(value)min"
            XCTAssertNil(GeneratedRecipeConsistency.prepMinutes(in: note), value)
            var original = card(stepMinutes: 20, prep: nil, total: 35)
            original.aiNote = note
            XCTAssertEqual(RecipeLogic.normalize(original).timeMinutes, 35)
            XCTAssertTrue(GeneratedRecipeConsistency.issues(original).contains { $0.contains("Clarify one explicit") })
        }
        XCTAssertNil(GeneratedRecipeConsistency.totalMinutes(stepMinutes: Int.max, prepMinutes: 1))
        XCTAssertNil(GeneratedRecipeConsistency.totalMinutes(stepMinutes: 1, prepMinutes: Int.max))
        XCTAssertNil(GeneratedRecipeConsistency.totalMinutes(stepMinutes: 20, prepMinutes: Durations.maxTotalMinutes))
        XCTAssertEqual(GeneratedRecipeConsistency.totalMinutes(stepMinutes: 20, prepMinutes: Durations.maxTotalMinutes - 20), Durations.maxTotalMinutes)
        var nearLimit = card(stepMinutes: 20, prep: Durations.maxTotalMinutes, total: 35)
        XCTAssertTrue(GeneratedRecipeConsistency.issues(nearLimit).contains { $0.contains("supported limit") })
        XCTAssertEqual(RecipeLogic.normalize(nearLimit).timeMinutes, 35)
        nearLimit.steps[0].timeSeconds = Int.max
        XCTAssertTrue(GeneratedRecipeConsistency.issues(nearLimit).contains { $0.contains("Step time sum") })
    }

    func testMissingTotalCannotHideMalformedOrOverflowPrepGap() {
        for note in ["Prep:10-15min", "Prep:10min plus30seconds", "Prep:\(Int.max)min"] {
            var original = card(stepMinutes: 20, prep: nil, total: nil)
            original.aiNote = note
            let normalized = RecipeLogic.normalize(original)
            XCTAssertNil(normalized.timeMinutes)
            XCTAssertTrue(GeneratedRecipeConsistency.issues(normalized).contains { $0.contains("Clarify one explicit") })
        }
    }

    func testPrepParserRequiresOneExplicitStatement() {
        XCTAssertEqual(GeneratedRecipeConsistency.prepMinutes(in: "Prep: 12 min. Rest as directed."), 12)
        XCTAssertEqual(GeneratedRecipeConsistency.prepMinutes(in: "Prep: 0 min"), 0)
        XCTAssertNil(GeneratedRecipeConsistency.prepMinutes(in: "Prep: 10 min. Prep: 12 min"))
        XCTAssertNil(GeneratedRecipeConsistency.prepMinutes(in: "Prep: 10-12 min"))
    }
    func testLegacyPhotoTotalKeepsBoundedPrepGapWithoutInventingPrepNote() {
        var original = RecipeCard(title: "Sandwich", timeMinutes: 30,
            ingredients: [.init(name: "cheese", quantity: 2, unit: "slices"),
                          .init(name: "polony", quantity: 3, unit: "slices")],
            steps: [.init(order: 1, instruction: "Layer cheese and polony", timeSeconds: 120),
                    .init(order: 2, instruction: "Toast sandwich in pan", timeSeconds: 300)],
            source: .photoGuess)
        let bounded = Durations.sanitize(original).card
        XCTAssertEqual(bounded.timeMinutes, 12)
        XCTAssertNil(bounded.aiNote, "Do not fabricate an exact Prep statement")
        XCTAssertTrue(GeneratedRecipeConsistency.issues(bounded).contains { $0.contains("Explain the extra 5 minutes") })
        XCTAssertEqual(Durations.sanitize(bounded).card.timeMinutes, 12)
        original.aiNote = "Prep: 12 min"
        XCTAssertEqual(Durations.sanitize(original).card.timeMinutes, 19, "Explicit photo prep must not be legacy-capped")
        original.aiNote = "Prep: 10-15 min"
        XCTAssertEqual(Durations.sanitize(original).card.timeMinutes, 30, "Malformed photo prep stays a visible gap")
        XCTAssertTrue(GeneratedRecipeConsistency.issues(original).contains { $0.contains("Clarify one explicit") })
    }

}
