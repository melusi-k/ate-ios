import Foundation

/// Narrow source contract for explicitly measured inline captions. This is not a
/// general natural-language/OCR recipe parser. Unsupported structure stays on its
/// existing path; it must not be labelled fidelity-verified by this check.
enum SourceRecipeFidelity {
    struct Contract {
        let text: String
        let ingredients: [Ingredient]
        let method: String

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
        return Contract(text: source, ingredients: ingredients, method: method)
    }

    static func rejectUngroundedText(_ raw: String) throws {
        if CaptionAnalysis.isUngroundedPromo(raw) {
            throw BackendError(message: "This doesn't look like a recipe or name a dish. Paste a recipe or tell ate the dish you want.")
        }
    }
}
