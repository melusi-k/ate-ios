import XCTest
@testable import Ate

final class ExploreRecipesTests: XCTestCase {
    private func card(_ id: String, minutes: Int? = nil, favourite: Bool = false, created: Double = 1) -> RecipeCard {
        var recipe = RecipeCard(id: id, title: id, timeMinutes: minutes, createdAt: created)
        recipe.favorite = favourite
        return recipe
    }
    func testQuickIncludesThirtyButNotUnknownZeroNegativeOrLong() {
        let groups = ExploreRecipes.groups(recipes: [card("thirty", minutes: 30), card("fast", minutes: 10), card("unknown"), card("zero", minutes: 0), card("negative", minutes: -1), card("slow", minutes: 31)], completed: [:])
        XCTAssertEqual(groups[0].recipes.map(\.id), ["fast", "thirty"])
    }
    func testCookAgainRequiresCompletedHistoryNotOpenTimestampAndIgnoresDeletedReferences() {
        var opened = card("opened"); opened.lastCookedAt = 100
        let groups = ExploreRecipes.groups(recipes: [opened, card("cooked"), card("older")], completed: ["2026-11-12": ["cooked", "deleted"], "2026-11-11": ["older"]])
        XCTAssertEqual(groups[2].recipes.map(\.id), ["cooked", "older"])
    }
    func testFavouritesAndTiesAreStableAndInputsUnchanged() {
        let input = [card("b", minutes: 15, favourite: true), card("a", minutes: 15, favourite: true), card("c", favourite: true, created: 2)]
        let groups = ExploreRecipes.groups(recipes: input, completed: [:])
        XCTAssertEqual(groups[0].recipes.map(\.id), ["a", "b"])
        XCTAssertEqual(groups[1].recipes.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(input.map(\.id), ["b", "a", "c"])
    }
    func testEmptyAndDuplicateIdentities() {
        XCTAssertTrue(ExploreRecipes.groups(recipes: [], completed: [:]).allSatisfy { $0.recipes.isEmpty })
        let groups = ExploreRecipes.groups(recipes: [card("a", favourite: true), card("a", favourite: true)], completed: [:])
        XCTAssertEqual(groups[1].recipes.map(\.id), ["a"])
    }
}
