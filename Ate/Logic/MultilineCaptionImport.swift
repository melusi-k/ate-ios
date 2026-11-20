import Foundation

/// A line-delimited caption has explicit item boundaries even without an
/// Ingredients heading. Group source rows only; never infer or fill recipe facts.
enum MultilineCaptionImport {
    static func card(_ text: String) -> RecipeCard? {
        var rows = SourceDraftImport.lines(text)
        // Presentation framing is retained in raw source, not cooking directions.
        if rows.first?.range(of: #"^(?:sample\s+)?(?:caption|recipe),?\s+paste as is\s*:$"#,
                             options: [.regularExpression, .caseInsensitive]) != nil {
            rows.removeFirst()
        }
        guard rows.count >= 4 else { return nil }
        let markers = rows.indices.filter {
            rows[$0].range(of: #"^(?:method|directions|instructions)\s*:"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard markers.count == 1, let methodStart = markers.first, methodStart >= 3,
              rows[0].count <= 160, !SourceDraftImport.isAction(rows[0]),
              rows[0].range(of: #"[:\d]"#, options: .regularExpression) == nil else { return nil }
        let items = Array(rows[1..<methodStart])
        // Two leading measured rows establish the list. Later unmeasured rows
        // (such as salt and pepper) stay whole and unspecified, never omitted.
        guard (2...40).contains(items.count), items.prefix(2).allSatisfy({
            $0.range(of: #"^\d+(?:[./]\d+)?\s+\p{L}"#, options: .regularExpression) != nil
        }), items.allSatisfy({
            $0.count <= 160 && !SourceDraftImport.isAction($0)
                && $0.range(of: #"[:;.!?]"#, options: .regularExpression) == nil
                && !$0.hasPrefix("http")
        }) else { return nil }
        let method = Array(rows[methodStart...])
        guard method.contains(where: SourceDraftImport.isAction) else { return nil }
        let exactServings = SourceDraftImport.servings(text)
        var result = RecipeCard(title: rows[0], servings: exactServings ?? 0,
            ingredients: items.map { .init(name: $0, quantity: 0, unit: "", notes: nil) },
            steps: method.enumerated().map { .init(order: $0.offset + 1, instruction: $0.element, timeSeconds: nil) },
            source: .imported)
        result.sourceDraft = .init(text: text,
            warnings: ["Imported from your source. Check the ingredient and method grouping. Unspecified amounts, servings and times are blank; no missing facts were filled in."],
            unknownServings: exactServings == nil)
        result.aiNote = result.sourceDraft?.warnings.joined(separator: " ")
        return result
    }
}
