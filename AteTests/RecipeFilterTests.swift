import XCTest
@testable import Ate

final class IngredientTagTests: XCTestCase {
    func ing(_ names: String...) -> [Ingredient] { names.map { Ingredient(name: $0, quantity: 1, unit: "", notes: nil) } }

    func testExtractsMeatAndCarbs() {
        let r = RecipeCard(title: "Creamy chicken penne", ingredients: ing("chicken thighs", "penne", "cream", "garlic"))
        let t = IngredientTags.tags(for: r)
        XCTAssertTrue(t.isSuperset(of: ["chicken", "pasta"]))
        XCTAssertFalse(t.contains("vegetarian"))
        XCTAssertEqual(IngredientTags.main(for: r), "chicken")
    }
    func testVegetarianAndVegan() {
        let veg = RecipeCard(title: "Mac and cheese", ingredients: ing("macaroni", "cheddar cheese", "milk"))
        XCTAssertTrue(IngredientTags.tags(for: veg).contains("vegetarian"))
        XCTAssertFalse(IngredientTags.tags(for: veg).contains("vegan"))
        let vegan = RecipeCard(title: "Chickpea curry", ingredients: ing("chickpeas", "coconut milk", "onion", "rice"))
        // coconut milk contains "milk" → conservative: not vegan unless tagged
        XCTAssertTrue(IngredientTags.tags(for: vegan).contains("vegetarian"))
        let tofu = RecipeCard(title: "Tofu stir fry", tags: ["vegan"], ingredients: ing("firm tofu", "soy sauce", "noodles"))
        XCTAssertTrue(IngredientTags.tags(for: tofu).isSuperset(of: ["vegan", "vegetarian", "tofu", "pasta"]))
    }
    func testWholeWordsAndEmpty() {
        let r = RecipeCard(title: "Hamburger buns", ingredients: ing("flour", "yeast"))  // "ham" only as part of a word
        XCTAssertFalse(IngredientTags.tags(for: r).contains("pork"))
        XCTAssertTrue(IngredientTags.tags(for: RecipeCard(title: "x")).isEmpty, "no ingredients → no plant-based guess")
    }
    func testSweetPotatoTwoWordKeyword() {
        XCTAssertTrue(IngredientTags.tags(for: RecipeCard(title: "Fries", ingredients: ing("sweet potato"))).contains("potato"))
    }
    func testAvailableAndCollections() {
        let a = RecipeCard(title: "A", ingredients: ing("chicken"))
        let b = RecipeCard(title: "B", ingredients: ing("chicken", "rice"))
        let c = RecipeCard(title: "C", ingredients: ing("salmon"))
        XCTAssertEqual(IngredientTags.available(in: [a, b, c]).first, "chicken")
        XCTAssertEqual(IngredientTags.collections(in: [a, b, c]), ["chicken", "fish"])
        XCTAssertEqual(IngredientTags.collections(in: [a, b, c], min: 2), ["chicken"])
    }
}

final class RecipeFilterTests: XCTestCase {
    let quick = RecipeCard(title: "Quick eggs", servings: 1, timeMinutes: 10,
                           ingredients: [Ingredient(name: "eggs", quantity: 2, unit: "", notes: nil)], sourceURL: "https://x.test")
    let stew = RecipeCard(title: "Beef stew", servings: 6, timeMinutes: 120,
                          ingredients: [Ingredient(name: "beef", quantity: 1, unit: "kg", notes: nil)])
    lazy var pasta: RecipeCard = {
        var r = RecipeCard(title: "Chicken pasta", servings: 4, timeMinutes: 25,
                           ingredients: [Ingredient(name: "chicken", quantity: 1, unit: "", notes: nil), Ingredient(name: "spaghetti", quantity: 1, unit: "", notes: nil)])
        r.origin = .prompt; r.favorite = true; r.lastCookedAt = 2; return r
    }()
    var all: [RecipeCard] { [quick, stew, pasta] }

    func testEmptyFilterMatchesAll() {
        XCTAssertEqual(RecipeFilter().apply(all).count, 3)
        XCTAssertFalse(RecipeFilter().isActive)
    }
    func testTimeBuckets() {
        var f = RecipeFilter(); f.maxMinutes = 15
        XCTAssertEqual(f.apply(all).map(\.title), ["Quick eggs"])
        f.maxMinutes = 30
        XCTAssertEqual(Set(f.apply(all).map(\.title)), ["Quick eggs", "Chicken pasta"])
    }
    func testGroupsAreANDValuesAreOR() {
        var f = RecipeFilter(); f.tags = ["beef", "chicken"]
        XCTAssertEqual(f.apply(all).count, 2)
        f.servings = [.many]
        XCTAssertEqual(f.apply(all).map(\.title), ["Beef stew"])
        XCTAssertEqual(f.activeCount, 3)
        f.clear(); XCTAssertEqual(f, RecipeFilter())
    }
    func testOriginsIncludingLegacyInference() {
        var f = RecipeFilter(); f.origins = [.link]
        XCTAssertEqual(f.apply(all).map(\.title), ["Quick eggs"], "legacy card with sourceURL counts as link")
        f.origins = [.prompt, .link]
        XCTAssertEqual(f.apply(all).count, 2)
    }
    func testCollections() {
        var f = RecipeFilter()
        f.collection = .quick; XCTAssertEqual(Set(f.apply(all).map(\.title)), ["Quick eggs", "Chicken pasta"])
        f.collection = .favourites; XCTAssertEqual(f.apply(all).map(\.title), ["Chicken pasta"])
        f.collection = .recentlyCooked; XCTAssertEqual(f.apply(all).map(\.title), ["Chicken pasta"])
        f.collection = .ingredient("beef"); XCTAssertEqual(f.apply(all).map(\.title), ["Beef stew"])
        var old = stew; old.createdAt = 1; var new = quick; new.createdAt = 99
        f.collection = .recentlyAdded; XCTAssertEqual(f.apply([old, new]).map(\.title), ["Quick eggs", "Beef stew"])
    }
    func testQueryCombinesWithFilter() {
        var f = RecipeFilter(); f.maxMinutes = 30
        XCTAssertEqual(f.apply(all, query: "pasta").map(\.title), ["Chicken pasta"])
    }
    func testPersistence() {
        let d = UserDefaults(suiteName: "filter-\(UUID())")!
        var f = RecipeFilter(); f.tags = ["chicken"]; f.collection = .ingredient("chicken"); f.maxMinutes = 60
        f.save(d)
        XCTAssertEqual(RecipeFilter.load(d), f)
    }
    func testLegacyRecipeDecodesNewFields() throws {
        let r = try JSONDecoder().decode(RecipeCard.self, from: Data(#"{"id":"a","title":"t"}"#.utf8))
        XCTAssertFalse(r.favorite); XCTAssertNil(r.lastCookedAt); XCTAssertNil(r.origin)
    }
}
