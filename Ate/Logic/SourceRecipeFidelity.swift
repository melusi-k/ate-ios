import Foundation

/// Narrow source contract for explicitly measured inline captions. This is not a
/// general natural-language/OCR recipe parser. Unsupported structure stays on its
/// existing path; it must not be labelled fidelity-verified by this check.
enum SourceRecipeFidelity {
    /// Comma and parenthesis tails on an ingredient item are supported ONLY as
    /// explicit preparation syntax: this closed whitelist of prep words/phrases,
    /// joined by spaces, commas or "and". Any other tail content - an unmeasured
    /// item ("salt"), an interior heading ("For the sauce"), hedging prose -
    /// makes the recipe unverifiable and is refused honestly; a blacklist of
    /// known-bad tails would keep losing to the next unlisted phrasing.
    private static let prepTerms = ["cut into strips", "chopped", "crushed", "sliced",
                                    "diced", "cleaned", "minced", "peeled", "grated"]

    static func isPrepOnly(_ tail: String) -> Bool {
        var rest = tail.lowercased().trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return false }
        while !rest.isEmpty {
            guard let term = prepTerms.first(where: {
                rest == $0 || rest.hasPrefix($0 + " ") || rest.hasPrefix($0 + ",")
            }) else { return false }
            rest = String(rest.dropFirst(term.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            if rest.hasPrefix("and"), rest.count == 3 || rest[rest.index(rest.startIndex, offsetBy: 3)] == " " {
                rest = String(rest.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            }
        }
        return true
    }

    /// The tails a parser moves into notes: every parenthetical group plus the
    /// comma tail of the item text after its quantity.
    static func tails(in remainder: String) -> [String] {
        var region = remainder
        var tails: [String] = []
        while let r = region.range(of: #"\(([^)]*)\)"#, options: .regularExpression) {
            tails.append(String(region[r].dropFirst().dropLast()))
            region.removeSubrange(r)
        }
        if let comma = region.firstIndex(of: ",") {
            tails.append(String(region[region.index(after: comma)...]))
        }
        return tails
    }

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
        // The comma split keeps each item explicit; parentheses are the only tail a
        // caption part can carry. They are supported ONLY as preparation syntax from
        // the closed whitelist - "2 onions (salt)" is unverifiable, never certified
        // with salt dropped into notes.
        guard parts.allSatisfy({ part in
            guard let quantity = part.range(of: #"^\d+(?:[./]\d+)?\s+"#, options: .regularExpression) else { return false }
            return tails(in: String(part[quantity.upperBound...])).allSatisfy(isPrepOnly)
        }) else { return nil }
        let ingredients = parts.map(IngredientParser.parse)
        guard ingredients.allSatisfy({
            let name = $0.name.trimmingCharacters(in: .whitespaces)
            return $0.quantity > 0 && !name.isEmpty
                && name.range(of: #"\b(?:to taste|as needed|as required|optional)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
                && name.split(whereSeparator: { $0.isWhitespace }).count <= 3
        }), Set(ingredients.map { $0.name.lowercased() }).count == ingredients.count else { return nil }
        let method = String(source[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !method.isEmpty, CaptionAnalysis.hasRecipeSignals(method) else { return nil }
        return Contract(text: source, ingredients: ingredients, method: method, dishes: [])
    }

    /// Full-recipe text with an explicit measured Ingredients section followed by a
    /// Method/Directions/Instructions section: a recipe web page whose htmlToText output
    /// preserved its list/line-break boundaries, or a pasted recipe with real line
    /// breaks. This grounds extraction; it is not a general parser. Item boundaries must
    /// be explicit: ONE measured item per line, and every line must be a measured item -
    /// an unmeasured line ("salt", "onions and salt") is unverifiable, and so is any
    /// line carrying several measured items, because nothing marks where one name ends
    /// and the next item starts ("500 ml water salt"). A collapsed page or caption with
    /// no explicit boundaries is refused honestly rather than partially certified. Any
    /// other ambiguity - an interior sub-heading, a second concatenated recipe, an empty
    /// section - returns nil and the import keeps its existing path.
    static func structuredRecipe(_ raw: String) -> Contract? {
        // Collapse spaces/tabs only: newlines are item boundaries and survive.
        let text = raw.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        // One item per line, and every line must be a measured item. Layout bullets
        // before a quantity are not content. A line that splits at a second measured
        // quantity start has no defensible inner boundary: refuse the whole recipe
        // rather than guess where one item's name ends.
        let lines = rawSegment.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var pieces: [String] = []
        for line in lines {
            let stripped = line.replacingOccurrences(of: #"^[•·*\-–— ]+"#, with: "", options: .regularExpression)
            let split = stripped.replacingOccurrences(of: #"\s+(?=\d+(?:[.,]\d+)?\s)"#, with: "\n", options: .regularExpression)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard split.count == 1 else { return nil }
            pieces.append(split[0])
        }
        guard (2...40).contains(pieces.count),
              let leading = try? NSRegularExpression(pattern: #"^(\d+(?:[.,]\d+)?)\s+(\D[\s\S]*)$"#) else { return nil }
        var ingredients: [Ingredient] = []
        for piece in pieces {
            let ns = piece as NSString
            guard let match = leading.firstMatch(in: piece, range: NSRange(location: 0, length: ns.length)),
                  let amount = Double(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return nil }
            let ingredient = IngredientParser.parse(piece)
            // Parse the WHOLE item: the measured quantity must round-trip and leave a
            // name. The parser moves comma/parenthesis tails into notes, so a tail is
            // accepted only as explicit preparation syntax (the closed whitelist in
            // isPrepOnly); any other tail - an unmeasured item ("2 onions, salt"), an
            // interior heading with or without a colon ("2 onions, For the sauce"),
            // hedging prose ("2 onions (salt to taste)") - makes the item unverifiable
            // and is refused honestly rather than certified with the tail dropped into
            // notes. Ambiguity absorbed into the name itself ("2 onions salt to
            // taste") is refused by the name guards.
            let name = ingredient.name.trimmingCharacters(in: .whitespaces)
            let remainder = ns.substring(with: match.range(at: 2))
            let itemTails = tails(in: remainder)
            guard amount.isFinite, amount > 0, amount == ingredient.quantity, !name.isEmpty,
                  name.range(of: #"[.:;]"#, options: .regularExpression) == nil,
                  name.range(of: #"\b(?:to taste|as needed|as required|optional)\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  name.split(whereSeparator: { $0.isWhitespace }).count <= 3,
                  itemTails.allSatisfy(isPrepOnly) else { return nil }
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

    /// A caption is recognizable when it carries the explicit "you need" list marker
    /// followed by a measured-looking first item. Recognition alone is never
    /// verification: a recognizable caption whose list fails certification fails
    /// closed instead of falling through to creative generation or a demo substitute.
    static func claimsInlineCaption(_ raw: String) -> Bool {
        let source = CaptionAnalysis.stripInstagramPrefix(raw)
        guard let marker = source.range(of: #"\byou need\s+"#, options: [.regularExpression, .caseInsensitive]) else { return false }
        return source[marker.upperBound...].range(of: #"^\d"#, options: .regularExpression) != nil
    }

    static func extraction(_ raw: String) -> Extraction {
        if let contract = inlineCaption(raw) ?? structuredRecipe(raw) { return .verified(contract) }
        return claimsStructuredRecipe(raw) || claimsInlineCaption(raw) ? .unverifiable : .none
    }

    static func rejectUngroundedText(_ raw: String) throws {
        if CaptionAnalysis.isUngroundedPromo(raw) {
            throw BackendError(message: "This doesn't look like a recipe or name a dish. Paste a recipe or tell ate the dish you want.")
        }
    }
}
