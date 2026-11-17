import Foundation
import Observation

struct RoadmapCatalog: Decodable {
    let schemaVersion: Int
    let cards: [RoadmapCard]
    enum CatalogError: Error { case invalid }

    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        func hasText(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard catalog.schemaVersion == 1,
              Set(catalog.cards.map(\.id)).count == catalog.cards.count,
              catalog.cards.allSatisfy({ card in
                  !card.id.isEmpty && card.id.utf8.allSatisfy { byte in
                      (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
                  } && hasText(card.title) && hasText(card.summary) && hasText(card.detail)
              }) else { throw CatalogError.invalid }
        return catalog
    }

    static func load(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "roadmap", withExtension: "json", subdirectory: "ProductUpdates"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}

struct RoadmapCard: Decodable, Identifiable {
    enum Status: String, Decodable { case considering, planned, building, released }
    let id: String
    let title: String
    let summary: String
    let detail: String
    let status: Status
    var statusLabel: String { status.rawValue.capitalized }
}

/// One local preference per card per installation. Never sent or treated as community votes.
@MainActor @Observable
final class RoadmapVotes {
    static let storageKey = "ate.roadmap.local-votes.v1"
    private let defaults: UserDefaults
    private(set) var selected: Set<String> = []
    private(set) var error: String?
    private let allowedIDs: Set<String>

    init(cards: [RoadmapCard], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        allowedIDs = Set(cards.map(\.id))
        guard let existing = defaults.object(forKey: Self.storageKey) else { return }
        guard let data = existing as? Data,
              let stored = try? JSONDecoder().decode([String].self, from: data) else {
            error = "Your saved local preferences could not be read. Voting is unavailable; existing data has not been changed."
            return
        }
        // Preserve unknown IDs for catalog changes; only current cards can be toggled.
        selected = Set(stored)
    }

    func contains(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        guard error == nil, allowedIDs.contains(id) else { return }
        var updated = selected
        if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        do {
            let data = try JSONEncoder().encode(updated.sorted())
            defaults.set(data, forKey: Self.storageKey)
            guard defaults.data(forKey: Self.storageKey) == data else {
                error = "Your preference could not be saved on this iPhone. No saved vote is confirmed."
                return
            }
            selected = updated
        } catch {
            self.error = "Your preference could not be saved on this iPhone. No saved vote is confirmed."
        }
    }
}
