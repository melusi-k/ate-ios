import XCTest
@testable import Ate

@MainActor
final class SiriRoutingTests: XCTestCase {
    let lib = [RecipeCard(id: "ccr", title: "Classic Chicken and Rice", ingredients: [Ingredient(name: "rice", quantity: 1, unit: "cup"), Ingredient(name: "chicken thighs", quantity: 4, unit: "")]),
               RecipeCard(id: "mog", title: "Mogodu"),
               RecipeCard(id: "pasta", title: "Tomato Pasta", tags: ["vegan"])]

    func testCleanQueryStripsVerbAndAppName() {
        XCTAssertEqual(RecipeMatcher.cleanQuery("Cook Rice in Ate").query, "rice")
        XCTAssertEqual(RecipeMatcher.cleanQuery("Cook Rice in Ate").verb, .cook)
        XCTAssertEqual(RecipeMatcher.cleanQuery("make mogodu with ate").query, "mogodu")
        XCTAssertEqual(RecipeMatcher.cleanQuery("start cook mode for Mogodu").query, "mogodu")
        XCTAssertEqual(RecipeMatcher.cleanQuery("search for pasta").verb, .search)
        XCTAssertEqual(RecipeMatcher.cleanQuery("search for pasta").query, "pasta")
        XCTAssertNil(RecipeMatcher.cleanQuery("tripe").verb)
    }
    func testTokenSearchFindsRiceRecipe() {
        XCTAssertTrue(RecipeLogic.matches(lib[0], query: "Cook Rice"))
        XCTAssertTrue(RecipeLogic.matches(lib[0], query: "chicken rice"))
        XCTAssertFalse(RecipeLogic.matches(lib[1], query: "Cook Rice"))
        XCTAssertTrue(RecipeLogic.matches(lib[2], query: "vegan pasta"))
    }
    func testPartialNameResolves() {
        let hits = RecipeMatcher.rank(lib, query: RecipeMatcher.cleanQuery("Cook Rice in Ate").query)
        XCTAssertEqual(hits.first?.recipe.id, "ccr")
        XCTAssertTrue(RecipeMatcher.isConfident(hits))
        XCTAssertEqual(RecipeMatcher.rank(lib, query: "chicken rice").first?.recipe.id, "ccr")
    }
    func testAmbiguousPartialNeedsDisambiguation() {
        let two = lib + [RecipeCard(id: "fr", title: "Fried Rice")]
        let hits = RecipeMatcher.rank(two, query: "rice")
        XCTAssertFalse(RecipeMatcher.isConfident(hits))
        XCTAssertEqual(Set(RecipeMatcher.nearTop(hits).map(\.recipe.id)), ["ccr", "fr"])
    }
    func testSynonymsAndShortcutLimits() {
        let syn = RecipeAppEntity.synonyms(title: "Classic Chicken and Rice")
        XCTAssertTrue(syn.contains("rice")); XCTAssertTrue(syn.contains("chicken"))
        XCTAssertLessThanOrEqual(AteShortcuts.phraseCatalog.count, 10)
        XCTAssertTrue(AteShortcuts.phraseCatalog.flatMap(\.phrases).allSatisfy { $0.lowercased().contains("ate") })
    }
}

@MainActor
final class SiriPolishTests: XCTestCase {
    func testPickLinePunctuation() {
        XCTAssertEqual(SiriAnswers.pickLine(title: "Chotlo with Setswana Ting ", health: nil, why: "one of your favourites."),
                       "Tonight's pick is Chotlo with Setswana Ting. One of your favourites.")
    }
    func testImplausibleQuickTimeExcluded() {
        let feet = RecipeCard(id: "f", title: "Amanqina Enkukhu", timeMinutes: 3)
        let ok = RecipeCard(id: "o", title: "Omelette", timeMinutes: 10)
        XCTAssertNil(Durations.plausibleQuickMinutes(feet))
        XCTAssertEqual(SiriAnswers.quick([feet, ok]).map(\.id), ["o"])
    }
}
