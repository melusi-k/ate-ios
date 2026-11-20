import Foundation

/// Lossless paste evidence only. Not an AI claim or a general recipe parser.
/// The snapshot scopes normalization/display exceptions to an unchanged import.
struct PastedRecipeSource: Codable, Hashable {
    var text: String
    var title: String
    var servings: Int
    var ingredients: [Ingredient]
    var steps: [Step]
    var ingredientLines: [String]
    var writtenTime: String?
    var importNote: String

    func matches(_ card: RecipeCard) -> Bool {
        guard card.source == .imported && card.title == title && card.servings == servings
            && card.ingredients == ingredients && card.steps == steps && card.timeMinutes == nil
            && card.description == nil && card.tags.isEmpty && card.cuisine == nil && card.aiNote == importNote
        else { return false }
        // Decoded metadata is not authority. Rebuild from the verified raw source,
        // then compare every protected field, including visible raw row text.
        guard case .verified(let contract) = SourceRecipeFidelity.extraction(text),
              let rebuilt = try? VerifiedPasteImport.card(from: text, contract: contract)
        else { return false }
        return rebuilt.pastedSource == self
    }
}

/// Lossless fast conversion for a verified numbered source. Other layouts use
/// the editable source-draft path instead. Servings may remain unspecified.
enum VerifiedPasteImport {
    static let unsupported = BackendError(message: "Ate couldn't safely import the complete pasted recipe. No demo recipe was substituted. Nothing was generated or saved. Keep the full title, explicit Serves, Ingredients and numbered Method, or enter it manually.")

    static func card(from raw: String, contract: SourceRecipeFidelity.Contract) throws -> RecipeCard {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: #"[ \t\x{00A0}\x{202F}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func key(_ s: String) -> String { clean(s).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": ")) }
        let lines = raw.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
        let ingredientMarkers = lines.indices.filter { key(lines[$0]) == "ingredients" }
        let methodMarkers = lines.indices.filter { ["method", "directions", "instructions"].contains(key(lines[$0])) }
        guard raw.count <= 6000, ingredientMarkers.count == 1, methodMarkers.count == 1,
              let i = ingredientMarkers.first, let m = methodMarkers.first, i > 0, m > i + 1,
              lines[0].count <= 160, !lines[0].contains("://") else { throw unsupported }
        let header = Array(lines[..<i])
        let servings = SourceDraftImport.servings(raw) ?? 0
        // Keep written total/range as text. Never turn 40-60 into an exact total.
        let timeMarkers = header.indices.filter { key(header[$0]) == "cooking time" }
        guard timeMarkers.count <= 1 else { throw unsupported }
        var writtenTime: String?
        if let ti = timeMarkers.first {
            guard ti + 1 < header.count,
                  header[ti + 1].range(of: #"^\d+(?:\s*[-–]\s*\d+)?\s+(?:minutes?|hours?)$"#, options: [.regularExpression, .caseInsensitive]) != nil else { throw unsupported }
            writtenTime = header[ti + 1]
        }
        var rowLines: [String] = [], prefix: [String] = []
        var cursor = 0
        for line in lines[(i + 1)..<m] {
            // The existing contract drops only explicit section markers. Retain
            // their text attached to the next review row, never discard it.
            if line.hasSuffix(":") && line.range(of: #"\d"#, options: .regularExpression) == nil
                || key(line).hasPrefix("for ") || key(line).hasPrefix("to ") {
                prefix.append(line); continue
            }
            guard cursor < contract.ingredients.count else { throw unsupported }
            let expected = contract.ingredients[cursor]
            var parsed = IngredientParser.parse(line)
            if let lead = line.range(of: #"^a (?:pinch|handful|dash|splash) of "#, options: [.regularExpression, .caseInsensitive]) {
                parsed = Ingredient(name: String(line[lead.upperBound...]), quantity: 0, unit: "", notes: nil)
            }
            guard parsed == expected else { throw unsupported }
            rowLines.append((prefix + [line]).joined(separator: "\n")); prefix = []; cursor += 1
        }
        guard prefix.isEmpty, cursor == contract.ingredients.count, cursor >= 2 else { throw unsupported }
        var instructions: [String] = [], pendingHeading: String?, number = 0
        let numbered = try NSRegularExpression(pattern: #"^(\d+)(?:[.)]\s+|\s+)(.+)$"#)
        for line in lines[(m + 1)...] {
            let ns = line as NSString
            if let match = numbered.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard let n = Int(ns.substring(with: match.range(at: 1))), n == number + 1 else { throw unsupported }
                let instruction = ns.substring(with: match.range(at: 2))
                guard let last = instruction.last, ".!?".contains(last) else { throw unsupported }
                instructions.append([pendingHeading, instruction].compactMap { $0 }.joined(separator: "\n"))
                pendingHeading = nil; number = n
            } else {
                // A heading may reset source numbering, but never masquerade as
                // prose, an unnumbered instruction or a truncated numeric marker.
                guard pendingHeading == nil,
                      line.range(of: #"^[A-Z][A-Za-z '&-]{0,60}:?$"#, options: .regularExpression) != nil,
                      line.split(separator: " ").count <= 5 else { throw unsupported }
                pendingHeading = line; number = 0
            }
        }
        guard pendingHeading == nil, !instructions.isEmpty, instructions.count <= 60 else { throw unsupported }
        let steps = instructions.enumerated().map { Step(order: $0.offset + 1, instruction: $0.element, timeSeconds: nil) }
        var card = RecipeCard(title: lines[0], servings: servings, ingredients: contract.ingredients, steps: steps, source: .imported)
        card.sourceDraft = .init(text: raw, warnings: ["Check the imported source before saving. Missing facts remain unspecified."], unknownServings: servings == 0)
        card.aiNote = "Imported directly from verified pasted source. Component headings are kept as unmeasured rows. No AI recipe was generated; unknown times remain unknown."
        card.pastedSource = PastedRecipeSource(text: raw, title: card.title, servings: servings,
            ingredients: card.ingredients, steps: steps, ingredientLines: rowLines, writtenTime: writtenTime, importNote: card.aiNote ?? "")
        // The contract must still accept every ingredient and written method time.
        guard contract.issues(card).isEmpty else { throw unsupported }
        return card
    }
}
