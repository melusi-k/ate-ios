import XCTest
@testable import Ate

final class JSONLDTests: XCTestCase {
    let html = """
    <html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"x"},
    {"@type":["Recipe"],"name":"Best Banana Bread &amp; Walnuts","description":"Moist and easy.","recipeYield":["8","8 slices"],
     "totalTime":"PT1H15M","image":[{"@type":"ImageObject","url":"https://ex.com/b.jpg"}],"recipeCuisine":"American","keywords":"bread, baking",
     "recipeIngredient":["3 ripe bananas, mashed","1 1/2 cups all-purpose flour","½ tsp salt","113 g (1 stick) butter, melted","Pinch of cinnamon"],
     "recipeInstructions":[{"@type":"HowToSection","name":"Prep","itemListElement":[{"@type":"HowToStep","text":"Heat oven to 175°C."}]},
       {"@type":"HowToStep","text":"Mix everything."},{"@type":"HowToStep","text":"Bake for 60 minutes."}]}]}</script></head></html>
    """

    func testExtractsGraphRecipe() throws {
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: html, sourceURL: "https://ex.com/r"))
        XCTAssertEqual(c.title, "Best Banana Bread & Walnuts")
        XCTAssertEqual(c.servings, 8)
        XCTAssertEqual(c.timeMinutes, 75)
        XCTAssertEqual(c.imageURL, "https://ex.com/b.jpg")
        XCTAssertEqual(c.sourceURL, "https://ex.com/r")
        XCTAssertEqual(c.ingredients.count, 5)
        XCTAssertEqual(c.steps.map(\.instruction), ["Heat oven to 175°C.", "Mix everything.", "Bake for 60 minutes."])
        XCTAssertEqual(c.steps.last?.timeSeconds, 3600)
        XCTAssertTrue(c.tags.contains("american"))
    }

    func testIngredientParser() {
        let a = IngredientParser.parse("1 1/2 cups all-purpose flour")
        XCTAssertEqual(a.quantity, 1.5); XCTAssertEqual(a.unit, "cup"); XCTAssertEqual(a.name, "all-purpose flour")
        let b = IngredientParser.parse("3 ripe bananas, mashed")
        XCTAssertEqual(b.quantity, 3); XCTAssertEqual(b.unit, "pcs"); XCTAssertEqual(b.name, "ripe bananas"); XCTAssertEqual(b.notes, "mashed")
        let c = IngredientParser.parse("½ tsp salt")
        XCTAssertEqual(c.quantity, 0.5); XCTAssertEqual(c.unit, "tsp"); XCTAssertEqual(c.name, "salt")
        let d = IngredientParser.parse("113 g (1 stick) butter, melted")
        XCTAssertEqual(d.quantity, 113); XCTAssertEqual(d.unit, "g"); XCTAssertEqual(d.name, "butter")
        XCTAssertEqual(d.notes, "melted; 1 stick")
        let e = IngredientParser.parse("Pinch of cinnamon")
        XCTAssertEqual(e.unit, "pinch"); XCTAssertEqual(e.quantity, 1); XCTAssertEqual(e.name, "cinnamon")
        let f = IngredientParser.parse("2 cloves garlic")
        XCTAssertEqual(f.unit, "cloves"); XCTAssertEqual(f.name, "garlic")
        let g = IngredientParser.parse("salt and pepper")
        XCTAssertEqual(g.quantity, 0); XCTAssertEqual(g.unit, ""); XCTAssertEqual(g.name, "salt and pepper")
    }

    func testDurationsAndTimers() {
        XCTAssertEqual(JSONLD.duration("PT1H30M"), 90)
        XCTAssertEqual(JSONLD.duration("P0DT45M"), 45)
        XCTAssertNil(JSONLD.duration("PT0M"))
        XCTAssertEqual(StepTimer.seconds(in: "Simmer for 1 hour 10 mins"), 4200)
        XCTAssertEqual(StepTimer.seconds(in: "Rest 30 seconds"), 30)
        XCTAssertEqual(StepTimer.seconds(in: "Bake 10-12 minutes"), 720)
        XCTAssertNil(StepTimer.seconds(in: "Serve with 4 slices of toast"))
    }

    func testNoRecipeReturnsNil() {
        XCTAssertNil(JSONLD.recipe(fromHTML: #"<script type="application/ld+json">{"@type":"Article","name":"x"}</script>"#))
        XCTAssertNil(JSONLD.recipe(fromHTML: "<html>no data</html>"))
    }

    func testInstructionsAsSingleString() throws {
        let h = #"<script type='application/ld+json'>{"@type":"Recipe","name":"Tea","recipeIngredient":["1 tea bag"],"recipeInstructions":"Boil water.\nSteep 3 minutes."}</script>"#
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: h))
        XCTAssertEqual(c.steps.count, 2)
        XCTAssertEqual(c.steps[1].timeSeconds, 180)
    }
}

final class AisleTests: XCTestCase {
    func testGroupedInStoreOrder() {
        let items = [ShoppingItem(name: "rice", quantity: 1, unit: "kg"), ShoppingItem(name: "garlic", quantity: 2, unit: "cloves"),
                     ShoppingItem(name: "salmon", quantity: 2, unit: "pcs"), ShoppingItem(name: "mystery", quantity: 1, unit: ""),
                     ShoppingItem(name: "onion", quantity: 1, unit: "pcs", aisle: .frozen)]
        let g = ShoppingLogic.grouped(items)
        XCTAssertEqual(g.map(\.aisle), [.produce, .meatFish, .pantry, .frozen, .other])
        XCTAssertEqual(g.first?.items.map(\.name), ["garlic"])
        XCTAssertEqual(g.first(where: { $0.aisle == .frozen })?.items.map(\.name), ["onion"], "explicit aisle wins over guess")
    }
}

final class ImportedCopyTests: XCTestCase {
    let lancewoodHTML = #"""
    <html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Recipe",
    "name":"Delicious Creamy Samp Recipe | LANCEWOOD\u00AE",
    "description":"Explore our delicious Creamy Samp recipe featuring LANCEWOOD\u00AE dairy products. Try the recipe now!",
    "recipeYield":"6","totalTime":"PT45M",
    "recipeIngredient":["800 g quick cooking samp","5 ml Aromat\u00AE","230 g LANCEWOOD\u00AE Medium Fat Plain Cream Cheese"],
    "recipeInstructions":[{"@type":"HowToStep","text":"Bring the samp and water to the boil."}]}</script></head></html>
    """#

    func testSiteSuffixIsStrippedFromImportedTitle() throws {
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: lancewoodHTML, sourceURL: "https://lancewood.co.za/recipes/creamy-samp/"))
        XCTAssertEqual(c.title, "Delicious Creamy Samp Recipe")
    }

    func testMarketingBlurbBecomesNoDescription() throws {
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: lancewoodHTML, sourceURL: "https://lancewood.co.za/recipes/creamy-samp/"))
        XCTAssertNil(c.description, "a call to action is not dish context; no description is better")
    }

    func testIngredientTextKeepsBrandMarks() throws {
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: lancewoodHTML, sourceURL: "https://lancewood.co.za/recipes/creamy-samp/"))
        XCTAssertTrue(c.ingredients.contains { $0.name.contains("Aromat\u{00AE}") || $0.name.contains("LANCEWOOD\u{00AE}") },
                      "title cleaning never touches ingredient text")
    }

    func testCleanTitleSeparators() {
        XCTAssertEqual(JSONLD.cleanTitle("Best Banana Bread"), "Best Banana Bread")
        // EVERY separator form strips only when the suffix names the site.
        XCTAssertEqual(JSONLD.cleanTitle("Samp Recipe | FoodSite", host: "foodsite.com"), "Samp Recipe")
        XCTAssertEqual(JSONLD.cleanTitle("Samp Recipe :: FoodSite", host: "foodsite.com"), "Samp Recipe")
        XCTAssertEqual(JSONLD.cleanTitle("Samp Recipe \u{2013} FoodSite", host: "foodsite.com"), "Samp Recipe")
        XCTAssertEqual(JSONLD.cleanTitle("Samp Recipe \u{2014} FoodSite", host: "foodsite.com"), "Samp Recipe")
        // An unknown or missing host keeps the whole title verbatim.
        XCTAssertEqual(JSONLD.cleanTitle("Samp Recipe | FoodSite", host: "other.com"), "Samp Recipe | FoodSite")
        XCTAssertEqual(JSONLD.cleanTitle("Samp Recipe | FoodSite"), "Samp Recipe | FoodSite")
        // A legitimate dash title is a dish, not a suffix.
        XCTAssertEqual(JSONLD.cleanTitle("Chicken \u{2013} Lemon and Herb", host: "ex.com"), "Chicken \u{2013} Lemon and Herb")
        // Leading title is never emptied by a separator, and its space survives.
        XCTAssertEqual(JSONLD.cleanTitle(" | FoodSite", host: "foodsite.com"), " | FoodSite")
    }

    func testHyphenSuffixOnlyWhenItNamesTheSite() {
        XCTAssertEqual(JSONLD.cleanTitle("Creamy Samp - Lancewood", host: "lancewood.co.za"), "Creamy Samp")
        XCTAssertEqual(JSONLD.cleanTitle("Creamy Samp - Dinner Ideas", host: "lancewood.co.za"), "Creamy Samp - Dinner Ideas")
        XCTAssertEqual(JSONLD.cleanTitle("Creamy Samp - Lancewood", host: nil), "Creamy Samp - Lancewood")
        XCTAssertEqual(JSONLD.cleanTitle("Mother-in-law Chicken", host: "ex.com"), "Mother-in-law Chicken")
        // A leading www never matches; the registrable name does (both sides).
        XCTAssertEqual(JSONLD.cleanTitle("Creamy Samp - Lancewood", host: "www.lancewood.co.za"), "Creamy Samp")
        XCTAssertEqual(JSONLD.cleanTitle("Creamy Samp - Www", host: "www.lancewood.co.za"), "Creamy Samp - Www")
        XCTAssertEqual(JSONLD.registrableName("www.lancewood.co.za"), "lancewood")
        XCTAssertEqual(JSONLD.registrableName("lancewood.co.za"), "lancewood")
        XCTAssertEqual(JSONLD.registrableName("www.example.com"), "example")
    }

    func testSiteNameMatchesOnlyOnAWholeNameBoundary() {
        // r3 collision fixture: substring membership is never enough. Host
        // eat.com must not strip "Wheat and Cheese" (wheat only CONTAINS eat);
        // exact-name and whole-token suffixes still strip.
        XCTAssertEqual(JSONLD.cleanTitle("Chicken - Wheat and Cheese", host: "eat.com"), "Chicken - Wheat and Cheese")
        XCTAssertEqual(JSONLD.cleanTitle("Chicken - Wheaten Delight", host: "eat.com"), "Chicken - Wheaten Delight")
        XCTAssertEqual(JSONLD.cleanTitle("Chicken - Eat", host: "eat.com"), "Chicken")
        XCTAssertEqual(JSONLD.cleanTitle("Chicken - eat.com", host: "eat.com"), "Chicken")
        XCTAssertEqual(JSONLD.cleanTitle("Chicken | Eat Out", host: "eat.com"), "Chicken")
        XCTAssertEqual(JSONLD.suffixNamesSite("Wheat and Cheese", site: "eat"), false)
        XCTAssertEqual(JSONLD.suffixNamesSite("eat.com", site: "eat"), true)
    }

    func testGenuineDescriptionsSurvive() throws {
        let genuineHTML = #"""
        <html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Recipe",
        "name":"Banana Bread","description":"Moist and easy.","recipeIngredient":["2 bananas","200 g flour"],
        "recipeInstructions":[{"@type":"HowToStep","text":"Bake 40 minutes."}]}</script></head></html>
        """#
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: genuineHTML, sourceURL: "https://ex.com/r"))
        XCTAssertEqual(c.description, "Moist and easy.")
    }
}
