import Foundation

/// schema.org/Recipe extraction from `<script type="application/ld+json">` blocks.
/// Runs before any AI call for links: most recipe sites publish structured data, so this is instant and exact.
enum JSONLD {
    static func recipe(fromHTML html: String, sourceURL: String? = nil) -> RecipeCard? {
        for block in scripts(html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            let host = sourceURL.flatMap { URL(string: $0)?.host }
            if let node = findRecipe(json), var card = card(from: node, host: host) {
                card.sourceURL = sourceURL
                return card
            }
        }
        return nil
    }

    static func scripts(_ html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func isRecipe(_ d: [String: Any]) -> Bool {
        if let t = d["@type"] as? String { return t.lowercased() == "recipe" }
        if let ts = d["@type"] as? [String] { return ts.contains { $0.lowercased() == "recipe" } }
        return false
    }

    static func findRecipe(_ any: Any) -> [String: Any]? {
        if let d = any as? [String: Any] {
            if isRecipe(d) { return d }
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"] {
                if let v = d[key], let r = findRecipe(v) { return r }
            }
        } else if let a = any as? [Any] {
            for v in a { if let r = findRecipe(v) { return r } }
        }
        return nil
    }

    /// Site suffixes ("Name | SITENAME") are SEO chrome, not the dish name. EVERY
    /// separator form (" | ", " :: ", en dash, em dash, " - ") is stripped only
    /// when the suffix names the site itself on a whole-name boundary: the trimmed
    /// suffix equals the registrable site name or holds it as its own token
    /// ("Chicken - eat.com" strips for eat.com; "Chicken - Wheat and Cheese" never
    /// does, wheat only CONTAINS eat); otherwise the whole title survives
    /// verbatim ("Chicken – Lemon and Herb" is a dish, not a suffix). Without a
    /// host nothing is stripped, and an unstripped title is returned untrimmed.
    static func cleanTitle(_ raw: String, host: String? = nil) -> String {
        var t = raw
        var stripped = false
        if let host {
            let site = registrableName(host)
            for sep in [" | ", " :: ", " \u{2013} ", " \u{2014} ", " - "] {
                if site.count >= 3, let i = t.range(of: sep, options: .backwards),
                   Self.suffixNamesSite(String(t[i.upperBound...]), site: site),
                   !t[..<i.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
                    t = String(t[..<i.lowerBound])
                    stripped = true
                }
            }
        }
        return stripped ? t.trimmingCharacters(in: .whitespacesAndNewlines) : raw
    }

    /// Whole-name boundary: the trimmed, lowercased suffix equals the site name or
    /// holds it as its own token (split on anything non-alphanumeric). Substring
    /// membership is never enough: "wheat" is not "eat".
    static func suffixNamesSite(_ suffix: String, site: String) -> Bool {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s == site || s.components(separatedBy: CharacterSet.alphanumerics.inverted).contains(site)
    }

    /// The registrable host name: a leading "www" is dropped, and second-level
    /// public suffixes (lancewood.co.za, example.com.au, ...) collapse to the
    /// name above them. The first label is never used: "www" matches nothing.
    static func registrableName(_ host: String) -> String {
        var labels = host.lowercased().split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        if labels.count >= 3, labels[labels.count - 1].count == 2,
           ["co", "com", "org", "net", "ac", "gov", "edu"].contains(labels[labels.count - 2]) {
            return labels[labels.count - 3]
        }
        return labels.count >= 2 ? labels[labels.count - 2] : (labels.first ?? "")
    }

    /// Calls to action make a page description useless as dish context. Prefer no
    /// description over the site's marketing blurb; genuine dish descriptions stay.
    static let marketingPhrases = ["try the recipe", "try this recipe", "try our", "explore our",
                                   "check out", "shop now", "shop the", "buy now", "order now",
                                   "sign up", "subscribe", "read more", "learn more", "find out more",
                                   "get the recipe", "click here"]
    static func isMarketingBlurb(_ text: String) -> Bool {
        let l = text.lowercased()
        return marketingPhrases.contains { l.contains($0) }
    }

    static func card(from d: [String: Any], host: String? = nil) -> RecipeCard? {
        guard let name = text(d["name"]), !name.isEmpty else { return nil }
        let ingredients = (d["recipeIngredient"] as? [Any] ?? d["ingredients"] as? [Any] ?? [])
            .compactMap { text($0) }.filter { !$0.isEmpty }.map(IngredientParser.parse)
        let steps = instructions(d["recipeInstructions"]).enumerated().map { i, s in
            Step(order: i + 1, instruction: s, timeSeconds: Durations.rangeLabel(in: s) == nil ? StepTimer.seconds(in: s) : nil)
        }
        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }
        let minutes = duration(text(d["totalTime"]))
        var tags: [String] = []
        for k in ["recipeCategory", "recipeCuisine", "keywords"] {
            if let s = d[k] as? String { tags += s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
            else if let a = d[k] as? [Any] { tags += a.compactMap { text($0)?.lowercased() } }
        }
        var seen = Set<String>()
        tags = tags.filter { !$0.isEmpty && $0.count <= 30 && seen.insert($0).inserted }
        let blurb = text(d["description"]).map(decode).map { String($0.prefix(300)) }
        var card = RecipeCard(title: cleanTitle(decode(name), host: host), description: blurb.flatMap { isMarketingBlurb($0) ? nil : $0 },
                          servings: servings(d["recipeYield"]) ?? 0, timeMinutes: minutes, tags: Array(tags.prefix(5)),
                          ingredients: ingredients, steps: steps, imageURL: image(d["image"]))
        card.sourceDraft = .init(text: (try? JSONSerialization.data(withJSONObject: d)).flatMap { String(data: $0, encoding: .utf8) } ?? name,
            warnings: ["Check the imported source; missing facts are unspecified."], unknownServings: card.servings == 0)
        return card
    }

    static func text(_ v: Any?) -> String? {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        if let d = v as? [String: Any] { return text(d["text"] ?? d["name"] ?? d["@value"]) }
        if let a = v as? [Any] { return a.first.flatMap { text($0) } }
        return nil
    }

    static func instructions(_ v: Any?) -> [String] {
        if let s = v as? String {
            let cleaned = decode(strip(s))
            let parts = cleaned.components(separatedBy: CharacterSet.newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return parts.count > 1 ? parts : (cleaned.isEmpty ? [] : [cleaned])
        }
        if let a = v as? [Any] { return a.flatMap { instructions($0) } }
        if let d = v as? [String: Any] {
            if let items = d["itemListElement"] { return instructions(items) }
            if let t = text(d["text"] ?? d["name"]) { return t.isEmpty ? [] : [decode(strip(t))] }
        }
        return []
    }

    /// ISO 8601 duration (PT1H30M, P0DT45M) → minutes.
    static func duration(_ s: String?) -> Int? {
        guard let s = s?.uppercased(), s.hasPrefix("P") else { return nil }
        var total = 0.0, num = "", inTime = false
        for ch in s.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." { num.append(ch); continue }
            let v = Double(num) ?? 0; num = ""
            switch ch {
            case "D": total += v * 1440
            case "H": total += v * 60
            case "M": total += inTime ? v : v * 43200
            case "S": total += v / 60
            case "W": total += v * 10080
            default: break
            }
        }
        let m = Int(total.rounded())
        return m > 0 ? m : nil
    }

    static func servings(_ v: Any?) -> Int? {
        guard let s = text(v),
              s.range(of: #"^[1-9]\d*(?:\s+(?:servings?|slices?|portions?))?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let first = s.split(whereSeparator: { !$0.isNumber }).first,
              let value = Int(first), value > 0 else { return nil }
        return value
    }

    static func image(_ v: Any?) -> String? {
        if let s = v as? String { return s.hasPrefix("http") ? s : nil }
        if let a = v as? [Any] { return a.lazy.compactMap { image($0) }.first }
        if let d = v as? [String: Any] { return image(d["url"] ?? d["contentUrl"]) }
        return nil
    }

    static func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ s: String) -> String {
        var out = s
        for (a, b) in ["&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&#039;": "'", "&apos;": "'", "&quot;": "\"",
                       "&lt;": "<", "&gt;": ">", "&#8217;": "’", "&#8211;": "–", "&frac12;": "½", "&deg;": "°"] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }
}

/// "1 1/2 cups plain flour, sifted" → Ingredient(name: "plain flour", quantity: 1.5, unit: "cup", notes: "sifted")
enum IngredientParser {
    static let vulgar: [Character: Double] = ["½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75, "⅛": 0.125,
                                              "⅕": 0.2, "⅙": 1.0 / 6, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]
    static let units: [String: String] = [
        "g": "g", "gram": "g", "grams": "g", "gr": "g", "kg": "kg", "kilogram": "kg", "kilograms": "kg",
        "mg": "mg", "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l", "dl": "dl", "cl": "cl",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp", "t": "tsp",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp", "tbl": "tbsp", "T": "tbsp",
        "cup": "cup", "cups": "cup", "oz": "oz", "ounce": "oz", "ounces": "oz", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "clove": "cloves", "cloves": "cloves", "pinch": "pinch", "pinches": "pinch", "can": "can", "cans": "can", "tin": "tin", "tins": "tin",
        "slice": "slice", "slices": "slice", "bunch": "bunch", "bunches": "bunch", "handful": "handful", "sprig": "sprig", "sprigs": "sprig",
        "pc": "pcs", "pcs": "pcs", "piece": "pcs", "pieces": "pcs", "stick": "stick", "sticks": "stick", "dash": "dash",
    ]

    static func parse(_ raw: String) -> Ingredient {
        var s = JSONLD.decode(JSONLD.strip(raw)).trimmingCharacters(in: .whitespaces)
        var notes: [String] = []
        // Parenthetical notes.
        while let r = s.range(of: "\\(([^)]*)\\)", options: .regularExpression) {
            let inner = s[r].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { notes.append(inner) }
            s.removeSubrange(r)
        }
        // Quantity: "1 1/2", "1½", "1.5", "1-2" (takes first), "½".
        var qty = 0.0
        var rest = Substring(s)
        func skipSpaces() { while rest.first == " " { rest = rest.dropFirst() } }
        func number() -> Double? {
            skipSpaces()
            if let c = rest.first, let v = vulgar[c] { rest = rest.dropFirst(); return v }
            var t = ""
            while let c = rest.first, c.isNumber || c == "." || c == "," || c == "/" { t.append(c); rest = rest.dropFirst() }
            if t.isEmpty { return nil }
            var v: Double?
            if t.contains("/") {
                let p = t.split(separator: "/").compactMap { Double($0) }
                v = p.count == 2 && p[1] != 0 ? p[0] / p[1] : nil
            } else { v = Double(t.replacingOccurrences(of: ",", with: ".")) }
            if let c = rest.first, let frac = vulgar[c] { rest = rest.dropFirst(); v = (v ?? 0) + frac }
            return v
        }
        if let a = number() {
            qty = a
            let save = rest
            if let b = number(), b < 1 { qty += b } else { rest = save }
            skipSpaces()
            if rest.first == "-" || rest.first == "–" || rest.lowercased().hasPrefix("to ") {
                rest = rest.drop(while: { $0 == "-" || $0 == "–" || $0 == " " || $0 == "t" || $0 == "o" })
                _ = number()
            }
        }
        skipSpaces()
        // Unit.
        var unit = ""
        if qty > 0 || rest.first?.isLetter == true {
            let word = rest.prefix { $0.isLetter || $0 == "." }
            let key = word.replacingOccurrences(of: ".", with: "")
            if let u = units[key] ?? units[key.lowercased()], qty > 0 || ["pinch", "dash", "handful"].contains(key.lowercased()) {
                unit = u; rest = rest.dropFirst(word.count)
                skipSpaces()
                if rest.lowercased().hasPrefix("of ") { rest = rest.dropFirst(3) }
                if unit == "pinch" || unit == "dash" || unit == "handful", qty == 0 { qty = 1 }
            }
        }
        var name = rest.trimmingCharacters(in: .whitespaces)
        if let comma = name.firstIndex(of: ",") {
            let n = name[name.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { notes.insert(n, at: 0) }
            name = String(name[..<comma]).trimmingCharacters(in: .whitespaces)
        }
        if qty > 0 && unit.isEmpty { unit = "pcs" }
        return Ingredient(name: name.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : name,
                          quantity: RecipeLogic.round2(qty), unit: unit, notes: notes.isEmpty ? nil : notes.joined(separator: "; "))
    }
}

/// Finds a waiting time in a step ("bake for 25 minutes", "simmer 1 hour 10 mins", "rest 30 seconds").
enum StepTimer {
    static func seconds(in s: String) -> Int? { Durations.seconds(in: s) }
}
