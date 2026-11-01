import Foundation

/// Social caption analysis: strip platform boilerplate and tell recipe text from ads/menus.
enum CaptionAnalysis {
    /// `191 likes, 6 comments - user on September 17, 2025: "caption". ` → `caption`;
    /// `Name on Instagram: "caption"` → `caption`.
    static func stripInstagramPrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [#"^[\d.,]+[KkMm]?\s+likes?,\s*[\d.,]+[KkMm]?\s+comments?\s*-\s*[^:\n]{1,80}?\s+on\s+[^:\n]{3,40}:\s*"#,
                        #"^[^:\n]{1,80}\s+on Instagram:\s*"#]
        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) { s = String(s[r.upperBound...]); break }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".") { s.removeLast() }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'").union(.whitespacesAndNewlines))
    }

    static let promoWords = ["delivery", "deliver", "order", "whatsapp", "dm us", "dm for", "text us", "call us", "book now", "price",
                             "link in bio", "menu", "catering", "available", "special"]
    static let recipeWords = ["ingredients", "method", "cup", "cups", "tbsp", "tsp", "teaspoon", "tablespoon", "grams", "ml",
                              "minutes", "mins", "stir", "simmer", "boil", "fry", "bake", "preheat", "season", "chop"]

    static func isPromo(_ s: String) -> Bool { let l = s.lowercased(); return promoWords.contains { l.contains($0) } }
    static func hasRecipeSignals(_ s: String) -> Bool { let l = s.lowercased(); return recipeWords.filter { l.contains($0) }.count >= 3 }

    /// Remove @handles, hashtags, phone numbers and URLs so the model can't build a recipe from them.
    static func scrub(_ s: String) -> String {
        var t = s
        for p in [#"@[A-Za-z0-9_.]+"#, #"#[A-Za-z0-9_]+"#, #"https?://\S+"#, #"\+?\d[\d -]{7,}\d"#] {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        return t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An ad/menu with no recipe and no recognisable dish name: nothing to ground a recipe on.
    static func isUngroundedPromo(_ caption: String) -> Bool {
        let c = stripInstagramPrefix(caption)
        return isPromo(c) && !hasRecipeSignals(c) && CuisineGlossary.matches(in: c).isEmpty
    }
}

/// Pure prompt construction for Foundation Models (snapshot-tested in RecipePromptTests).
enum RecipePrompt {
    static let instructions = """
    You are a South African home-cooking expert who also knows Southern and West African, and international, home cooking. You turn the user's input into one recipe card.
    Format: first identify the dish (name, cuisine, confidence, alternatives), then write title, servings, time, ingredients (amount, unit, name, prep) and steps (instruction, minutes, temperatureC).
    Rules:
    1. Ground everything in the provided text. Copy dish names and ingredients verbatim when they are given. Do not invent a different dish.
    2. Never use place names, business or account names, hashtags, @handles, phone numbers, prices or delivery/ordering text as the dish, title or ingredients.
    3. If the text is a menu or an advert that names a dish but has no recipe, write a best-effort traditional recipe for that NAMED dish and say so in note.
    4. For text-only inputs, if no dish is named at all, title the card "Unknown dish", set confidence below 0.2 and explain in note. For photo inputs, use only visible evidence and image labels to identify food or a beverage; if the item cannot be established, use "Unknown dish" with confidence below 0.2. Never turn an ambiguous colour, glass or object into a specific ingredient or recipe.
    5. Use realistic home quantities in metric units (g, kg, ml, l, tbsp, tsp, cloves, pcs). Servings must suit the dish (stews and braises usually 4 to 6).
    6. Give minutes for every waiting or cooking step, matching the time written in the step ("simmer 20 minutes" is 20; "2 to 3 h" is 180). timeMinutes is the sum of all steps plus prep: tripe takes 2 to 3 h, steamed bread over 1 h, samp and beans 2 to 3 h.
    7. Respect regional cuisines (South African, Southern African, West African). Use the glossary when provided. Never replace them with an unrelated Western dish.
    8. First identify the dish (dishName, cuisine, confidence, alternatives), then write the recipe for that dish. confidence is 0 to 1: how sure you are about dishName; use below 0.8 when the input does not clearly name or show it.
    9. A main dish needs at least 4 real ingredients with quantities. Oven steps give the temperature in °C. Every step says how (heat, cue), never just "cook the ribs". Times must be realistic: simmer/stew 20+ min, braise 1 h+, pap 15+ min, browning 5+ min. Start each step with a specific verb. Never invent steps or ingredients the source contradicts.
    10. Ingredient–step consistency is mandatory: every named food, wrapper, sauce, fat or binder used in a step must appear as a measured ingredient. Conversely, do not list ingredients that the steps never use. For a photo, account for the dish's structure (for example, a spring roll needs a wrapper and a named filling); do not turn a generic vegetable mixture into a complete recipe.
    Example 1 (South African), input "chakalaka": dish Chakalaka, South African, confidence 0.95. Ingredients: 2 tbsp oil; 1 onion, diced; 2 carrots, grated; 1 green pepper, diced; 2 tsp curry powder; 400 g tinned baked beans. Steps: Sauté the onion in the oil over medium heat until soft, 5 min. Stir in the carrot, pepper and curry powder and fry 3 min. Add the beans and simmer uncovered until thick, 15 min.
    Example 2, input "sticky oven ribs": dish Sticky pork ribs, American, confidence 0.9. Ingredients: 1.2 kg pork ribs; 3 tbsp brown sugar; 2 tsp smoked paprika; 3 cloves garlic, crushed; 125 ml barbecue sauce. Steps: Rub the ribs with sugar, paprika and garlic. Wrap in foil and bake at 160°C until tender, 120 min. Unwrap, brush with sauce and roast at 220°C until sticky, 15 min.
    """

    enum Input: String { case link, social, photo, screenshot, prompt, rewrite }

    /// Per-input instructions ("profiles"): the shared rules plus a short mode-specific brief.
    /// (FoundationModels in Xcode 26.6 has no Dynamic Profiles API; a fresh session per input does the same job.)
    static func instructions(for input: Input) -> String {
        let brief: String
        switch input {
        case .link: brief = "Input: text scraped from a recipe web page. Ignore navigation, ads and comments."
        case .social: brief = "Input: a social media caption. It may be an advert or menu; follow rule 3 and 4 strictly."
        case .photo: brief = "Input: a photo of food or a beverage, optionally named by the user. If you need printed text in the photo (menu boards, labels), call readPhotoText. Never invent a different dish or drink than the user named. Distinguish plated food from a drink/cocktail only when image labels and scene clues support it. A glass, plate, utensil, wooden object, cookware or tableware alone is not enough to identify a recipe. If the edible item cannot be established, return Unknown dish with confidence below 0.2 instead of inventing a recipe."
        case .screenshot: brief = "Input: OCR text of a recipe screenshot. Keep the original quantities and order."
        case .prompt: brief = "Input: the user's own description. A sensible traditional recipe is fine; still follow the units and timing rules."
        case .rewrite: brief = "Input: an existing recipe card as JSON plus the user's change request. Change only what is asked."
        }
        return instructions + "\n" + brief
    }

    static func social(caption raw: String) -> String {
        let caption = CaptionAnalysis.scrub(CaptionAnalysis.stripInstagramPrefix(raw))
        var p = "Social media caption (the only source of truth):\n\"\"\"\n\(caption.prefix(3000))\n\"\"\"\n"
        if CaptionAnalysis.isPromo(caption) && !CaptionAnalysis.hasRecipeSignals(caption) {
            p += "This caption looks like an advert or menu, not a recipe. Only use dish names that appear in it.\n"
        }
        return p + glossary(for: caption)
    }

    static func page(_ text: String) -> String {
        "Web page text:\n\"\"\"\n\(text.prefix(3500))\n\"\"\"\nExtract the recipe from it.\n" + glossary(for: text)
    }

    static func screenshot(_ text: String) -> String {
        "Screenshot text (OCR):\n\"\"\"\n\(text.prefix(3500))\n\"\"\"\nExtract the recipe from it.\n" + glossary(for: text)
    }

    static func prompt(_ text: String) -> String {
        "Recipe card for: \(text.prefix(500))\n" + glossary(for: text)
    }

    /// Food photo where the user (or a confident label) named the dish.
    /// `ocr` is inlined only on the fallback path; with the readPhotoText tool the model fetches it on demand.
    static func photo(dish: String, labels: [String], ocr: String, ocrViaTool: Bool = false) -> String {
        var p = "A photo shows this dish: \(dish). Write a traditional home-cook recipe for exactly that dish. List every visible structural component and make every component used in the steps a measured ingredient; never write a step using an unlisted wrapper, pastry, sauce, binder or filling."
        if !labels.isEmpty { p += " Image labels (generic hints only): \(labels.prefix(5).joined(separator: ", "))." }
        let o = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        if ocrViaTool { if !o.isEmpty { p += " The photo contains some printed text; call readPhotoText if it helps." } }
        else if !o.isEmpty { p += " Text visible in the photo: \(o.prefix(200))." }
        return p + "\n" + glossary(for: dish + " " + o)
    }

    /// Food photo with no confident name: the model identifies the dish in the same pass (dishName first).
    static func photoUnnamed(labels: [String], candidates: [String], ocr: String, ocrViaTool: Bool = false) -> String {
        var p = "A photo of food or a beverage. First identify whether the image evidence supports a prepared food dish or a drink/cocktail, then create an editable recipe only when there is a reasonable basis. Use supplied image labels, visible text and scene clues as evidence, not certainty. For cocktails and drinks, never infer a specific spirit by name (including brandy, gin, vodka, rum or tequila), liqueur, mixer, garnish or exact quantity from colour, bubbles, ice, fruit colour or glassware alone. Do not turn a generic label such as cocktail, drink, liquid or glass into a specific drink recipe. If the drink identity or ingredients are not visibly supported, return title Unknown dish, confidence below 0.2, empty or minimal recipe fields, and ask the user to identify the drink instead of inventing ingredients. For any other uncertain ingredient or quantity, omit unsupported specifics or explicitly mark estimates in the note. If the edible item or beverage cannot be established, return title Unknown dish, confidence below 0.2, empty or minimal recipe fields, and explain that the user must identify it; never invent a recipe around an object."
        if !labels.isEmpty { p += " Image labels: \(labels.prefix(6).joined(separator: ", "))." }
        if !candidates.isEmpty { p += " Likely regional candidates: \(candidates.prefix(8).joined(separator: ", "))." }
        let o = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        if ocrViaTool { if !o.isEmpty { p += " The photo contains printed text; call readPhotoText if it helps." } }
        else if !o.isEmpty { p += " Text visible in the photo: \(o.prefix(200))." }
        return p + "\n" + glossary(for: (labels + candidates).joined(separator: " ") + " " + o)
    }

    /// Short pointer only; the full entries come from the lookupRegionalDish tool on demand (saves context).
    static func glossary(for text: String) -> String {
        let m = CuisineGlossary.matches(in: text)
        return m.isEmpty ? "" : "Regional dishes mentioned: " + m.map(\.name).joined(separator: "; ") + ". Call lookupRegionalDish for each before writing ingredients.\n"
    }

    /// Tool body for lookupRegionalDish: glossary entries (traditional ingredients, method, time) for a dish name.
    static func lookupRegionalDish(_ name: String) -> String {
        var m = CuisineGlossary.matches(in: name)
        if m.isEmpty { m = CuisineGlossary.dishes.filter { $0.name.lowercased().contains(name.lowercased().trimmingCharacters(in: .whitespaces)) } }
        return m.isEmpty ? "No glossary entry for \(name). Use a traditional home-cook version." : CuisineGlossary.promptLines(m)
    }

    /// Conditional prompt lines (code-along 205 Prompt { } builder): dietary preference, servings and region.
    struct Context: Equatable { var dietary: [String] = []; var servings: Int? = nil; var region: String? = nil }
    static let dietaryWords = ["vegan", "vegetarian", "halal", "kosher", "gluten-free", "dairy-free", "pescatarian", "low-carb"]
    static func context(for text: String, region: String? = Locale.current.region?.identifier) -> Context {
        let l = text.lowercased()
        var c = Context()
        c.dietary = dietaryWords.filter { w in
            guard let r = l.range(of: w) else { return false }
            let before = l[..<r.lowerBound].suffix(8)
            return !["not ", "no ", "non-", "non ", "isn't ", "without"].contains { before.hasSuffix($0) }
        }
        if let r = l.range(of: #"(?:for|serves)\s+(\d{1,2})(?!\s*(?:minutes?|mins?|hours?|hrs?|h|seconds?|secs?)\b)"#, options: .regularExpression),
           let n = Int(l[r].filter(\.isNumber)), n > 0 { c.servings = n }
        c.region = region == "ZA" ? "South Africa" : nil
        return c
    }
    static func contextLines(_ c: Context) -> [String] {
        var out: [String] = []
        if !c.dietary.isEmpty { out.append("Dietary preference: \(c.dietary.joined(separator: ", ")). Every ingredient must fit it.") }
        if let n = c.servings { out.append("Write it for \(n) servings.") }
        if let r = c.region { out.append("The cook is in \(r): use locally available ingredients and names.") }
        return out
    }
    /// A/B switch for code-along 205 step 3: with the one-shot GenRecipe example in the prompt, the schema can be left out.
    static var includeSchemaInPrompt: Bool { ProcessInfo.processInfo.arguments.contains("-qaIncludeSchema") || UserDefaults.standard.bool(forKey: "ate.ai.includeSchema") }
    static let exampleLead = "Here is an example of the desired format, but don't copy its content:"
}

/// What the photo path should do before generating.
enum PhotoAssessment: Equatable {
    case confident(String)                      // specific dish label
    case uncertain(suggestions: [String])       // generic labels: ask "What dish is this?"
    case spread(suggestions: [String])          // several bowls/dishes: pick one or "spread"
}

extension PhotoGuess {
    /// Vision often labels the serving context or an object more confidently than the food itself.
    /// These labels must never become recipe titles or confidence anchors.
    static let nonDishObjects: Set<String> = [
        "utensil", "wooden utensil", "wood utensil", "kitchen utensil", "serving utensil", "wooden spoon",
        "spoon", "fork", "knife", "chopsticks", "plate", "serving plate", "dish", "serving dish",
        "bowl", "pot", "pan", "saucepan", "cooking pot", "cookware", "tableware", "dishware",
        "cutlery", "container", "tray", "platter", "table", "wood", "wood processed"
    ]
    static func isNonDishObject(_ raw: String) -> Bool {
        let n = raw.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return nonDishObjects.contains(n) || n.contains("utensil") || n.contains("tableware") || n.contains("dishware")
    }

    static let weak: Set<String> = ["potato", "potatoes", "french fries", "chicken", "meat", "vegetable", "stew", "soup", "bread",
                                    "rice", "salad", "baked goods", "fried food", "sauce", "curry", "produce"]
    static let spreadHints: Set<String> = ["bowl", "buffet", "platter", "tableware", "dishware", "table"]

    /// Distinct specific foods (generic scene words removed, plurals folded so two plates of toast = one "toast").
    static func distinctFoods(_ labels: [(String, Float)], minConfidence: Float = 0.3) -> [(String, Float)] {
        var seen = Set<String>(), out: [(String, Float)] = []
        for (id, c) in labels.sorted(by: { $0.1 > $1.1 }) where c >= minConfidence {
            let n = id.lowercased().replacingOccurrences(of: "_", with: " ")
            if generic.contains(id.lowercased()) || generic.contains(n) || spreadHints.contains(n) || isNonDishObject(n) { continue }
            let key = n.hasSuffix("es") ? String(n.dropLast(2)) : (n.hasSuffix("s") ? String(n.dropLast()) : n)
            if seen.insert(key).inserted { out.append((n, c)) }
        }
        return out
    }

    static func titled(_ s: String) -> String { RecipeQuality.titleCased(s.lowercased()) }

    /// Chips: Vision's own food labels first; the SA glossary only when the labels are ambiguous.
    static func suggestions(labels: [(String, Float)], ocrText: String) -> [String] {
        let named = CuisineGlossary.matches(in: ocrText).map(\.name)
        let foods = distinctFoods(labels, minConfidence: 0.1).map(\.0)
        var out = named + foods.prefix(5).map(titled)
        if foods.count >= 2 { out.insert(titled("\(foods[0]) with \(foods[1])"), at: named.count) }
        let ambiguous = distinctFoods(labels).filter { !weak.contains($0.0) }.isEmpty
        if ambiguous { out += CuisineGlossary.photoSuggestions }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.lowercased()).inserted }.prefix(8))
    }

    static func assess(labels: [(String, Float)], ocrText: String) -> PhotoAssessment {
        let named = CuisineGlossary.matches(in: ocrText).map(\.name)
        let suggestions = Self.suggestions(labels: labels, ocrText: ocrText)
        // A spread means 3+ DIFFERENT specific foods, not several plates/bowls of the same thing.
        let specific = distinctFoods(labels).filter { !weak.contains($0.0) && !isNonDishObject($0.0) }
        if specific.filter({ $0.1 >= 0.45 }).count >= 3 { return .spread(suggestions: suggestions) }
        if let n = named.first { return .confident(n) }
        if let top = specific.first, top.1 >= 0.5 {
            if specific.count >= 2, specific[1].1 >= 0.35 { return .confident("\(top.0) with \(specific[1].0)") }
            return .confident(top.0)
        }
        return .uncertain(suggestions: suggestions)
    }

    /// Confidence calibrated from Vision: when the card is the dish Vision clearly saw, trust Vision's score.
    static func calibratedConfidence(model: Double?, title: String, labels: [(String, Float)]) -> Double? {
        guard let top = distinctFoods(labels).first(where: { !weak.contains($0.0) && !isNonDishObject($0.0) }) else { return model }
        let tw = CoverLogic.words(title)
        let hit = CoverLogic.words(top.0).allSatisfy { w in tw.contains(w) || tw.contains(w + "s") }
        guard hit else { return model }
        return max(model ?? 0, min(0.95, 0.45 + Double(top.1)))
    }

    /// Visual description for the prompt: top labels with %, distinct item count, colours.
    static func sceneDescription(labels: [(String, Float)], salientObjects: Int, colours: [String]) -> String {
        let top = labels.sorted { $0.1 > $1.1 }.prefix(10).map { "\($0.0.replacingOccurrences(of: "_", with: " ")) \(Int(($0.1 * 100).rounded()))%" }
        var p = "Vision labels: \(top.joined(separator: ", "))."
        let foods = distinctFoods(labels)
        if !foods.isEmpty { p += " Distinct foods: \(foods.map(\.0).joined(separator: ", "))." }
        if salientObjects > 0 { p += " About \(salientObjects) separate item\(salientObjects == 1 ? "" : "s") in frame (plates of the same food are one dish)." }
        if !colours.isEmpty { p += " Main colours: \(colours.joined(separator: ", "))." }
        return p
    }
}

/// Thrown by the photo path so the Add sheet can ask "What dish is this?" before generating.
struct PhotoNeedsDishError: LocalizedError, Equatable {
    let suggestions: [String]
    let spread: Bool
    var errorDescription: String? {
        spread ? "This looks like a spread of several dishes. Pick one, or make a card for each."
               : "Not sure what this dish is. Tell ate what it is for a better recipe."
    }
}

