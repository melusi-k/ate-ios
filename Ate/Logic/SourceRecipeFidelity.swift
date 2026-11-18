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
            // A multi-part source can repeat a name across components (cocoa in the
            // cake and the custard): match each source item to ONE card item by
            // name + quantity + unit, consuming it. A verbatim unmeasured item
            // (quantity 0) binds by name alone.
            var unmatched = card.ingredients
            for source in ingredients {
                if let i = unmatched.firstIndex(where: {
                    Self.name($0.name) == Self.name(source.name)
                        && (source.quantity == 0
                            ? $0.quantity == 0
                            : ($0.quantity == source.quantity && Self.unit($0.unit) == Self.unit(source.unit)))
                }) {
                    unmatched.remove(at: i)
                    continue
                }
                if card.ingredients.contains(where: { Self.name($0.name) == Self.name(source.name) }) {
                    // A source item listed without an amount must stay without one:
                    // any generated quantity is invented.
                    failures.append(source.quantity == 0
                        ? "The source lists \(source.name) without an amount; do not invent one."
                        : "Preserve source quantity/unit: \(source.quantity) \(source.unit) \(source.name).")
                } else {
                    failures.append("Preserve the source ingredient: \(source.name).")
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
                let titleLower = card.title.lowercased()
                let namedInTitle = dishes.contains { titleLower.contains($0.lowercased()) }
                let titled = Set(CuisineGlossary.matches(in: card.title).map(\.name))
                if !namedInTitle, titled.isDisjoint(with: dishes) {
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
        // A caption that names its dish ("Mogodu Monday! you need: ...") binds the
        // title exactly like a headered source; a caption that names nothing keeps
        // the honest Unknown-dish path and the user question. Never derive one.
        let captionHeader = String(source[..<marker.lowerBound])
        var dishes = CuisineGlossary.matches(in: captionHeader).map(\.name)
        if let named = captionDishName(captionHeader), !dishes.contains(where: { $0.lowercased() == named.lowercased() }) {
            dishes.append(named)
        }
        return Contract(text: source, ingredients: ingredients, method: method, dishes: dishes)
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
        if let notes = method.range(of: #"\b(?:hints?\s*(?:&|and)\s*tips|tips|variations|notes|faqs?|frequently asked|related recipes)\b\s*:?"#,
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

    /// A section heading needs a STRUCTURAL marker, never capitalisation or a
    /// food noun alone: a trailing colon, or a "For ..."/"To ..." lead-in. This
    /// one rule is shared by the multi-part and caption extractors so the two
    /// can never diverge. "Soy Sauce", "Worcestershire Sauce", "Golden Syrup"
    /// and "Pasta of Choice" are items: an ambiguous line binds as an
    /// ingredient or the contract fails closed, never silently dropped.
    private static func isSectionHeading(_ line: String) -> Bool {
        guard isShapedLine(line) else { return false }
        if line.hasSuffix(":") { return true }
        let lower = line.lowercased()
        return lower.hasPrefix("for ") || lower.hasPrefix("to ")
    }

    /// The short Title Case shape a heading and an unmeasured item share: 1 to 4
    /// capitalised words (and connectors) with no digit, fraction or sentence
    /// punctuation. A colon is a marker, never a disqualifier.
    private static func isShapedLine(_ line: String) -> Bool {
        line.range(of: #"^(?:[A-Z][A-Za-z'&.-]*|the|and|of|for|with|to|a|an)(?:\s+(?:[A-Z][A-Za-z'&.-]*|the|and|of|for|with|to|a|an)){0,3}\s*:?$"#, options: .regularExpression) != nil
            && line.range(of: #"[0-9\x{00BC}\x{00BD}\x{00BE}\x{2153}\x{2154};.*]"#, options: .regularExpression) == nil
    }

    /// A shaped line that is not a structural heading binds as an unmeasured
    /// item (quantity 0): "Soy Sauce" is kept, never silently dropped.
    private static func unmeasuredShapedItem(_ line: String) -> Ingredient? {
        guard isShapedLine(line), !line.hasSuffix(":") else { return nil }
        let parsed = IngredientParser.parse(line)
        let name = parsed.name.trimmingCharacters(in: .whitespaces)
        guard parsed.quantity == 0, !name.isEmpty else { return nil }
        return Ingredient(name: name, quantity: 0, unit: "", notes: parsed.notes)
    }

    /// A parenthesized measure equivalent ("(1/2 cup)", "(1 tsp)") is the source
    /// restating the same amount in other units, not new content.
    private static func isMeasureEquivalent(_ tail: String) -> Bool {
        let t = tail.trimmingCharacters(in: .whitespaces)
        return t.range(of: #"^(?:\d+(?:[.,]\d+)?|[\x{00BC}\x{00BD}\x{00BE}\x{2153}\x{2154}\x{2155}\x{2156}\x{2157}\x{2158}\x{2159}\x{215A}\x{215B}])\s*(?:cups?|tbsp|tsp|ml|l|g|kg)$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// An explicitly unmeasured item is carried verbatim (quantity 0): the source's
    /// own words, never a guessed amount. Recognized shapes stay a closed set: a
    /// prep-led item ("Grated chocolate") or "a pinch/handful/dash/splash of ...".
    private static func unmeasuredItem(_ line: String) -> Ingredient? {
        let lower = line.lowercased()
        let shaped = prepTerms.contains { lower.hasPrefix($0 + " ") }
            || lower.range(of: #"^a (pinch|handful|dash|splash) of "#, options: .regularExpression) != nil
        guard shaped, line.range(of: #"[.:;]"#, options: .regularExpression) == nil,
              line.split(whereSeparator: { $0.isWhitespace }).count <= 5 else { return nil }
        let parsed = IngredientParser.parse(line)
        var name = parsed.name.trimmingCharacters(in: .whitespaces)
        // "A pinch of salt" parses whole (quantity 0, the lead inside the name):
        // the pinch phrase is the source's own measure, so the item binds
        // quantity-less under the ingredient's own name, the "a ... of" lead
        // normalised away. A parser-recognised pinch measure (quantity 1 unit
        // pinch) binds the same way.
        if let lead = lower.range(of: #"^a (?:pinch|handful|dash|splash) of "#, options: .regularExpression) {
            name = String(line[lead.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        let pinchClass = parsed.quantity == 1 && ["pinch", "handful", "dash", "splash"].contains(parsed.unit.lowercased())
        guard parsed.quantity == 0 || pinchClass, !name.isEmpty else { return nil }
        return Ingredient(name: name, quantity: 0, unit: "", notes: parsed.notes)
    }

    /// One measured item line in a multi-part list: quantity first (digits or a
    /// vulgar fraction; unit adjacency allowed: "125g", "1/4 tsp"), then the item.
    /// The quantity must round-trip through IngredientParser, and tails stay
    /// prep-only or measure equivalents. Any ambiguity refuses the whole recipe.
    private static func measuredItem(_ line: String) -> Ingredient? {
        let split = line.replacingOccurrences(of: #"\s+(?=\d+(?:[.,]\d+)?\s)"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard split.count == 1, let piece = split.first else { return nil }
        // ASCII fractions and mixed numbers round-trip too ("1/4 tsp", "1 1/2 cups"),
        // not only leading integers, decimals and vulgar fractions.
        var amount: Double
        var rest: Substring
        if let m = piece.range(of: #"^\d+\s+\d+/\d+"#, options: .regularExpression) {
            let parts = piece[m].split(whereSeparator: { $0.isWhitespace || $0 == "/" }).compactMap { Double($0) }
            guard parts.count == 3, parts[2] > 0 else { return nil }
            amount = parts[0] + parts[1] / parts[2]; rest = piece[m.upperBound...]
        } else if let m = piece.range(of: #"^\d+/\d+"#, options: .regularExpression) {
            let parts = piece[m].split(separator: "/").compactMap { Double($0) }
            guard parts.count == 2, parts[1] > 0 else { return nil }
            amount = parts[0] / parts[1]; rest = piece[m.upperBound...]
        } else if let m = piece.range(of: #"^(?:\d+(?:[.,]\d+)?|[\x{00BC}\x{00BD}\x{00BE}\x{2153}\x{2154}\x{2155}\x{2156}\x{2157}\x{2158}\x{2159}\x{215A}\x{215B}])"#,
                                      options: .regularExpression) {
            let token = String(piece[m])
            amount = Double(token.replacingOccurrences(of: ",", with: ".")) ?? IngredientParser.vulgar[token.first!] ?? 0
            rest = piece[m.upperBound...]
        } else { return nil }
        if let c = rest.first, let frac = IngredientParser.vulgar[c] { amount += frac; rest = rest.dropFirst() }
        let ingredient = IngredientParser.parse(piece)
        let name = ingredient.name.trimmingCharacters(in: .whitespaces)
        let itemTails = tails(in: String(rest))
        // IngredientParser rounds to hundredths: 1/3 is 0.333... here, 0.33 there.
        // Compare at the parser's own precision, never exact binary equality.
        guard amount.isFinite, amount > 0, (amount * 100).rounded() == (ingredient.quantity * 100).rounded(), !name.isEmpty,
              name.range(of: #"[.:;]"#, options: .regularExpression) == nil,
              name.range(of: #"\b(?:to taste|as needed|as required|optional)\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
              name.split(whereSeparator: { $0.isWhitespace }).count <= 5,
              itemTails.allSatisfy({ isPrepOnly($0) || isMeasureEquivalent($0) }) else { return nil }
        return ingredient
    }

    /// Multi-part full-recipe text: ONE Ingredients section whose items are grouped
    /// under Title Case sub-headings (cake, custard, syrup, garnish), then one
    /// Method/Directions/Instructions section. The honesty bar matches the
    /// single-section path: every line is a measured item, an explicitly
    /// unmeasured item carried verbatim, or a sub-heading; anything else makes the
    /// whole recipe unverifiable rather than partially certified.
    static func multiPartRecipe(_ raw: String) -> Contract? {
        // Social/page copies pad lines with no-break spaces (U+00A0/U+202F); treat
        // them as ordinary whitespace or every heading and item keeps a stray tail.
        let text = raw.replacingOccurrences(of: #"[ \t\x{00A0}\x{202F}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Recipe pages repeat the word in navigation before the real section; try
        // each candidate until one certifies, never just the first.
        var searchStart = text.startIndex
        while let ingredientsMarker = text.range(of: #"\bingredients\b\s*:?"#, options: [.regularExpression, .caseInsensitive],
                                                 range: searchStart..<text.endIndex) {
            if let contract = multiPartCandidate(text, ingredientsMarker: ingredientsMarker) { return contract }
            searchStart = ingredientsMarker.upperBound
        }
        return nil
    }

    private static func multiPartCandidate(_ text: String, ingredientsMarker: Range<String.Index>) -> Contract? {
        guard let methodMarker = text.range(of: #"\b(?:method|directions|instructions)\b\s*:?"#, options: [.regularExpression, .caseInsensitive],
                                            range: ingredientsMarker.upperBound..<text.endIndex) else { return nil }
        let header = String(text[..<ingredientsMarker.lowerBound])
        let rawSegment = String(text[ingredientsMarker.upperBound..<methodMarker.lowerBound])
        var method = String(text[methodMarker.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let notes = method.range(of: #"\b(?:hints?\s*(?:&|and)\s*tips|tips|variations|notes|faqs?|frequently asked|related recipes)\b\s*:?"#,
                                    options: [.regularExpression, .caseInsensitive]) {
            method = String(method[..<notes.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        // A second recipe's measured section makes every boundary ambiguous.
        guard !method.isEmpty, CaptionAnalysis.hasRecipeSignals(method),
              method.range(of: #"\bingredients\b\s*:?\s*\d"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        let lines = rawSegment.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var ingredients: [Ingredient] = []
        for line in lines {
            let stripped = line.replacingOccurrences(of: #"^[•·*\-–— ]+"#, with: "", options: .regularExpression)
            // A line drops only on an explicit structural marker (a colon, a
            // For/To lead-in); every other shaped line binds as an item,
            // measured or unmeasured, or the candidate fails closed.
            // Ambiguity is never resolved by dropping.
            if isSectionHeading(stripped) { continue }
            if let item = unmeasuredItem(stripped) { ingredients.append(item); continue }
            guard let item = measuredItem(stripped) ?? unmeasuredShapedItem(stripped) else { return nil }
            ingredients.append(item)
        }
        guard (2...60).contains(ingredients.count) else { return nil }
        // A repeated name across components is legitimate (cocoa in cake and
        // custard); an exact same-item repeat has no defensible boundary.
        var seen = Set<String>()
        for ingredient in ingredients {
            let key = "\(ingredient.name.lowercased())|\(ingredient.quantity)|\(ingredient.unit.lowercased())"
            guard seen.insert(key).inserted else { return nil }
        }
        // Only the dish named near the section anchors the title; distant site
        // navigation may name unrelated dishes and never grounds the card title.
        let dishes = CuisineGlossary.matches(in: String(header.suffix(200))).map(\.name)
        return Contract(text: text, ingredients: ingredients, method: method, dishes: dishes)
    }

    /// The dish a caption names in its own first line: a short title before a dash or
    /// colon break ("Marry Me Shrimp Pasta - creamy garlic shrimp..."), taken verbatim.
    /// Never derived: no break, no name. Sentences, hashtags and handles are not titles.
    static func captionDishName(_ header: String) -> String? {
        let line = header.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard let split = line.range(of: #"^(.{2,60}?)\s*[-\x{2013}\x{2014}:]\s+\S"#, options: .regularExpression),
              let dash = line[split].lastIndex(where: { "-\u{2013}\u{2014}:".contains($0) }) else { return nil }
        let title = String(line[split.lowerBound..<dash]).trimmingCharacters(in: .whitespaces)
        let words = title.split(whereSeparator: { $0.isWhitespace })
        guard (1...8).contains(words.count),
              title.range(of: #"^[A-Za-z\x{00C0}-\x{017F}]"#, options: .regularExpression) != nil,
              title.range(of: #"[@#$/]|https?:"#, options: .regularExpression) == nil,
              title.range(of: #"[.!?]$"#, options: .regularExpression) == nil else { return nil }
        return title
    }


    /// Lines that never belong to a caption's ingredient list: trailers pointing at
    /// the full recipe, engagement prompts, dates, tags and links.
    private static func isCaptionTrailer(_ line: String) -> Bool {
        line.range(of: #"(?i)full recipe|link in (my )?bio|recipe (is )?in (my )?bio|comment |follow |save this|share this"#, options: .regularExpression) != nil
            || line.hasPrefix("#") || line.hasPrefix("@")
            || line.range(of: #"https?:"#, options: .regularExpression) != nil
            || line.range(of: #"^(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}"#, options: .regularExpression) != nil
    }

    /// Social captions that name a dish and list ingredients WITHOUT quantities and
    /// without a method ("Full recipe linked in my bio"): the list binds verbatim as
    /// unmeasured items; amounts are never invented, and an empty method binds nothing.
    static func captionSections(_ raw: String) -> Contract? {
        let source = CaptionAnalysis.stripInstagramPrefix(raw)
        guard let marker = source.range(of: #"\bingredients\b\s*:?"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let header = String(source[..<marker.lowerBound])
        var dishes = CuisineGlossary.matches(in: header).map(\.name)
        if let named = captionDishName(header), !dishes.contains(where: { $0.lowercased() == named.lowercased() }) {
            dishes.append(named)
        }
        let body = source[marker.upperBound...]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var ingredients: [Ingredient] = []
        for line in body {
            if isCaptionTrailer(line) { break }
            let stripped = line.replacingOccurrences(of: #"^[•·*\-–— ]+"#, with: "", options: .regularExpression)
            if isSectionHeading(stripped) { continue }
            // A measured line means this caption is not the quantity-less shape; other
            // extractors own it. Anything else unparseable refuses the whole list.
            guard stripped.range(of: #"\d"#, options: .regularExpression) == nil,
                  stripped.range(of: #"[.:;]"#, options: .regularExpression) == nil,
                  stripped.split(whereSeparator: { $0.isWhitespace }).count <= 6 else { return nil }
            let parsed = IngredientParser.parse(stripped)
            let name = parsed.name.trimmingCharacters(in: .whitespaces)
            guard parsed.quantity == 0, !name.isEmpty,
                  name.range(of: #"\b(?:to taste|as needed|as required|optional)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
            ingredients.append(Ingredient(name: name, quantity: 0, unit: "", notes: parsed.notes))
        }
        guard ingredients.count >= 2 else { return nil }
        // A name may repeat across sections (paprika in the rub and the sauce);
        // order and count in issues() still bind the list exactly.
        return Contract(text: source, ingredients: ingredients, method: "", dishes: dishes)
    }

    /// A caption in the quantity-less shape is recognizable from its Ingredients
    /// marker plus at least one bulleted or sectioned line; recognition without a
    /// parse fails closed, it never reaches creative generation.
    static func claimsCaptionSections(_ raw: String) -> Bool {
        let source = CaptionAnalysis.stripInstagramPrefix(raw)
        guard let marker = source.range(of: #"\bingredients\b\s*:?"#, options: [.regularExpression, .caseInsensitive]) else { return false }
        return source[marker.upperBound...].range(of: #"^[•·*\-–— ]*\S"#, options: .regularExpression) != nil
    }

    /// A dish answer on a source-bound import sets the title only: the contract's
    /// ingredients are re-applied verbatim (generation may never drift or replace
    /// them), and a typed dish that contradicts the source's own named dish keeps
    /// the source - its facts and its name - and says so in the card's note.
    static func applyingDishConfirmation(_ card: inout RecipeCard, contract: Contract, hint: String) {
        card.ingredients = contract.ingredients
        let typed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        if !contract.dishes.isEmpty,
           !contract.dishes.contains(where: { $0.lowercased() == typed.lowercased() }) {
            card.title = contract.dishes[0]
            card.aiNote = "The source names \(contract.dishes[0]); its recipe and name were kept. Your answer \"\(typed)\" was not applied as the title."
        } else {
            card.title = typed
        }
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

    /// Recipe-shaped text must bind or fail closed, however short or long and
    /// whatever dishes it mentions: explicit Ingredients/Method markers, or at
    /// least two measured quantity lines plus at least two numbered step lines.
    /// Only text with neither shape is an idea prompt for creative generation.
    static func isRecipeShaped(_ raw: String) -> Bool {
        if raw.range(of: #"\bingredients\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
           raw.range(of: #"\b(?:method|directions|instructions)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let lines = raw.components(separatedBy: .newlines)
        let measured = lines.filter {
            $0.range(of: #"^[\x{2022}\x{00B7}*\-\x{2013}\x{2014} ]*(?:\d+(?:[.,]\d+)?|\d+\s+\d+/\d+|\d+/\d+|[\x{00BC}\x{00BD}\x{00BE}\x{2153}\x{2154}])\s*(?:[A-Za-z]{1,12}\s)?\S"#, options: .regularExpression) != nil
        }.count
        let steps = lines.filter {
            $0.range(of: #"^[\x{2022}\x{00B7}*\-\x{2013}\x{2014} ]*(?:step\s+)?\d+[.)]\s"#, options: [.regularExpression, .caseInsensitive]) != nil
        }.count
        return measured >= 2 && steps >= 2
    }

    static func extraction(_ raw: String) -> Extraction {
        if let contract = inlineCaption(raw) ?? structuredRecipe(raw) ?? multiPartRecipe(raw) ?? captionSections(raw) { return .verified(contract) }
        return claimsStructuredRecipe(raw) || claimsInlineCaption(raw) || claimsCaptionSections(raw) || isRecipeShaped(raw) ? .unverifiable : .none
    }

    static func rejectUngroundedText(_ raw: String) throws {
        if CaptionAnalysis.isUngroundedPromo(raw) {
            throw BackendError(message: "This doesn't look like a recipe or name a dish. Paste a recipe or tell ate the dish you want.")
        }
    }
}
