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
            else if tokensAllMatch(q, words) { s = 0.86 }
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

    /// Every query word (minus stop words) is a prefix of some title word: "chicken rice" → "Classic Chicken and Rice".
    static func tokensAllMatch(_ q: String, _ words: [String]) -> Bool {
        let toks = tokens(q)
        return !toks.isEmpty && toks.allSatisfy { t in words.contains { $0.hasPrefix(t) } }
    }

    static let stopWords: Set<String> = ["a", "an", "the", "and", "with", "in", "on", "of", "for", "to", "my", "me", "some", "please",
                                         "cook", "make", "start", "open", "find", "show", "search", "recipe", "recipes", "ate"]
    /// Lowercased, diacritic-free search words without stop words.
    static func tokens(_ s: String) -> [String] {
        norm(s).lowercased().split(separator: " ").map(String.init).filter { !stopWords.contains($0) }
    }

    enum Verb: String { case cook, make, start, open, find, show, search }
    /// Strips a leading verb ("cook", "start cook mode for", "search for") and a trailing "in/with/on ate".
    static func cleanQuery(_ raw: String) -> (verb: Verb?, query: String) {
        let folded: String = raw.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var cleaned = ""
        for ch in folded { cleaned.append(ch.isLetter || ch.isNumber || ch == "'" ? ch : " ") }
        var w: [String] = cleaned.split(separator: " ").map { String($0) }
        while let l = w.last, ["ate", "app", "please"].contains(l) {
            w.removeLast()
            if let p = w.last, ["in", "with", "on", "using", "from"].contains(p) { w.removeLast() }
        }
        var verb: Verb?
        if let f = w.first, let v = Verb(rawValue: f) {
            verb = v; w.removeFirst()
            for lead in [["cook", "mode", "for"], ["cook", "mode"], ["for"], ["me"], ["the"], ["a"], ["recipe", "for"], ["recipe"]] {
                if w.starts(with: lead) { w.removeFirst(lead.count) }
            }
        }
        return (verb, w.joined(separator: " "))
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
