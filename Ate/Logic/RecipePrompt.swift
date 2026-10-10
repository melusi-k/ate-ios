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
    You turn the user's text into one recipe card. Rules:
    1. Ground everything in the provided text. Copy dish names and ingredients verbatim when they are given. Do not invent a different dish.
    2. Never use place names, business or account names, hashtags, @handles, phone numbers, prices or delivery/ordering text as the dish, title or ingredients.
    3. If the text is a menu or an advert that names a dish but has no recipe, write a best-effort traditional recipe for that NAMED dish and say so in note.
    4. If no dish is named at all, title the card "Unknown dish", set confidence below 0.2 and explain in note.
    5. Use realistic home quantities in metric units (g, kg, ml, l, tbsp, tsp, cloves, pcs). Servings must suit the dish (stews and braises usually 4 to 6).
    6. Give timeSeconds for every waiting or cooking step. timeMinutes is the sum of all steps plus prep: tripe takes 2 to 3 h, steamed bread over 1 h, samp and beans 2 to 3 h.
    7. Respect regional cuisines (South African, Southern African, West African). Use the glossary when provided. Never replace them with an unrelated Western dish.
    8. confidence is 0 to 1: how sure you are that this card is the dish in the text.
    """

    enum Input: String { case link, social, photo, screenshot, prompt, rewrite }

    /// Per-input instructions ("profiles"): the shared rules plus a short mode-specific brief.
    /// (FoundationModels in Xcode 26.6 has no Dynamic Profiles API; a fresh session per input does the same job.)
    static func instructions(for input: Input) -> String {
        let brief: String
        switch input {
        case .link: brief = "Input: text scraped from a recipe web page. Ignore navigation, ads and comments."
        case .social: brief = "Input: a social media caption. It may be an advert or menu; follow rule 3 and 4 strictly."
        case .photo: brief = "Input: a food photo the user named. If you need any text printed in the photo (menu boards, labels), call the readPhotoText tool. Never invent a different dish than the one named."
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
        var p = "A photo shows this dish: \(dish). Write a traditional home-cook recipe for exactly that dish."
        if !labels.isEmpty { p += " Image labels (generic hints only): \(labels.prefix(5).joined(separator: ", "))." }
        let o = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        if ocrViaTool { if !o.isEmpty { p += " The photo contains some printed text; call readPhotoText if it helps." } }
        else if !o.isEmpty { p += " Text visible in the photo: \(o.prefix(200))." }
        return p + "\n" + glossary(for: dish + " " + o)
    }

    static func glossary(for text: String) -> String {
        let m = CuisineGlossary.matches(in: text)
        return m.isEmpty ? "" : "Glossary:\n" + CuisineGlossary.promptLines(m) + "\n"
    }
}

/// What the photo path should do before generating.
enum PhotoAssessment: Equatable {
    case confident(String)                      // specific dish label
    case uncertain(suggestions: [String])       // generic labels: ask "What dish is this?"
    case spread(suggestions: [String])          // several bowls/dishes: pick one or "spread"
}

extension PhotoGuess {
    static let weak: Set<String> = ["potato", "potatoes", "french fries", "chicken", "meat", "vegetable", "stew", "soup", "bread",
                                    "rice", "salad", "baked goods", "fried food", "sauce", "curry", "produce"]
    static let spreadHints: Set<String> = ["bowl", "buffet", "platter", "tableware", "dishware", "table"]

    static func assess(labels: [(String, Float)], ocrText: String) -> PhotoAssessment {
        let named = CuisineGlossary.matches(in: ocrText).map(\.name)
        let d = dishes(from: labels).filter { !weak.contains($0) }
        let lower = labels.map { $0.0.lowercased() }
        let bowls = lower.filter { spreadHints.contains($0) }.count
        let specificFoods = dishes(from: labels).count
        let suggestions = Array((named + CuisineGlossary.photoSuggestions).prefix(8))
        if bowls >= 2 || specificFoods >= 4 { return .spread(suggestions: suggestions) }
        if let n = named.first { return .confident(n) }
        if let top = labels.sorted(by: { $0.1 > $1.1 }).first(where: { d.contains($0.0.lowercased().replacingOccurrences(of: "_", with: " ")) }), top.1 >= 0.6 {
            return .confident(top.0.replacingOccurrences(of: "_", with: " "))
        }
        return .uncertain(suggestions: suggestions)
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
