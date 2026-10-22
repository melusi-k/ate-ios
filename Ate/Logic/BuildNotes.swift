import Foundation

/// Build-specific notes are generated from the checked-out commit history before XcodeGen runs.
/// The explicit fallback keeps About useful if the build environment has no Git history.
enum BuildNotes {
    static var current: String {
        guard let url = Bundle.main.url(forResource: "BuildNotes", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "Build notes are not available for this build."
        }
        let notes = contents
            .components(separatedBy: .newlines)
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? "Build notes are not available for this build." : notes
    }
}
