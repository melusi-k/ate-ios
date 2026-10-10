import Foundation

enum Units {
    static let aliases: [String: String] = [
        "g": "g", "gram": "g", "grams": "g", "gr": "g", "grm": "g",
        "kg": "kg", "kgs": "kg", "kilogram": "kg", "kilograms": "kg", "kilo": "kg", "kilos": "kg",
        "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l", "lt": "l",
        "oz": "oz", "ounce": "oz", "ounces": "oz",
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "fl oz": "fl oz", "floz": "fl oz", "fl. oz": "fl oz", "fluid ounce": "fl oz", "fluid ounces": "fl oz",
        "cup": "cup", "cups": "cup", "c": "cup",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp", "tsps": "tsp",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsps": "tbsp", "tbs": "tbsp",
    ]

    static func canonical(_ unit: String) -> String {
        let u = unit.trimmingCharacters(in: .whitespaces).lowercased()
        return aliases[u] ?? u
    }

    static func niceRound(_ v: Double) -> Double {
        if v >= 100 { return (v / 5).rounded() * 5 }
        if v >= 10 { return v.rounded() }
        if v >= 1 { return (v * 4).rounded() / 4 }
        return (v * 100).rounded() / 100
    }

    static func convert(quantity q: Double, unit: String, to system: UnitSystem) -> (Double, String) {
        let u = canonical(unit)
        guard q > 0 else { return (q, unit) }
        switch system {
        case .imperial:
            switch u {
            case "g":
                let oz = q / 28.3495
                return oz >= 16 ? (niceRound(oz / 16), "lb") : (niceRound(oz), "oz")
            case "kg": return (niceRound(q * 2.20462), "lb")
            case "ml", "l":
                let ml = u == "l" ? q * 1000 : q
                return ml >= 240 ? (niceRound(ml / 240), "cup") : (niceRound(ml / 29.5735), "fl oz")
            default: return (q, unit)
            }
        case .metric:
            switch u {
            case "oz", "lb":
                let g = u == "oz" ? q * 28.3495 : q * 453.592
                return g >= 1000 ? (niceRound(g / 1000), "kg") : (niceRound(g), "g")
            case "fl oz": return (niceRound(q * 29.5735), "ml")
            case "cup": return (niceRound(q * 240), "ml")
            default: return (q, unit)
            }
        }
    }

    static func convertTemperatures(in text: String, to system: UnitSystem) -> String {
        guard let re = try? NSRegularExpression(pattern: "(\\d{2,3})\\s*(°|º|degrees)\\s*([CF])\\b", options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let v = Double(ns.substring(with: m.range(at: 1))) else { continue }
            let scale = ns.substring(with: m.range(at: 3)).uppercased()
            var rep: String?
            if scale == "C" && system == .imperial { rep = "\(Int(((v * 9 / 5 + 32) / 5).rounded() * 5))°F" }
            if scale == "F" && system == .metric { rep = "\(Int((((v - 32) * 5 / 9) / 5).rounded() * 5))°C" }
            if let rep, let r = Range(m.range, in: out) { out.replaceSubrange(r, with: rep) }
        }
        return out
    }

    static let hidden: Set<String> = ["pcs", "pc", "x", "whole", "unit", "units", "item", "items"]
    static let pluralisable: Set<String> = ["clove", "piece", "can", "slice", "cup", "pinch", "bunch", "sprig", "stick",
        "handful", "head", "tin", "packet", "jar", "fillet", "stalk", "knob", "dash", "bottle", "bag", "sheet", "wedge"]

    static func formatUnit(_ unit: String, quantity: Double) -> String {
        let u = unit.trimmingCharacters(in: .whitespaces)
        let l = u.lowercased()
        if hidden.contains(l) { return "" }
        let plural = quantity > 1 || quantity == 0
        if l == "leaf" { return plural ? "leaves" : "leaf" }
        if pluralisable.contains(l) && plural {
            return ["pinch", "bunch", "dash"].contains(l) ? l + "es" : l + "s"
        }
        return u
    }

    static func formatQuantity(_ q: Double) -> String {
        if q == 0 { return "" }
        if q == q.rounded() { return String(Int(q)) }
        var s = String(format: "%.2f", q)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func formatAmount(_ q: Double, _ unit: String) -> String {
        [formatQuantity(q), formatUnit(unit, quantity: q)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Finds durations like "10 minutes", "1 hr 15 min", "8-10 mins" (upper bound). Returns seconds.
    static func findDurations(in text: String) -> [Int] {
        let pattern = "(?:(\\d+)\\s*(?:-|–|to)\\s*)?(\\d+)\\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\\b(?:\\s*(\\d+)\\s*(minutes?|mins?|m)\\b)?"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let v = Int(ns.substring(with: m.range(at: 2))) else { return nil }
            let unit = ns.substring(with: m.range(at: 3)).lowercased()
            var secs: Int
            if unit.hasPrefix("h") { secs = v * 3600 } else if unit.hasPrefix("m") { secs = v * 60 } else { secs = v }
            if m.range(at: 4).location != NSNotFound, let extra = Int(ns.substring(with: m.range(at: 4))) { secs += extra * 60 }
            return secs
        }
    }
}
