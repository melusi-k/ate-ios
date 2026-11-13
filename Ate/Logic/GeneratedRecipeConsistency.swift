import Foundation

/// Bounded, deterministic gaps for the generated-card repair loop. Never changes
/// imported/user recipes or fabricates quantities to make a check pass.
enum GeneratedRecipeConsistency {
    static func contains(_ text: String, _ words: [String]) -> Bool {
        words.contains { CoverLogic.matches(text.lowercased(), $0) }
    }

    /// One explicit nonnegative prep statement, shared by normalization and the
    /// validator. Ambiguous/multiple statements are not permission to guess.
    static func prepMinutes(in note: String) -> Int? {
        let text = note as NSString
        guard let declarations = try? NSRegularExpression(pattern: #"\bprep\s*:"#, options: .caseInsensitive),
              let value = try? NSRegularExpression(
                pattern: #"^\s*(\d+)\s*min\s*(?:$|[.!](?=\s|$)(?!\s*(?:plus|and)\b)|[\r\n])"#,
                options: .caseInsensitive) else { return nil }
        // Count ALL declarations, not only well-formed values. A valid value
        // alongside a malformed second declaration is still ambiguous.
        let matches = declarations.matches(in: note, range: NSRange(location: 0, length: text.length))
        guard matches.count == 1, let declaration = matches.first else { return nil }
        let tail = text.substring(from: NSMaxRange(declaration.range)) as NSString
        guard let match = value.firstMatch(in: tail as String, range: NSRange(location: 0, length: tail.length)) else { return nil }
        guard let minutes = Int(tail.substring(with: match.range(at: 1))),
              (0...Durations.maxTotalMinutes).contains(minutes) else { return nil }
        return minutes
    }

    /// Bound both operands before arithmetic. Invalid text and an excessive
    /// combined total remain a quality gap, never an integer trap or silent cap.
    static func totalMinutes(stepMinutes: Int, prepMinutes: Int) -> Int? {
        guard (0...Durations.maxTotalMinutes).contains(stepMinutes),
              prepMinutes >= 0, prepMinutes <= Durations.maxTotalMinutes - stepMinutes else { return nil }
        return stepMinutes + prepMinutes
    }

    static func issues(_ card: RecipeCard) -> [String] {
        guard RecipeQuality.isGenerated(card) else { return [] }
        var gaps: [String] = []
        let ingredients = card.ingredients.filter { $0.quantity.isFinite && $0.quantity > 0 }
            .map(\.name).joined(separator: " ").lowercased()
        let steps = RecipeLogic.nonBlank(card.steps).map(\.instruction).joined(separator: " ").lowercased()
        // Deliberately limited vocabulary, not an unreliable general food-name parser.
        // A source has already supplied its facts; these checks apply only to generated cards.
        let staples: [(String, [String])] = [
            ("salt", ["salt", "salted"]), ("oil", ["oil"]), ("water", ["water"])
        ]
        for (name, uses) in staples where contains(steps, uses) && !contains(ingredients, [name]) {
            gaps.append("Steps use \(name), but no measured \(name) ingredient is listed.")
        }
        if contains(card.title, ["bunny chow", "bunny-chow"]) {
            if !contains(ingredients, ["bread", "loaf", "loaves"]) {
                gaps.append("Bunny chow needs measured bread portions for the curry-filled hollowed loaf.")
            }
            if !contains(steps, ["hollow", "hollowed", "hollowing"]) ||
                !contains(steps, ["fill", "filled", "filling", "spoon", "ladle"]) {
                gaps.append("Bunny chow needs a step to hollow the bread and fill it with curry.")
            }
        }
        var seconds = 0
        let maxSeconds = Durations.maxTotalMinutes * 60
        for duration in RecipeLogic.nonBlank(card.steps).compactMap(\.timeSeconds) where duration > 0 {
            guard duration <= maxSeconds - seconds else {
                gaps.append("Step time sum exceeds the supported total; clarify cooking times.")
                return gaps
            }
            seconds += duration
        }
        let note = card.aiNote ?? ""
        let prep = prepMinutes(in: note)
        let hasPrep = note.range(of: #"\bprep\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil
        // Missing total must not make an invalid/overflowing Prep declaration
        // vanish from the quality path after sanitizer correctly refused it.
        if hasPrep && prep == nil {
            gaps.append("Clarify one explicit Prep: N min value before total time can be verified.")
            return gaps
        }
        if seconds > 0, let total = card.timeMinutes {
            let stepMinutes = (seconds + 59) / 60
            if let prep {
                guard let expected = totalMinutes(stepMinutes: stepMinutes, prepMinutes: prep) else {
                    gaps.append("Total time plus stated prep exceeds the supported limit; clarify cooking times.")
                    return gaps
                }
                if total != expected { gaps.append("Total time must equal the step sum plus stated prep minutes.") }
            } else if total < stepMinutes {
                gaps.append("Total time must equal the step sum plus stated prep minutes.")
            } else if total > stepMinutes {
                gaps.append("Explain the extra \(total - stepMinutes) minutes as Prep: N min in the note; total time is steps plus prep.")
            }
        }
        return gaps
    }
}
