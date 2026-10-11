import Foundation

enum RecipeLogic {
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func scaled(_ card: RecipeCard, factor: Double) -> RecipeCard {
        var c = card
        c.ingredients = card.ingredients.map { var i = $0; i.quantity = round2($0.quantity * factor); return i }
        c.servings = Int((Double(card.servings) * factor).rounded())
        c.steps = nonBlank(card.steps)
        return c
    }

    static func normalize(_ card: RecipeCard) -> RecipeCard {
        var c = card
        let t = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
        c.title = t.isEmpty ? "Untitled recipe" : (RecipeQuality.isGenerated(c) ? RecipeQuality.titleCased(t) : t)
        c.servings = max(1, c.servings)
        c.tags = c.tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        c.ingredients = c.ingredients.map { var i = $0; if !i.quantity.isFinite { i.quantity = 0 }; return i }
        c.steps = nonBlank(c.steps).enumerated().map { idx, s in var s = s; s.order = idx + 1; return s }
        let fixed = Durations.sanitize(c)
        c = fixed.card
        if fixed.corrected {
            let note = "Some cooking times looked wrong and were corrected from the step text — check them before cooking."
            if !(c.aiNote ?? "").contains("cooking times") { c.aiNote = [c.aiNote, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
        }
        return c
    }

    /// P0 duplicate-save cleanup: one card per id, and exact duplicates (same title, ingredients and steps, created
    /// within `window` ms of each other) merged into the earliest copy (keeps favourite/cover/cook date if any copy has them).
    static func dedupe(_ cards: [RecipeCard], window: Double = 15 * 60 * 1000) -> (cards: [RecipeCard], removedIDs: [String]) {
        func key(_ c: RecipeCard) -> String {
            let t = c.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let i = c.ingredients.map { "\($0.name.lowercased())|\($0.quantity)|\($0.unit.lowercased())" }.joined(separator: ";")
            let s = nonBlank(c.steps).map { $0.instruction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ";")
            return t + "#" + i + "#" + s
        }
        var out: [RecipeCard] = [], removed: [String] = [], seenIDs = Set<String>()
        for c in cards {
            if seenIDs.contains(c.id) { continue }
            seenIDs.insert(c.id)
            if let k = out.firstIndex(where: { key($0) == key(c) && abs($0.createdAt - c.createdAt) <= window }) {
                var keep = out[k].createdAt <= c.createdAt ? out[k] : c
                let other = keep.id == c.id ? out[k] : c
                keep.favorite = keep.favorite || other.favorite
                if keep.coverImage == nil { keep.coverImage = other.coverImage }
                if keep.imageURL == nil { keep.imageURL = other.imageURL }
                keep.lastCookedAt = [keep.lastCookedAt, other.lastCookedAt].compactMap { $0 }.max()
                out[k] = keep; removed.append(other.id)
            } else { out.append(c) }
        }
        return (out, removed)
    }

    /// Drops steps whose instruction is empty/whitespace/punctuation only.
    static func nonBlank(_ steps: [Step]) -> [Step] {
        steps.filter { $0.instruction.rangeOfCharacter(from: .alphanumerics) != nil }
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
            var l = "• " + [amt, i.name].filter { !$0.isEmpty }.joined(separator: " ")
            if let n = i.notes, !n.isEmpty { l += " (\(n))" }
            lines.append(l)
        }
        lines.append("")
        lines.append("Steps")
        for (idx, s) in r.steps.enumerated() {
            lines.append("\(idx + 1). \(sentenceCase(Units.convertTemperatures(in: s.instruction, to: units)))")
        }
        if let s = r.sourceURL, !s.isEmpty { lines.append(""); lines.append("Source: \(s)") }
        if let u = shareURL { lines.append(""); lines.append("View in ate: \(u)") }
        return lines.joined(separator: "\n")
    }

    static func sentenceCase(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let f = t.first else { return t }
        return f.uppercased() + t.dropFirst()
    }

    static func matches(_ card: RecipeCard, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let hay = ([card.title, card.description ?? "", card.cuisine ?? ""] + card.tags + card.ingredients.map(\.name))
            .joined(separator: " ").lowercased()
        if hay.contains(q) { return true }
        // Token search: every meaningful word must appear somewhere (title, ingredients, tags), so "Cook Rice" finds rice dishes.
        let toks = RecipeMatcher.tokens(q)
        guard !toks.isEmpty else { return false }
        let words = Set(RecipeMatcher.norm(hay).lowercased().split(separator: " ").map(String.init))
        return toks.allSatisfy { t in words.contains { $0.hasPrefix(t) } }
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
