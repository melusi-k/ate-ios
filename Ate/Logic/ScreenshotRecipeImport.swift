import Foundation

/// Bounded OCR structuring, not model reconstruction or an OCR-accuracy claim.
/// Explicit section boundaries and numbered method are required. Unsupported
/// pages fail closed instead of sending source facts through creative generation.
enum ScreenshotRecipeImport {
    static let unsupported = BackendError(message: "Ate couldn't safely separate this screenshot's ingredients and method. No recipe was generated. Try a clearer crop with title, servings, Ingredients and numbered Method, or enter it manually.")

    static func card(from text: String) throws -> RecipeCard {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func heading(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        }
        guard let ingredientIndex = lines.firstIndex(where: { heading($0) == "ingredients" }),
              let methodIndex = lines.firstIndex(where: { ["method", "directions", "instructions"].contains(heading($0)) }),
              ingredientIndex > 0, methodIndex > ingredientIndex + 1,
              let title = lines.first, !title.contains("://"), title.count <= 120 else { throw unsupported }
        let header = Array(lines[..<ingredientIndex])
        let declarations = header.indices.filter {
            header[$0].range(of: #"^serves\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard declarations.count == 1, let declaration = declarations.first else { throw unsupported }
        var value = header[declaration].replacingOccurrences(of: #"^serves\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix(":") { value.removeFirst(); value = value.trimmingCharacters(in: .whitespaces) }
        var valueLine = declaration
        if value.isEmpty {
            valueLine += 1
            guard valueLine < header.count else { throw unsupported }
            value = header[valueLine]
        }
        // Parse the WHOLE value, never a prefix of a range/fraction/composite.
        guard value.range(of: #"^\d+$"#, options: .regularExpression) != nil,
              let servings = Int(value), (1...100).contains(servings) else { throw unsupported }
        if valueLine + 1 < header.count,
           header[valueLine + 1].range(of: #"^(?:\d|[-/]|to\b|plus\b|and\b)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            throw unsupported
        }
        var ingredientLines: [String] = []
        var sawWebControls = false
        let controls = ["convert your measurements", "view full conversion table"]
        for line in lines[(ingredientIndex + 1)..<methodIndex] {
            if controls.contains(heading(line)) { sawWebControls = true; continue }
            guard !sawWebControls else { throw unsupported }
            if line.range(of: #"^\d+(?:[.,]\d+)?\s+"#, options: .regularExpression) != nil {
                ingredientLines.append(line)
            } else {
                // Only wrapping within a known measured ingredient is supported.
                guard !ingredientLines.isEmpty,
                      line.range(of: #"^\d|https?://|\b(?:share|download|nutrition|reviews)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { throw unsupported }
                ingredientLines[ingredientLines.count - 1] += " " + line
            }
        }
        guard ingredientLines.count >= 2 else { throw unsupported }
        let ingredients = ingredientLines.map { IngredientParser.parse($0.replacingOccurrences(of: "(s)", with: "s")) }
        let leadingNumber = try NSRegularExpression(pattern: #"^(\d+(?:[.,]\d+)?)\s+"#)
        let exactAmounts = zip(ingredientLines, ingredients).allSatisfy { line, ingredient in
            let ns = line as NSString
            guard let match = leadingNumber.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let amount = Double(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return false }
            return amount.isFinite && amount > 0 && amount == ingredient.quantity
        }
        guard exactAmounts, ingredients.allSatisfy({ $0.quantity.isFinite && $0.quantity > 0 && !$0.name.isEmpty }),
              Set(ingredients.map { $0.name.lowercased() }).count == ingredients.count else { throw unsupported }
        let tail = Array(lines[(methodIndex + 1)...])
        let noteIndex = tail.firstIndex { ["hints & tips", "hints and tips", "tips", "variations", "notes"].contains(heading($0)) } ?? tail.count
        var instructions: [String] = []
        let numbered = try NSRegularExpression(pattern: #"^(\d+)[.)]\s+(.+)$"#)
        for line in tail[..<noteIndex] {
            let ns = line as NSString
            if let match = numbered.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard Int(ns.substring(with: match.range(at: 1))) == instructions.count + 1 else { throw unsupported }
                instructions.append(ns.substring(with: match.range(at: 2)))
            } else {
                // A split/partial numeric marker is NOT prose continuation.
                // Refuse rather than silently merge the final step into step3.
                guard line.range(of: #"^\d+(?:[.)](?:\s|$)|\s*$)"#, options: .regularExpression) == nil,
                      !instructions.isEmpty else { throw unsupported }
                instructions[instructions.count - 1] += " " + line
            }
        }
        guard !instructions.isEmpty else { throw unsupported }
        var card = RecipeCard(title: title, servings: servings, ingredients: ingredients,
            steps: instructions.enumerated().map { .init(order: $0.offset + 1, instruction: $0.element, timeSeconds: nil) },
            source: .imported)
        // Keep tips OUTSIDE the method, without inferring time, prep or nutrition.
        var notes = ["Imported from detected screenshot text. Check OCR wording and quantities against the original; no AI recipe was generated."]
        if noteIndex < tail.count { notes.append(tail[noteIndex...].joined(separator: "\n")) }
        card.aiNote = notes.joined(separator: "\n\n")
        return card
    }
}
