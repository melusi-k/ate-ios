import Foundation

enum ShoppingLogic {
    static let massBase: [String: Double] = ["g": 1, "kg": 1000, "oz": 28.3495, "lb": 453.592]
    static let volumeBase: [String: Double] = ["ml": 1, "l": 1000, "tsp": 4.92892, "tbsp": 14.7868, "cup": 240, "fl oz": 29.5735]
    static let countUnits: Set<String> = ["", "pcs", "pc", "piece", "pieces", "x", "whole"]

    static func family(_ unit: String) -> String {
        let u = Units.canonical(unit)
        if massBase[u] != nil { return "mass" }
        if volumeBase[u] != nil { return "volume" }
        if countUnits.contains(u) { return "count" }
        return "unit:" + u
    }

    static func singular(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if n.hasSuffix("ies") && n.count > 4 { n = String(n.dropLast(3)) + "y" }
        else if n.hasSuffix("oes") || n.hasSuffix("shes") || n.hasSuffix("ches") { n = String(n.dropLast(2)) }
        else if n.hasSuffix("s") && !n.hasSuffix("ss") && n.count > 3 { n = String(n.dropLast()) }
        return n
    }

    static let aisleRules: [(Aisle, String)] = [
        (.frozen, "frozen|ice cream|peas frozen"),
        (.meatFish, "chicken|beef|pork|lamb|mince|bacon|sausage|salmon|tuna|cod|fish|prawn|shrimp|turkey|ham|steak"),
        (.dairy, "milk|cheese|butter|yogh?urt|cream|egg|parmesan|mozzarella|feta|ricotta"),
        (.bakery, "bread|bun|roll|bagel|tortilla|pita|croissant|baguette|naan"),
        (.produce, "onion|garlic|tomato|potato|carrot|lettuce|spinach|pepper|chilli|chili|lemon|lime|apple|banana|herb|basil|parsley|coriander|cilantro|ginger|mushroom|cucumber|avocado|zucchini|courgette|broccoli|cabbage|celery|scallion|leek|kale|berry|fruit|mint|thyme|rosemary"),
        (.pantry, "flour|sugar|salt|oil|vinegar|rice|pasta|noodle|sauce|stock|broth|spice|cumin|paprika|bean|lentil|can|tin|honey|soy|miso|oat|nut|seed|baking"),
    ]

    static func guessAisle(_ name: String) -> Aisle {
        let n = name.lowercased()
        for (aisle, pattern) in aisleRules where n.range(of: "\\b(\(pattern))", options: .regularExpression) != nil { return aisle }
        return .other
    }

    static func merge(_ ingredients: [Ingredient], source: String?, into list: [ShoppingItem]) -> [ShoppingItem] {
        var items = list
        for ing in ingredients {
            let key = singular(ing.name)
            if let idx = items.firstIndex(where: { !$0.done && singular($0.name) == key && family($0.unit) == family(ing.unit) }) {
                var it = items[idx]
                let a = Units.canonical(it.unit), b = Units.canonical(ing.unit)
                if a == b || family(a) == "count" {
                    it.quantity = RecipeLogic.round2(it.quantity + ing.quantity)
                } else {
                    let fam = family(a)
                    let table = fam == "mass" ? massBase : volumeBase
                    let total = it.quantity * (table[a] ?? 1) + ing.quantity * (table[b] ?? 1)
                    if total >= 1000 { it.quantity = RecipeLogic.round2(total / 1000); it.unit = fam == "mass" ? "kg" : "l" }
                    else { it.quantity = RecipeLogic.round2(total); it.unit = fam == "mass" ? "g" : "ml" }
                }
                if ing.name.count > it.name.count { it.name = ing.name }
                if let s = source {
                    var srcs = it.sources ?? (it.from.map { [$0] } ?? [])
                    if !srcs.contains(s) { srcs.append(s) }
                    it.sources = srcs
                }
                if let n = ing.notes, !n.isEmpty {
                    it.notes = [it.notes, n].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
                }
                items[idx] = it
            } else {
                items.append(ShoppingItem(name: ing.name, quantity: ing.quantity, unit: ing.unit, from: source,
                                          sources: source.map { [$0] }, notes: ing.notes, aisle: guessAisle(ing.name)))
            }
        }
        return items
    }

    /// Store-walk order for grouping the list.
    static let aisleOrder: [Aisle] = [.produce, .bakery, .meatFish, .dairy, .pantry, .frozen, .other]

    /// Pending items grouped by aisle (stable item order within a group, empty aisles dropped).
    static func grouped(_ items: [ShoppingItem]) -> [(aisle: Aisle, items: [ShoppingItem])] {
        let by = Dictionary(grouping: items) { $0.aisle ?? guessAisle($0.name) }
        return aisleOrder.compactMap { a in by[a].map { (a, $0) } }
    }

    static func label(_ it: ShoppingItem) -> String {
        [Units.formatAmount(it.quantity, it.unit), it.name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func exportText(_ items: [ShoppingItem]) -> String {
        var lines = ["ate — shopping list", ""]
        for it in items {
            var l = (it.done ? "[x] " : "[ ] ") + label(it)
            if let n = it.notes, !n.isEmpty { l += " (\(n))" }
            lines.append(l)
        }
        return lines.joined(separator: "\n")
    }

    static func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    static func exportCSV(_ items: [ShoppingItem]) -> String {
        var lines = ["item,quantity,unit,notes,aisle,recipe,done"]
        for it in items {
            let recipe = (it.sources ?? (it.from.map { [$0] } ?? [])).joined(separator: "; ")
            lines.append([q(it.name), Units.formatQuantity(it.quantity), q(it.unit), q(it.notes ?? ""),
                          q((it.aisle ?? guessAisle(it.name)).rawValue), q(recipe), it.done ? "true" : "false"].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
