import Foundation

/// One row in public.user_recipes (kind = "recipe" | "shopping").
/// Encoding rules (PostgREST is strict): `updated_at` is an integer (bigint column; `123.4` or `123.0` → 22P02),
/// and every object has the same keys (`data` is written as `null`, never omitted → otherwise PGRST102).
struct SyncRecord: Codable, Equatable {
    var user_id: String
    var kind: String            // "recipe" | "shopping"
    var id: String
    var data: AnyJSON?
    var updated_at: Int64       // ms since epoch (bigint column), last-write-wins clock
    var deleted: Bool

    init(user_id: String, kind: String, id: String, data: AnyJSON?, updated_at: Int64, deleted: Bool) {
        self.user_id = user_id; self.kind = kind; self.id = id; self.data = data; self.updated_at = updated_at; self.deleted = deleted
    }
    init(user_id: String, kind: String, id: String, data: AnyJSON?, stampMs: Double, deleted: Bool) {
        self.init(user_id: user_id, kind: kind, id: id, data: data, updated_at: Int64(stampMs.rounded()), deleted: deleted)
    }

    enum CodingKeys: String, CodingKey { case user_id, kind, id, data, updated_at, deleted }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user_id = try c.decode(String.self, forKey: .user_id)
        kind = try c.decode(String.self, forKey: .kind)
        id = try c.decode(String.self, forKey: .id)
        data = try c.decodeIfPresent(AnyJSON.self, forKey: .data)
        if let i = try? c.decode(Int64.self, forKey: .updated_at) { updated_at = i }
        else if let d = try? c.decode(Double.self, forKey: .updated_at) { updated_at = Int64(d.rounded()) }
        else if let s = try? c.decode(String.self, forKey: .updated_at), let i = Int64(s) { updated_at = i }
        else { updated_at = 0 }
        deleted = (try? c.decode(Bool.self, forKey: .deleted)) ?? false
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user_id, forKey: .user_id)
        try c.encode(kind, forKey: .kind)
        try c.encode(id, forKey: .id)
        if let data { try c.encode(data, forKey: .data) } else { try c.encodeNil(forKey: .data) }
        try c.encode(updated_at, forKey: .updated_at)
        try c.encode(deleted, forKey: .deleted)
    }
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
    case tableMissing, unauthorized, http(Int, String?)
    var errorDescription: String? {
        switch self {
        case .tableMissing: return "Cloud sync isn't set up on the server yet (user_recipes table missing)."
        case .unauthorized: return "Your session expired. Sign in again."
        case .http(let c, let detail): return "HTTP \(c)" + (detail.map { " — \($0)" } ?? "")
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
        Net.authorize(&r, key: key, bearer: session.accessToken)
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
        // Surface PostgREST's code + message (e.g. "22P02: invalid input syntax for type bigint").
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let detail = [j?["code"] as? String, j?["message"] as? String].compactMap { $0 }.joined(separator: ": ")
        throw SyncError.http(code, detail.isEmpty ? nil : String(detail.prefix(160)))
    }

    func pull(session: AuthSession) async throws -> [SyncRecord] {
        let r = req([URLQueryItem(name: "select", value: "user_id,kind,id,data,updated_at,deleted"),
                     URLQueryItem(name: "user_id", value: "eq.\(session.userID)")], method: "GET", session: session)
        let (data, resp) = try await Net.data(for: r)
        try check(data, resp)
        return try JSONDecoder().decode([SyncRecord].self, from: data)
    }

    func push(_ records: [SyncRecord], session: AuthSession) async throws {
        guard !records.isEmpty else { return }
        var r = req([URLQueryItem(name: "on_conflict", value: "user_id,kind,id")], method: "POST", session: session,
                    body: try JSONEncoder().encode(records))
        r.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let (data, resp) = try await Net.data(for: r)
        try check(data, resp)
    }
}

/// In-memory server for UI tests.
final class MockSync: SyncService {
    private var rows: [String: SyncRecord] = [:]
    /// With `-qaPersistServer` the "server" is a file that survives relaunches (second-device / second-launch pull).
    private static var file: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("qa-mock-server.json") }
    var pushCount = 0
    init() {
        if AppConfig.qaPersistServer, let d = try? Data(contentsOf: Self.file),
           let r = try? JSONDecoder().decode([String: SyncRecord].self, from: d) { rows = r }
        if ProcessInfo.processInfo.arguments.contains("-qaResetServer") { try? FileManager.default.removeItem(at: Self.file); rows = [:] }
    }
    private var down: Bool { ProcessInfo.processInfo.arguments.contains("-qaBackendDown") }
    func pull(session: AuthSession) async throws -> [SyncRecord] {
        if down { throw SyncError.http(503, "Service unavailable") }
        return Array(rows.values)
    }
    func push(_ records: [SyncRecord], session: AuthSession) async throws {
        if down { throw SyncError.http(503, "Service unavailable") }
        pushCount += 1
        for r in records { rows["\(r.kind)/\(r.id)"] = r }
        if AppConfig.qaPersistServer { try? JSONEncoder().encode(rows).write(to: Self.file) }
    }
}

/// Pure last-write-wins merge, unit-testable.
enum SyncMerge {
    /// Account-switch safety: signing in as a different user than the one this device last synced with
    /// must not merge (or push tombstones of) the previous account's library into the new one.
    static func isAccountSwitch(lastSyncedUser: String?, newUser: String) -> Bool {
        guard let lastSyncedUser else { return false }
        return lastSyncedUser != newUser
    }

    struct Local { var data: [String: Data]; var stamps: [String: Double]; var tombstones: [String: Double] }
    struct Result { var data: [String: Data]; var stamps: [String: Double]; var tombstones: [String: Double]; var push: [String] ; var pushDeletes: [String] }

    static func merge(local: Local, remote: [SyncRecord]) -> Result {
        var data = local.data, stamps = local.stamps, tomb = local.tombstones
        var remoteStamp: [String: Double] = [:]
        for r in remote {
            remoteStamp[r.id] = Double(r.updated_at)
            // Stamps travel as whole ms (bigint); compare rounded so a re-sync is a no-op.
            let localStamp = max(stamps[r.id] ?? -1, tomb[r.id] ?? -1).rounded()
            guard Double(r.updated_at) > localStamp else { continue }
            if r.deleted {
                data[r.id] = nil; stamps[r.id] = nil; tomb[r.id] = Double(r.updated_at)
            } else if let raw = r.data?.raw {
                data[r.id] = raw; stamps[r.id] = Double(r.updated_at); tomb[r.id] = nil
            }
        }
        let push = data.keys.filter { (stamps[$0] ?? 0).rounded() > (remoteStamp[$0] ?? -1) }
        let pushDeletes = tomb.keys.filter { (tomb[$0] ?? 0).rounded() > (remoteStamp[$0] ?? -1) }
        return Result(data: data, stamps: stamps, tombstones: tomb, push: push.sorted(), pushDeletes: pushDeletes.sorted())
    }
}
