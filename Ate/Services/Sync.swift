import Foundation

/// One row in public.user_recipes (kind = "recipe" | "shopping").
struct SyncRecord: Codable, Equatable {
    var user_id: String
    var kind: String
    var id: String
    var data: AnyJSON?
    var updated_at: Double      // ms since epoch (bigint column) — simple last-write-wins clock
    var deleted: Bool
}

/// Opaque JSON value so we can round-trip `data jsonb` without re-modelling it.
struct AnyJSON: Codable, Equatable {
    let raw: Data
    init(_ raw: Data) { self.raw = raw }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let v = try c.decode(JSONValue.self)
        raw = try JSONEncoder().encode(v)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(try JSONDecoder().decode(JSONValue.self, from: raw))
    }
}

indirect enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

enum SyncError: LocalizedError {
    case tableMissing, unauthorized, http(Int)
    var errorDescription: String? {
        switch self {
        case .tableMissing: return "Cloud sync isn't set up on the server yet (user_recipes table missing)."
        case .unauthorized: return "Your session expired. Sign in again."
        case .http(let c): return "Sync failed (HTTP \(c))."
        }
    }
}

protocol SyncService {
    func pull(session: AuthSession) async throws -> [SyncRecord]
    func push(_ records: [SyncRecord], session: AuthSession) async throws
}

final class SupabaseSync: SyncService {
    let baseURL: URL
    let key: String
    init(baseURL: URL, key: String) { self.baseURL = baseURL; self.key = key }

    private func req(_ query: [URLQueryItem], method: String, session: AuthSession, body: Data? = nil) -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent("rest/v1/user_recipes"), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    private func check(_ data: Data, _ resp: URLResponse) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code) { return }
        let text = String(decoding: data, as: UTF8.self)
        if code == 404 || text.contains("PGRST205") || text.contains("42P01") { throw SyncError.tableMissing }
        if code == 401 || code == 403 { throw SyncError.unauthorized }
        throw SyncError.http(code)
    }

    func pull(session: AuthSession) async throws -> [SyncRecord] {
        let r = req([URLQueryItem(name: "select", value: "user_id,kind,id,data,updated_at,deleted"),
                     URLQueryItem(name: "user_id", value: "eq.\(session.userID)")], method: "GET", session: session)
        let (data, resp) = try await URLSession.shared.data(for: r)
        try check(data, resp)
        return try JSONDecoder().decode([SyncRecord].self, from: data)
    }

    func push(_ records: [SyncRecord], session: AuthSession) async throws {
        guard !records.isEmpty else { return }
        var r = req([URLQueryItem(name: "on_conflict", value: "user_id,kind,id")], method: "POST", session: session,
                    body: try JSONEncoder().encode(records))
        r.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let (data, resp) = try await URLSession.shared.data(for: r)
        try check(data, resp)
    }
}

/// In-memory server for UI tests.
final class MockSync: SyncService {
    private var rows: [String: SyncRecord] = [:]
    func pull(session: AuthSession) async throws -> [SyncRecord] { Array(rows.values) }
    func push(_ records: [SyncRecord], session: AuthSession) async throws {
        for r in records { rows["\(r.kind)/\(r.id)"] = r }
    }
}

/// Pure last-write-wins merge, unit-testable.
enum SyncMerge {
    struct Local { var data: [String: Data]; var stamps: [String: Double]; var tombstones: [String: Double] }
    struct Result { var data: [String: Data]; var stamps: [String: Double]; var tombstones: [String: Double]; var push: [String] ; var pushDeletes: [String] }

    static func merge(local: Local, remote: [SyncRecord]) -> Result {
        var data = local.data, stamps = local.stamps, tomb = local.tombstones
        var remoteStamp: [String: Double] = [:]
        for r in remote {
            remoteStamp[r.id] = r.updated_at
            let localStamp = max(stamps[r.id] ?? -1, tomb[r.id] ?? -1)
            guard r.updated_at > localStamp else { continue }
            if r.deleted {
                data[r.id] = nil; stamps[r.id] = nil; tomb[r.id] = r.updated_at
            } else if let raw = r.data?.raw {
                data[r.id] = raw; stamps[r.id] = r.updated_at; tomb[r.id] = nil
            }
        }
        let push = data.keys.filter { (stamps[$0] ?? 0) > (remoteStamp[$0] ?? -1) }
        let pushDeletes = tomb.keys.filter { (tomb[$0] ?? 0) > (remoteStamp[$0] ?? -1) }
        return Result(data: data, stamps: stamps, tombstones: tomb, push: push.sorted(), pushDeletes: pushDeletes.sorted())
    }
}
