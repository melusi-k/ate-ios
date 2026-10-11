import Foundation

/// Duration parsing + sanity checks for recipe times (seconds for steps, minutes for totals).
/// Times NEVER scale with servings: RecipeLogic.scaled only touches ingredients and servings.
enum Durations {
    struct Span: Equatable { var lower: Int; var upper: Int }   // seconds

    static let maxStepSeconds = 12 * 3600          // nothing on a stove step runs longer than 12 h
    static let maxUntimedStepSeconds = 3 * 3600    // a model-only time (no duration in the text) above 3 h is not trusted
    static let maxTotalMinutes = 48 * 60

    private static let num = #"(\d+(?:[.,]\d+)?|½|¼|¾)"#
    private static let unit = #"(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#
    // "2 to 3 h", "2-3 hours", "8–10 mins", "1 hr 15 min", "1.5 h", "20 minutes"
    private static let pattern = "\(num)\\s*(?:(?:-|–|—|to|or)\\s*\(num)\\s*)?\(unit)(?:\\s*(?:and\\s*)?(\\d+)\\s*(minutes?|mins?|m)\\b)?"

    private static func value(_ s: String) -> Double? {
        switch s { case "½": return 0.5; case "¼": return 0.25; case "¾": return 0.75
        default: return Double(s.replacingOccurrences(of: ",", with: ".")) }
    }
    private static func mult(_ u: String) -> Double { u.hasPrefix("h") ? 3600 : (u.hasPrefix("m") ? 60 : 1) }

    static func spans(in text: String) -> [Span] {
        let l = text.lowercased()
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = l as NSString
        return re.matches(in: l, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let a = value(ns.substring(with: m.range(at: 1))) else { return nil }
            let k = mult(ns.substring(with: m.range(at: 3)))
            var lo = a * k, hi = lo
            if m.range(at: 2).location != NSNotFound, let b = value(ns.substring(with: m.range(at: 2))) { hi = max(a, b) * k; lo = min(a, b) * k }
            if m.range(at: 4).location != NSNotFound, let extra = Double(ns.substring(with: m.range(at: 4))) { lo += extra * 60; hi += extra * 60 }
            guard hi > 0 else { return nil }
            return Span(lower: Int(lo), upper: Int(hi))
        }
    }

    /// Timer for a step: the sum of upper bounds of the durations written in the text.
    static func seconds(in text: String) -> Int? {
        let t = spans(in: text).reduce(0) { $0 + $1.upper }
        return t > 0 && t <= maxStepSeconds ? t : nil
    }

    /// "120–180 min" for a single ranged duration, else nil.
    static func rangeLabel(in text: String) -> String? {
        let s = spans(in: text)
        guard s.count == 1, let r = s.first, r.lower != r.upper else { return nil }
        return "\(r.lower / 60)–\(r.upper / 60) min"
    }

    /// Minimum believable seconds for a step, by verb/keyword (nil when no rule applies).
    /// Used only for model-supplied times; a time written in the step text always wins.
    static let plausibilityRules: [(keywords: [String], minSeconds: Int)] = [
        (["braise", "stew", "slow cook", "slow-cook", "mogodu", "tripe", "oxtail"], 60 * 60),
        (["simmer", "boil until tender", "until tender", "potjie"], 20 * 60),
        (["pap", "phutu", "mealie", "maize meal", "polenta"], 15 * 60),
        (["roast", "bake", "baking", "oven"], 15 * 60),
        (["rice"], 12 * 60),
        (["brown", "sear", "fry the onion", "caramelise", "caramelised", "caramelize", "caramelized"], 5 * 60),
        (["steam", "wilt"], 3 * 60),
    ]
    static func minimumSeconds(for instruction: String) -> Int? {
        let l = instruction.lowercased()
        func has(_ k: String) -> Bool {
            if k.contains(" ") { return l.contains(k) }
            return l.range(of: "\\b\(NSRegularExpression.escapedPattern(for: k))(?:s|es|d|ed|ing)?\\b", options: .regularExpression) != nil
        }
        return plausibilityRules.filter { $0.keywords.contains(where: has) }.map(\.minSeconds).max()
    }

    /// Sanitised total minutes if believable for a "quick" list; nil when missing or implausibly short (e.g. "3 min" chicken feet).
    static func plausibleQuickMinutes(_ card: RecipeCard) -> Int? {
        let c = sanitize(card).card
        guard let t = c.timeMinutes, t >= 5 else { return nil }
        let stepMin = (c.steps.compactMap(\.timeSeconds).reduce(0, +) + 59) / 60
        if stepMin > t { return nil }
        if c.steps.count >= 4 && t < 10 { return nil }
        return t
    }

    /// Reconciles model/import times with the step text and caps nonsense. Returns the fixed card and whether anything changed.
    static func sanitize(_ card: RecipeCard) -> (card: RecipeCard, corrected: Bool) {
        var c = card, corrected = false
        // If the model's time is off by 5x or more on any step whose text states a time, its units can't be trusted anywhere.
        let unitsBroken = card.steps.contains { s in
            guard let t = seconds(in: s.instruction), let m = s.timeSeconds, m > 0 else { return false }
            return Double(max(t, m)) / Double(min(t, m)) >= 5
        }
        c.steps = card.steps.map { s in
            var s = s
            let fromText = seconds(in: s.instruction)
            let model = (s.timeSeconds ?? 0) > 0 ? s.timeSeconds : nil
            let fixed: Int?
            if let t = fromText { fixed = t }                                   // the written time always wins
            else if let m = model, !unitsBroken, m <= maxUntimedStepSeconds, m >= (minimumSeconds(for: s.instruction) ?? 0) { fixed = m }
            else { fixed = nil }
            if fixed != s.timeSeconds { corrected = corrected || model != nil; s.timeSeconds = fixed }
            return s
        }
        let stepMin = (c.steps.compactMap(\.timeSeconds).reduce(0, +) + 59) / 60
        if let total = c.timeMinutes, total > 0 {
            let implausible = total > maxTotalMinutes || (stepMin > 0 && total > stepMin * 2 + 60)
            if implausible { c.timeMinutes = stepMin > 0 ? stepMin : nil; corrected = true }
            else if stepMin > total { c.timeMinutes = stepMin }
        } else if stepMin > 0 { c.timeMinutes = stepMin }
        return (c, corrected)
    }
}
