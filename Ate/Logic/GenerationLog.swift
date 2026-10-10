import Foundation

/// Debug record of the most recent AI/parse run (shown in Settings › About).
struct GenerationLog: Codable, Equatable {
    var source: RecipeSource
    var latencyMs: Int
    var mode: String
    var date: Date

    static let key = "ate.lastGeneration.v1"
    static var last: GenerationLog? {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(GenerationLog.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    var summary: String {
        "\(source.badge ?? source.rawValue) · \(mode) · \(latencyMs) ms · \(date.formatted(date: .omitted, time: .shortened))"
    }
}
