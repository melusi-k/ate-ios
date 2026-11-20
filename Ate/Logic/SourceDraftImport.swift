import Foundation

/// Additive import state. Zero servings/quantity means unspecified only on this
/// source-backed path. Raw source survives review, edits, save and archives.
struct SourceDraft: Codable, Hashable {
    var text: String
    var warnings: [String]
    var unknownServings: Bool
    static func applies(to card: RecipeCard) -> Bool {
        [.imported, .jsonLD].contains(card.source) && card.sourceDraft != nil
    }
}

/// Classification only: the model selects indices, never writes recipe facts.
struct SourceLineSelection: Codable, Equatable {
    var title: Int?
    var ingredients: [Int]
    var method: [Int]
}

enum SourceDraftImport {
    static let unreadable = BackendError(message: "Ate couldn't read a recipe from that source. Your input is kept. Paste readable recipe text, try a clearer screenshot, or enter it manually.")
    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    static func hasSource(_ text: String) -> Bool {
        switch SourceRecipeFidelity.extraction(text) {
        case .verified(let contract): return !contract.ingredients.isEmpty || !contract.method.isEmpty
        case .unverifiable:
            let rows = lines(text)
            let content = rows.filter { $0.range(of: #"^(?:ingredients|method|directions|instructions)\s*:?$"#, options: [.regularExpression, .caseInsensitive]) == nil }
            return text.count >= 20 && (content.count >= 2 || rows.contains(where: isAction))
        case .none:
            let rows = lines(text)
            let actions = rows.filter(isAction)
            let actionCount = (try? NSRegularExpression(pattern: #"\b(?:add|mix|stir|cook|fry|simmer|boil|bake|roast|heat|drain|serve|chill|whisk)\b"#, options: .caseInsensitive))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
            let ingredientList = text.range(of: #"\bingredients\b"#, options: [.regularExpression, .caseInsensitive]) != nil && rows.count >= 3
            return text.count >= 20 && (ingredientList || (rows.count >= 2 && !actions.isEmpty) || actionCount >= 2)
                && !rows.allSatisfy { $0.hasPrefix("http") }
        }
    }
    static func isAction(_ line: String) -> Bool {
        line.range(of: #"\b(?:add|mix|stir|cook(?:ing)?|fry|simmer|boil|bake|roast|heat|sauté|saute|drain|serve|chill|whisk)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func selection(_ text: String) -> SourceLineSelection {
        let rows = lines(text)
        var ingredient: [Int] = [], method: [Int] = [], inMethod = false
        for (i, line) in rows.enumerated() {
            if line.range(of: #"^(?:method|directions|instructions)\s*:?$"#, options: [.regularExpression, .caseInsensitive]) != nil { inMethod = true; continue }
            if line.range(of: #"^ingredients\s*:?$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if inMethod || isAction(line) { method.append(i) }
            else if i > 0 { ingredient.append(i) }
        }
        return .init(title: rows.count > 1 && rows[0].count <= 160 && !isAction(rows[0]) ? 0 : nil, ingredients: ingredient, method: method)
    }
    /// Only the existing measured inline-caption contract can split a mixed
    /// ingredient/method line. Never infer sentence or ingredient boundaries.
    static func inlineCaptionCard(_ text: String) -> RecipeCard? {
        guard let contract = SourceRecipeFidelity.inlineCaption(text) else { return nil }
        let exactServings = servings(text)
        var card = RecipeCard(title: contract.dishes.first ?? "Imported recipe",
            servings: exactServings ?? 0, ingredients: contract.ingredients,
            steps: [.init(order: 1, instruction: contract.method, timeSeconds: nil)],
            source: .imported)
        card.sourceDraft = .init(text: text,
            warnings: ["Imported from your source. Check it before saving. Unspecified facts remain blank."],
            unknownServings: exactServings == nil)
        card.aiNote = card.sourceDraft?.warnings.joined(separator: " ")
        guard contract.issues(card).isEmpty else { return nil }
        return card
    }
    static func card(_ text: String, selected: SourceLineSelection) throws -> RecipeCard {
        let rows = lines(text)
        guard !rows.isEmpty, hasSource(text) else { throw unreadable }
        // Ignore invalid/duplicate selections; keep every other source line in
        // review as source text, so classification can never erase a fact.
        let titleIndex = selected.title.flatMap { rows.indices.contains($0) ? $0 : nil }
        var used = Set<Int>()
        if let titleIndex { used.insert(titleIndex) }
        let ingredients = selected.ingredients.filter { rows.indices.contains($0) && used.insert($0).inserted }
        let methods = selected.method.filter { rows.indices.contains($0) && used.insert($0).inserted }
        let unassigned = rows.indices.filter { !used.contains($0) }
        let title = titleIndex.map { rows[$0] } ?? "Imported recipe"
        let exactServings = servings(text)
        var card = RecipeCard(title: title, servings: exactServings ?? 0,
            ingredients: ingredients.sorted().map { .init(name: rows[$0], quantity: 0, unit: "", notes: nil) },
            steps: (methods + unassigned).sorted().enumerated().map { .init(order: $0.offset + 1, instruction: rows[$0.element], timeSeconds: nil) },
            source: .imported)
        card.sourceDraft = .init(text: text,
            warnings: ["Imported from your source. Check the ingredient and method grouping. Unspecified amounts, servings and times are blank; no missing facts were filled in."],
            unknownServings: exactServings == nil)
        if card.ingredients.isEmpty { card.sourceDraft?.warnings.append("No ingredient rows were recognized. Add them if you have them.") }
        if !card.steps.contains(where: { isAction($0.instruction) }) { card.sourceDraft?.warnings.append("No cooking instructions were recognized. Add them if you have them.") }
        card.aiNote = card.sourceDraft?.warnings.joined(separator: " ")
        return card
    }
    static func servings(_ text: String) -> Int? {
        let rows = lines(text)
        let declarations = rows.indices.filter { rows[$0].range(of: #"^(?:serves|servings|yields?|makes|portions)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
        guard declarations.count == 1, var index = declarations.first,
              rows[index].range(of: #"^serves\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        var value = rows[index].replacingOccurrences(of: #"(?i)^serves\s*:?\s*"#, with: "", options: .regularExpression)
        if value.isEmpty {
            index += 1
            guard rows.indices.contains(index) else { return nil }
            value = rows[index]
        }
        guard value.range(of: #"^[1-9]\d{0,2}$"#, options: .regularExpression) != nil else { return nil }
        if rows.indices.contains(index + 1), rows[index + 1].range(of: #"^(?:\d|[-/]|to\b|plus\b|and\b)"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        return Int(value)
    }
}
