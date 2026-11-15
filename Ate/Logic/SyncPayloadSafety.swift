import Foundation

/// A narrow preflight for existing unversioned sync rows, not a new wire schema.
/// Pause the entire receipt before merge if any row cannot safely become a domain
/// value. Domain import's permissive defaults must not invent cloud identities.
enum SyncPayloadSafety {
    struct Incompatible: LocalizedError, Equatable {
        let count: Int
        var errorDescription: String? {
            "Sync paused: \(count) incompatible server row(s). Your local data is unchanged."
        }
    }
    static func validate(_ rows: [SyncRecord], owner: String) throws {
        let failures = rows.filter { !isCompatible($0, owner: owner) }.count
        if failures > 0 { throw Incompatible(count: failures) }
    }
    private static func isCompatible(_ row: SyncRecord, owner: String) -> Bool {
        guard row.user_id == owner, !row.id.isEmpty, row.updated_at >= 0,
              row.kind == "recipe" || row.kind == "shopping" else { return false }
        if row.deleted { return true }
        guard let raw = row.data?.raw,
              let fields = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              fields["id"] as? String == row.id else { return false }
        // No schema version is emitted today. Additive fields remain compatible;
        // an explicit version requires a future adapter, never a guess here.
        guard fields["schemaVersion"] == nil, fields["schema_version"] == nil else { return false }
        let decoder = JSONDecoder()
        if row.kind == "shopping" {
            guard let item = try? decoder.decode(ShoppingItem.self, from: raw) else { return false }
            return !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.quantity.isFinite && item.quantity > 0
        }
        guard let title = fields["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // RecipeCard is intentionally lenient for imports. Check its core typed
        // fields separately so malformed arrays/numbers cannot silently vanish.
        struct Core: Decodable {
            let servings: Double?
            let timeMinutes: Double?
            let ingredients: [Ingredient]?
            let steps: [Step]?
        }
        guard let core = try? decoder.decode(Core.self, from: raw) else { return false }
        for number in [core.servings, core.timeMinutes].compactMap({ $0 }) {
            guard number.isFinite, number > 0, number < Double(Int.max) else { return false }
        }
        guard (try? decoder.decode(RecipeCard.self, from: raw)) != nil else { return false }
        return true
    }
}
