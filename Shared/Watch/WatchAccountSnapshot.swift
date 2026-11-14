import Foundation

/// Strict generation/owner proof for watch writes. Never infer a generation from
/// local cache, never default malformed cloud fields, never accept foreign rows.
struct WatchAccountSnapshot {
    enum Failure: Error { case invalidSnapshot }
    let ownerID: String
    let generation: Int64
    let rows: [WatchRow]
    private struct Row: Decodable {
        let user_id: String
        let kind: String
        let id: String
        let data: WatchJSON?
        let updated_at: Int64
        let deleted: Bool
        enum CodingKeys: String, CodingKey { case user_id, kind, id, data, updated_at, deleted }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            user_id = try c.decode(String.self, forKey: .user_id)
            kind = try c.decode(String.self, forKey: .kind)
            id = try c.decode(String.self, forKey: .id)
            guard c.contains(.data) else { throw Failure.invalidSnapshot }
            data = try c.decodeIfPresent(WatchJSON.self, forKey: .data)
            updated_at = try c.decode(Int64.self, forKey: .updated_at)
            deleted = try c.decode(Bool.self, forKey: .deleted)
        }
    }
    private struct DTO: Decodable { let generation: Int64; let rows: [Row] }
    static func decode(_ bytes: Data, ownerID: String) throws -> Self {
        let value = try JSONDecoder().decode(DTO.self, from: bytes)
        guard !ownerID.isEmpty, value.generation >= 0,
              value.rows.allSatisfy({ $0.user_id == ownerID && !$0.id.isEmpty && !$0.kind.isEmpty && $0.updated_at >= 0 }) else { throw Failure.invalidSnapshot }
        return Self(ownerID: ownerID, generation: value.generation, rows: value.rows.map {
            WatchRow(kind: $0.kind, id: $0.id, data: $0.data, updated_at: $0.updated_at, deleted: $0.deleted)
        })
    }
}
