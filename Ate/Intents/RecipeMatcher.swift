import Foundation

/// Ranks recipes for a spoken or typed name: exact → title prefix → word prefix → contains → edit distance.
/// Returns nothing rather than an unrelated recipe.
enum RecipeMatcher {
    struct Hit { let recipe: RecipeCard; let score: Double }

    static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    static func rank(_ recipes: [RecipeCard], query: String) -> [Hit] {
        let q = norm(query)
        guard q.count >= 2 else { return [] }
        return recipes.compactMap { r -> Hit? in
            let t = norm(r.title)
            let words = t.split(separator: " ").map(String.init)
            let s: Double
            if t == q { s = 1 }
            else if t.hasPrefix(q) { s = 0.95 }
            else if words.contains(where: { $0.hasPrefix(q) }) { s = 0.9 }
            else if t.contains(q) { s = 0.85 }
            else {
                // Best similarity of the query against the title, its leading words, or any single word.
                var cands = words; cands.append(t)
                let qw = q.split(separator: " ").count
                if qw > 1, words.count >= qw { cands.append(words.prefix(qw).joined(separator: " ")) }
                let best = cands.map { similarity(q, $0) }.max() ?? 0
                guard best >= 0.6 else { return nil }
                s = 0.8 * best
            }
            return Hit(recipe: r, score: s)
        }.sorted { $0.score > $1.score }
    }

    /// Hits that are close to the best one (the set to disambiguate between).
    static func nearTop(_ hits: [Hit]) -> [Hit] {
        guard let top = hits.first else { return [] }
        return hits.filter { top.score - $0.score < 0.1 }
    }
    static func isConfident(_ hits: [Hit]) -> Bool {
        guard let top = hits.first else { return false }
        return top.score >= 0.85 && nearTop(hits).count == 1
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let n = max(a.count, b.count)
        return n == 0 ? 1 : 1 - Double(levenshtein(a, b)) / Double(n)
    }
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }; if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }
}
