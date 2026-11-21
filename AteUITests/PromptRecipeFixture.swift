// Explicit test source for Add import setup. Titles are navigation labels retained
// from callers, not evidence that the mock generated those dishes from a name.
// This file is compiled into UI and unit test targets only, never the app.
enum PromptRecipeFixture {
    static let salmonContinuation = """

    Ingredients
    2 salmon fillets
    2 tbsp white miso
    1 tbsp honey
    2 cloves garlic
    150 g rice
    Method
    1. Heat the oven to 200°C and line a tray.
    2. Mix miso, honey and garlic; brush over the salmon.
    3. Roast the salmon for 10 minutes.
    4. Rest for 1 minute, then serve over rice.
    """

    static func salmon(named title: String) -> String {
        title + salmonContinuation
    }

    // Repair wiring starts from an intentionally incomplete mock card. The input
    // source includes bread; its absence from the returned card must still fail.
    static let breadSalad = """
    Tomato bread salad
    Ingredients
    1 onion
    2 tomatoes
    1 tbsp oil
    2 slices bread
    Method
    1. Chop the onion and tomatoes.
    2. Cut the bread into cubes.
    3. Toss the onion, tomatoes and bread with oil.
    """
}
