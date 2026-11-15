import Foundation

/// One watch session owns every displayed row. Disk cache carries owner proof,
/// but never authorizes a cloud write. Only a fresh snapshot can do that.
struct WatchOwnedContent {
    enum Failure: Error { case staleItem, unavailable }
    private struct Cache: Codable {
        let format: Int
        let ownerID: String
        let recipes: [WatchRecipe]
        let shopping: [WatchShoppingItem]
    }
    struct Toggle {
        let session: WatchBridgePayload.Session
        let generation: Int64
        let revision: UUID
        let row: WatchRow
    }
    private(set) var session: WatchBridgePayload.Session?
    private(set) var recipes: [WatchRecipe] = []
    private(set) var shopping: [WatchShoppingItem] = []
    private(set) var generation: Int64?
    private var revision = UUID()

    init(session: WatchBridgePayload.Session?, cacheURL: URL) {
        self.session = session
        // Ownerless v1 cache, corrupt cache and another owner's bytes are never
        // displayed. Cache cannot restore generation or live-item authority.
        if let owner = session?.userID, !owner.isEmpty,
           let bytes = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: bytes),
           cache.format == 2, cache.ownerID == owner {
            recipes = cache.recipes
            shopping = cache.shopping.map { var item = $0; item.snapshotID = nil; return item }
        }
    }
    mutating func transition(to next: WatchBridgePayload.Session?, cacheURL: URL) throws {
        // Revoke first, even if clearing disk fails. Never leave A's content
        // visible while B's refresh waits or fails. Same-owner token rotation
        // also revokes retained UI items and all pre-refresh write authority.
        recipes = []; shopping = []; generation = nil; revision = UUID()
        let changedOwner = session?.userID != next?.userID
        session = next
        if changedOwner || next == nil { try save(cacheURL: cacheURL) }
    }
    mutating func publish(_ snapshot: WatchAccountSnapshot, session expected: WatchBridgePayload.Session,
                          cacheURL: URL) throws {
        guard session == expected, snapshot.ownerID == expected.userID else { throw Failure.unavailable }
        let rows = WatchRows.decode(snapshot.rows)
        revision = UUID()
        recipes = rows.recipes
        shopping = rows.shopping.map { var item = $0; item.snapshotID = revision; return item }
        generation = snapshot.generation
        try save(cacheURL: cacheURL)
    }
    mutating func prepareToggle(_ retained: WatchShoppingItem, session expected: WatchBridgePayload.Session,
                                nowMs: Int64, cacheURL: URL) throws -> Toggle {
        guard session == expected, let generation,
              retained.snapshotID == revision,
              let index = shopping.firstIndex(where: { $0.id == retained.id }),
              shopping[index] == retained else { throw Failure.staleItem }
        let (changed, row) = WatchRows.toggled(shopping[index], nowMs: nowMs)
        shopping[index] = changed
        // Every edit advances UI provenance. An old closure with identical id,
        // values or server generation can never act on a replacement snapshot.
        revision = UUID()
        shopping = shopping.map { var item = $0; item.snapshotID = revision; return item }
        try save(cacheURL: cacheURL)
        return Toggle(session: expected, generation: generation, revision: revision, row: row)
    }
    func validate(_ capture: Toggle, session expected: WatchBridgePayload.Session?) throws {
        guard session == capture.session, expected == capture.session,
              generation == capture.generation, revision == capture.revision else { throw Failure.staleItem }
    }
    mutating func invalidate(_ capture: Toggle) {
        guard (try? validate(capture, session: session)) != nil else { return }
        generation = nil; revision = UUID()
        shopping = shopping.map { var item = $0; item.snapshotID = nil; return item }
    }
    func save(cacheURL: URL) throws {
        if let owner = session?.userID, !owner.isEmpty {
            let cache = Cache(format: 2, ownerID: owner, recipes: recipes, shopping: shopping)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
    }
}
