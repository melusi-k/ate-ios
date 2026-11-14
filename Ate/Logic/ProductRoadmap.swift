import Foundation

/// Reviewed bundled community copy, never a raw issue feed or a promise of dates.
struct ProductRoadmapCatalog: Codable {
    let schemaVersion: Int
    let features: [ProductRoadmapFeature]
    enum Failure: Error { case invalid }
    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        func meaningful(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard catalog.schemaVersion == 1,
              Set(catalog.features.map(\.id)).count == catalog.features.count,
              catalog.features.allSatisfy({ meaningful($0.id) && meaningful($0.title) && meaningful($0.benefit) &&
                  $0.id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) } }) else {
            throw Failure.invalid
        }
        return catalog
    }
    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "roadmap", withExtension: "json", subdirectory: "ProductUpdates"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}
struct ProductRoadmapFeature: Codable, Identifiable {
    enum Status: String, Codable, CaseIterable {
        case considering, planned, building, released
        var title: String { rawValue.capitalized }
    }
    let id: String
    let title: String
    let benefit: String
    let status: Status
}

/// No backend or anonymous authentication is enabled. No local vote is accepted,
/// counted or queued until that separate service is approved and implemented.
enum ProductRoadmapVoting {
    static let available = false
    static let explanation = "Voting isn't available yet. No vote has been sent or saved."
    static let limits = "When voting opens, it's one vote per feature on this install, not per person. Reinstalling Ate or using another device can reset that limit."
}
