import Foundation

/// Deterministic fixtures used by the mock backend in UI tests (KeyFlowsQATests) — exercise the real parsers.
enum QAFixtures {
    static let jsonLDURL = "https://fixtures.ate.test/jsonld-shakshuka"
    static let instagramURL = "https://www.instagram.com/reel/qafixture/?igsh=TRACK"
    static let instagramNoCaptionURL = "https://www.instagram.com/reel/nocaption/"

    static let jsonLDHTML = """
    <html><head><script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"x"},{"@type":"Recipe","name":"Weekend shakshuka",
     "description":"Eggs poached in a spiced tomato sauce.","recipeYield":"4 servings","totalTime":"PT35M",
     "recipeIngredient":["2 tbsp olive oil","1 onion, diced","2 cloves garlic","1 tsp cumin","800 g chopped tomatoes","6 eggs"],
     "recipeInstructions":[{"@type":"HowToStep","text":"Fry the onion for 5 minutes."},{"@type":"HowToStep","text":"Add garlic and cumin."},
       {"@type":"HowToStep","text":"Simmer the tomatoes for 15 minutes."},{"@type":"HowToStep","text":"Crack in the eggs, cover and cook 6 minutes."}],
     "recipeCuisine":"Middle Eastern"}]}
    </script></head><body></body></html>
    """

    static let instagramHTML = """
    <html><head><meta property="og:title" content="Chef Thandi on Instagram: &quot;Creamy chakalaka pasta&quot;" />
    <meta property="og:description" content="12K likes, 340 comments - chef.thandi on March 3, 2026: &quot;Creamy chakalaka pasta 🍝 You need 250g penne, 1 onion, 2 cloves garlic, 1 tin chakalaka, 125ml cream and parmesan. Fry the onion 5 min, add chakalaka, simmer 10 min, stir in cream and pasta.&quot;" />
    </head></html>
    """

    /// Card from a caption without AI (mock path): title from the first phrase, ingredients via the real parser.
    static func cardFromCaption(_ caption: String, sourceURL: String) -> RecipeCard {
        let body = caption.components(separatedBy: "\n").last ?? caption
        let title = body.components(separatedBy: CharacterSet(charactersIn: "🍝.!\n")).first?.trimmingCharacters(in: .whitespaces) ?? "Recipe"
        var ings: [Ingredient] = []
        if let r = body.range(of: "You need ") {
            let list = body[r.upperBound...].components(separatedBy: ".").first ?? ""
            ings = list.replacingOccurrences(of: " and ", with: ", ").components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(IngredientParser.parse)
        }
        return RecipeCard(title: title, description: "From an Instagram caption.", servings: 2, timeMinutes: 20,
                          ingredients: ings, steps: [Step(order: 1, instruction: "Fry the onion 5 min.", timeSeconds: 300),
                                                     Step(order: 2, instruction: "Add chakalaka, simmer 10 min.", timeSeconds: 600),
                                                     Step(order: 3, instruction: "Stir in cream and pasta.", timeSeconds: nil)],
                          sourceURL: sourceURL)
    }
}
