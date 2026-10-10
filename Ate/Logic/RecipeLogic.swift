import Foundation

enum RecipeLogic {
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func scaled(_ card: RecipeCard, factor: Double) -> RecipeCard {
        var c = card
        c.ingredients = card.ingredients.map { var i = $0; i.quantity = round2($0.quantity * factor); return i }
        c.servings = Int((Double(card.servings) * factor).rounded())
        return c
    }

    static func normalize(_ card: RecipeCard) -> RecipeCard {
        var c = card
        let t = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
        c.title = t.isEmpty ? "Untitled recipe" : t
        c.servings = max(1, c.servings)
        c.tags = c.tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        c.ingredients = c.ingredients.map { var i = $0; if !i.quantity.isFinite { i.quantity = 0 }; return i }
        c.steps = c.steps.enumerated().map { idx, s in var s = s; s.order = idx + 1; return s }
        return c
    }

    /// Plain-text share format (PRD §7.4).
    static func text(for card: RecipeCard, factor: Double = 1, units: UnitSystem = .metric, shareURL: String? = nil) -> String {
        let r = scaled(card, factor: factor)
        var lines: [String] = [r.title]
        if let d = r.description, !d.isEmpty { lines.append(d) }
        var meta = "\(r.servings) servings"
        if let m = r.timeMinutes, m > 0 { meta += " · \(m) min" }
        lines.append(meta)
        lines.append("")
        lines.append("Ingredients")
        for i in r.ingredients {
            let (q, u) = Units.convert(quantity: i.quantity, unit: i.unit, to: units)
            let amt = Units.formatAmount(q, u)
            var l = "- " + [amt, i.name].filter { !$0.isEmpty }.joined(separator: " ")
            if let n = i.notes, !n.isEmpty { l += " (\(n))" }
            lines.append(l)
        }
        lines.append("")
        lines.append("Steps")
        for (idx, s) in r.steps.enumerated() {
            lines.append("\(idx + 1). \(Units.convertTemperatures(in: s.instruction, to: units))")
        }
        if let s = r.sourceURL, !s.isEmpty { lines.append(""); lines.append("Source: \(s)") }
        if let u = shareURL { lines.append(""); lines.append(u) }
        return lines.joined(separator: "\n")
    }

    static func matches(_ card: RecipeCard, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let hay = ([card.title, card.description ?? ""] + card.tags + card.ingredients.map(\.name))
            .joined(separator: " ").lowercased()
        return hay.contains(q)
    }

    /// Merge imported cards (PRD §6): skip empty cards, replace same id, count new ones.
    static func importCards(_ incoming: [RecipeCard], into existing: [RecipeCard]) -> (result: [RecipeCard], added: Int) {
        var result = existing
        var added = 0
        for card in incoming where !(card.ingredients.isEmpty && card.steps.isEmpty) {
            let n = normalize(card)
            if let idx = result.firstIndex(where: { $0.id == n.id }) { result[idx] = n }
            else { result.insert(n, at: 0); added += 1 }
        }
        return (result, added)
    }
}
