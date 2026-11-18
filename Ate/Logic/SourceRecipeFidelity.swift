import Foundation

/// Narrow source contract for explicitly measured inline captions. This is not a
/// general natural-language/OCR recipe parser. Unsupported structure stays on its
/// existing path; it must not be labelled fidelity-verified by this check.
enum SourceRecipeFidelity {
    struct Contract {
        let text: String
        let ingredients: [Ingredient]
        let method: String
        /// Regional dishes named by the source's own header, just before its ingredient
        /// list. Empty for caption contracts and sources that name no known dish.
        let dishes: [String]

        func issues(_ card: RecipeCard) -> [String] {
            var failures: [String] = []
            if card.ingredients.count != ingredients.count {
                failures.append("Preserve exactly the source ingredient list; do not add or duplicate ingredients.")
            }
            if card.ingredients.map({ Self.name($0.name) }) != ingredients.map({ Self.name($0.name) }) {
                failures.append("Preserve source ingredient order and names.")
            }
            for source in ingredients {
                let candidates = card.ingredients.filter { Self.name($0.name) == Self.name(source.name) }
                guard candidates.count == 1, let actual = candidates.first else {
                    failures.append("Preserve the source ingredient: \(source.name).")
                    continue
                }
                if actual.quantity != source.quantity || Self.unit(actual.unit) != Self.unit(source.unit) {
                    failures.append("Preserve source quantity/unit: \(source.quantity) \(source.unit) \(source.name).")
                }
            }
            // Explicit source waiting/cooking times must survive, in order. This
            // does not infer a missing time or assert semantic step equivalence.
            let expectedTimes = Self.times(method)
            let actualTimes = Self.times(card.steps.map(\.instruction).joined(separator: " "))
            if expectedTimes != actualTimes {
                failures.append("Preserve the source's written cooking times in order; do not shorten or invent them.")
            }
            // The title must stay the source's dish: a regional dish named before the
            // ingredient list must survive in the card title, and no head food noun may
            // appear in the title that the source itself never mentions.
            if !dishes.isEmpty {
                let titled = Set(CuisineGlossary.matches(in: card.title).map(\.name))
                if titled.isDisjoint(with: dishes) {
                    failures.append("Name the dish the source names (\(dishes.joined(separator: " or "))); do not invent a different title.")
                }
            }
            let sourceWords = GeneratedStepQuality.words(text)
            for food in GeneratedStepQuality.words(card.title).intersection(GeneratedStepQuality.foods).subtracting(sourceWords).sorted() {
                failures.append("The title names \(food), which the source never mentions; use the source's dish without inventing facts.")
            }
            return failures
        }

        private static func name(_ raw: String) -> String {
            // Prep may be split into notes, but food aliases/units are not guessed.
            let prep = ["grated", "diced", "chopped", "sliced", "minced", "crushed"]
            return raw.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                .filter { !prep.contains($0) }.map { word in
                    word.hasSuffix("s") && word.count > 3 ? String(word.dropLast()) : word
                }.joined(separator: " ")
        }
        private static func unit(_ raw: String) -> String {
            IngredientParser.units[raw] ?? IngredientParser.units[raw.lowercased()] ?? raw.lowercased()
        }
        private static func times(_ raw: String) -> [Durations.Span] {
            // Preserve BOTH bounds and order. Reducing a span to its upper bound
            // would certify 10-20, 1-20 and 20 minutes as the same source fact.
            Durations.spans(in: raw)
        }
    }

    static func inlineCaption(_ raw: String) -> Contract? {
        let source = CaptionAnalysis.stripInstagramPrefix(raw)
        // Explicit boundaries only: never treat likes/dates/servings/timing as an
        // ingredient list, or silently parse a partial list on failed recognition.
        guard let marker = source.range(of: #"\byou need\s+"#, options: [.regularExpression, .caseInsensitive]),
              let end = source.range(of: #"\.(?:\s+|$)"#, options: .regularExpression,
                                     range: marker.upperBound..<source.endIndex) else { return nil }
        let list = String(source[marker.upperBound..<end.lowerBound])
        let parts = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, parts.allSatisfy({
            $0.range(of: #"^\d+(?:[./]\d+)?\s+[^\d]+$"#, options: .regularExpression) != nil
        }) else { return nil }
        let ingredients = parts.map(IngredientParser.parse)
        guard ingredients.allSatisfy({ $0.quantity > 0 && !$0.name.isEmpty }),
              Set(ingredients.map { $0.name.lowercased() }).count == ingredients.count else { return nil }
        let method = String(source[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !method.isEmpty, CaptionAnalysis.hasRecipeSignals(method) else { return nil }
        return Contract(text: source, ingredients: ingredients, method: method, dishes: [])
    }

    /// Full-recipe text with an explicit measured Ingredients section followed by a
    /// Method/Directions/Instructions section: a recipe web page (htmlToText output is one
    /// collapsed line) or a pasted recipe. This grounds extraction; it is not a general
    /// parser. Any ambiguity - an unmeasured item, an interior sub-heading, a second
    /// concatenated recipe, an empty section - returns nil and the import keeps its
    /// existing path rather than certifying a structure it did not verify.
    static func structuredRecipe(_ raw: String) -> Contract? {
        let text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let ingredientsMarker = text.range(of: #"\bingredients\b\s*:?"#, options: [.regularExpression, .caseInsensitive]),
              let methodMarker = text.range(of: #"\b(?:method|directions|instructions)\b\s*:?"#, options: [.regularExpression, .caseInsensitive],
                                            range: ingredientsMarker.upperBound..<text.endIndex) else { return nil }
        let header = String(text[..<ingredientsMarker.lowerBound])
        let rawSegment = String(text[ingredientsMarker.upperBound..<methodMarker.lowerBound])
        var method = String(text[methodMarker.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let notes = method.range(of: #"\b(?:hints?\s*(?:&|and)\s*tips|tips|variations|notes)\b\s*:?"#,
                                    options: [.regularExpression, .caseInsensitive]) {
            method = String(method[..<notes.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        // A second recipe's measured section makes every boundary ambiguous.
        guard !method.isEmpty, CaptionAnalysis.hasRecipeSignals(method),
              method.range(of: #"\bingredients\b\s*:?\s*\d"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        // Item boundaries are explicit quantities: each measured item starts with a
        // number. Layout bullets before the first quantity are not content.
        let segment = rawSegment.replacingOccurrences(of: #"^[\s•·*\-–—]+"#, with: "", options: .regularExpression)
        guard segment.range(of: #"^\d"#, options: .regularExpression) != nil else { return nil }
        let pieces = segment.replacingOccurrences(of: #"\s+(?=\d+(?:[.,]\d+)?\s)"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard (2...40).contains(pieces.count),
              let leading = try? NSRegularExpression(pattern: #"^(\d+(?:[.,]\d+)?)\s+(\D[\s\S]*)$"#) else { return nil }
        var ingredients: [Ingredient] = []
        for piece in pieces {
            let ns = piece as NSString
            guard let match = leading.firstMatch(in: piece, range: NSRange(location: 0, length: ns.length)),
                  let amount = Double(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return nil }
            let ingredient = IngredientParser.parse(piece)
            // Parse the WHOLE item: the measured quantity must round-trip and leave a
            // name. Prose, an interior heading or an unmeasured amount absorbed into a
            // name ("2 onions salt to taste", "2 onions For the sauce") is not a
            // verified item: refuse rather than certify it.
            let name = ingredient.name.trimmingCharacters(in: .whitespaces)
            guard amount.isFinite, amount > 0, amount == ingredient.quantity, !name.isEmpty,
                  name.range(of: #"[.:;]"#, options: .regularExpression) == nil,
                  name.range(of: #"\b(?:to taste|as needed|as required|optional)\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  name.split(whereSeparator: { $0.isWhitespace }).count <= 3 else { return nil }
            ingredients.append(ingredient)
        }
        guard Set(ingredients.map { $0.name.lowercased() }).count == ingredients.count else { return nil }
        // Only the dish named near the section anchors the title; distant site navigation
        // may name unrelated dishes and never grounds the card title.
        let dishes = CuisineGlossary.matches(in: String(header.suffix(200))).map(\.name)
        return Contract(text: text, ingredients: ingredients, method: method, dishes: dishes)
    }

    /// A recipe structure is recognizable when the text carries an explicit Ingredients
    /// section marker followed by a Method/Directions/Instructions marker with at least
    /// one measured-looking item between them. Recognition alone is never verification:
    /// only a fully parsed contract may bind generation.
    static func claimsStructuredRecipe(_ raw: String) -> Bool {
        let text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let ingredientsMarker = text.range(of: #"\bingredients\b\s*:?"#, options: [.regularExpression, .caseInsensitive]),
              let methodMarker = text.range(of: #"\b(?:method|directions|instructions)\b\s*:?"#, options: [.regularExpression, .caseInsensitive],
                                            range: ingredientsMarker.upperBound..<text.endIndex) else { return false }
        return text[ingredientsMarker.upperBound..<methodMarker.lowerBound]
            .range(of: #"\d+(?:[.,]\d+)?\s"#, options: .regularExpression) != nil
    }

    /// Shared pre-model recognition for every extraction input (link page, pasted recipe,
    /// social caption). Verified structure binds generation; a recognizable structure that
    /// cannot be verified fails closed instead of falling through to creative generation
    /// or a demo substitute.
    enum Extraction {
        case none
        case verified(Contract)
        case unverifiable
    }

    static func extraction(_ raw: String) -> Extraction {
        if let contract = inlineCaption(raw) ?? structuredRecipe(raw) { return .verified(contract) }
        return claimsStructuredRecipe(raw) ? .unverifiable : .none
    }

    static func rejectUngroundedText(_ raw: String) throws {
        if CaptionAnalysis.isUngroundedPromo(raw) {
            throw BackendError(message: "This doesn't look like a recipe or name a dish. Paste a recipe or tell ate the dish you want.")
        }
    }
}
