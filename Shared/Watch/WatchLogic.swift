import Foundation

// Pure, platform-neutral logic shared by the iPhone app (Ate), the watch app (AteWatch) and its widget.
// Foundation only, so it compiles for iOS and watchOS and is unit-tested in AteTests.

/// Minimal recipe shape the watch needs, decoded from a user_recipes row's `data` jsonb.
struct WatchRecipe: Codable, Identifiable, Hashable {
    struct Item: Codable, Hashable { var name: String; var quantity: Double?; var unit: String? }
    struct Step: Codable, Hashable { var order: Int?; var instruction: String; var timeSeconds: Int? }
    var id: String
    var title: String
    var timeMinutes: Int?
    var ingredients: [Item]
    var steps: [Step]
    var updatedAt: Int64 = 0

    var ingredientLines: [String] { ingredients.map { WatchFormat.ingredient($0) } }
}

struct WatchShoppingItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var quantity: Double?
    var unit: String?
    var done: Bool
    var updatedAt: Int64 = 0
    /// Original jsonb so a tick-off round-trips every field the phone wrote.
    var raw: [String: WatchJSON] = [:]
}

/// Tiny JSON value for round-tripping the phone's jsonb rows without the full iOS model.
indirect enum WatchJSON: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: WatchJSON]), array([WatchJSON]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([WatchJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: WatchJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var object: [String: WatchJSON]? { if case .object(let o) = self { return o }; return nil }
    var array: [WatchJSON]? { if case .array(let a) = self { return a }; return nil }
}

/// A user_recipes row as returned by PostgREST.
struct WatchRow: Codable {
    var kind: String
    var id: String
    var data: WatchJSON?
    var updated_at: Int64
    var deleted: Bool
    enum CodingKeys: String, CodingKey { case kind, id, data, updated_at, deleted }
    init(kind: String, id: String, data: WatchJSON?, updated_at: Int64, deleted: Bool) {
        self.kind = kind; self.id = id; self.data = data; self.updated_at = updated_at; self.deleted = deleted
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        id = try c.decode(String.self, forKey: .id)
        data = try c.decodeIfPresent(WatchJSON.self, forKey: .data)
        if let i = try? c.decode(Int64.self, forKey: .updated_at) { updated_at = i }
        else if let d = try? c.decode(Double.self, forKey: .updated_at) { updated_at = Int64(d) }
        else { updated_at = 0 }
        deleted = (try? c.decode(Bool.self, forKey: .deleted)) ?? false
    }
}

enum WatchRows {
    /// Rows → recipes + shopping items. Tombstones are dropped; the newest row per id wins.
    static func decode(_ rows: [WatchRow]) -> (recipes: [WatchRecipe], shopping: [WatchShoppingItem]) {
        var latest: [String: WatchRow] = [:]
        for r in rows { let k = r.kind + "/" + r.id; if (latest[k]?.updated_at ?? .min) <= r.updated_at { latest[k] = r } }
        var recipes: [WatchRecipe] = [], shopping: [WatchShoppingItem] = []
        for r in latest.values where !r.deleted {
            guard let o = r.data?.object else { continue }
            if r.kind == "recipe" {
                let ings = (o["ingredients"]?.array ?? []).compactMap { $0.object }.map {
                    WatchRecipe.Item(name: $0["name"]?.string ?? "", quantity: $0["quantity"]?.double, unit: $0["unit"]?.string)
                }
                let steps = (o["steps"]?.array ?? []).compactMap { $0.object }.map {
                    WatchRecipe.Step(order: $0["order"]?.double.map(Int.init), instruction: $0["instruction"]?.string ?? "",
                                     timeSeconds: $0["timeSeconds"]?.double.map(Int.init))
                }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
                recipes.append(WatchRecipe(id: r.id, title: o["title"]?.string ?? "Untitled recipe",
                                           timeMinutes: o["timeMinutes"]?.double.map(Int.init),
                                           ingredients: ings, steps: steps, updatedAt: r.updated_at))
            } else if r.kind == "shopping" {
                shopping.append(WatchShoppingItem(id: r.id, name: o["name"]?.string ?? "", quantity: o["quantity"]?.double,
                                                  unit: o["unit"]?.string, done: o["done"]?.bool ?? false,
                                                  updatedAt: r.updated_at, raw: o))
            }
        }
        recipes.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        shopping.sort { ($0.done ? 1 : 0, $0.name.lowercased()) < ($1.done ? 1 : 0, $1.name.lowercased()) }
        return (recipes, shopping)
    }

    /// A tick-off as an upsert row (LWW: stamp strictly newer than what we saw).
    static func toggled(_ item: WatchShoppingItem, nowMs: Int64) -> (item: WatchShoppingItem, row: WatchRow) {
        var i = item
        i.done.toggle()
        i.updatedAt = max(nowMs, item.updatedAt + 1)
        var raw = item.raw
        raw["id"] = .string(i.id); raw["name"] = .string(i.name); raw["done"] = .bool(i.done)
        if raw["quantity"] == nil { raw["quantity"] = .number(i.quantity ?? 1) }
        if raw["unit"] == nil { raw["unit"] = .string(i.unit ?? "") }
        i.raw = raw
        return (i, WatchRow(kind: "shopping", id: i.id, data: .object(raw), updated_at: i.updatedAt, deleted: false))
    }
}

enum WatchFormat {
    static func quantity(_ q: Double) -> String {
        if q == q.rounded() { return String(Int(q)) }
        let fracs: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾"), (1.0 / 3, "⅓"), (2.0 / 3, "⅔")]
        let whole = Int(q), f = q - Double(whole)
        if let m = fracs.first(where: { abs($0.0 - f) < 0.02 }) { return (whole > 0 ? "\(whole)" : "") + m.1 }
        return String(format: "%.1f", q)
    }
    static func ingredient(_ i: WatchRecipe.Item) -> String {
        var parts: [String] = []
        if let q = i.quantity, q > 0 { parts.append(quantity(q)) }
        if let u = i.unit, !u.isEmpty { parts.append(u) }
        parts.append(i.name)
        return parts.joined(separator: " ")
    }
    static func mmss(_ s: Int) -> String { String(format: "%d:%02d", max(0, s) / 60, max(0, s) % 60) }
}

/// Step navigation for wrist cook mode (buttons + Digital Crown).
struct CookStepper: Equatable {
    var index: Int = 0
    let count: Int
    var canGoBack: Bool { index > 0 }
    var canGoNext: Bool { index < count - 1 }
    var isLast: Bool { index >= count - 1 }
    mutating func next() { if canGoNext { index += 1 } }
    mutating func back() { if canGoBack { index -= 1 } }
    /// Crown value (continuous) → clamped step index.
    static func index(forCrown value: Double, count: Int) -> Int { max(0, min(count - 1, Int(value.rounded()))) }
    var progressLabel: String { count == 0 ? "" : "Step \(index + 1) of \(count)" }
}

/// One wrist step timer; endDate-based so it survives suspension.
struct WatchStepTimer: Codable, Equatable {
    var recipeTitle: String
    var stepIndex: Int
    var total: Int
    var endDate: Date?          // nil = paused
    var pausedRemaining: Int

    static func start(title: String, step: Int, seconds: Int, now: Date = Date()) -> WatchStepTimer {
        WatchStepTimer(recipeTitle: title, stepIndex: step, total: seconds, endDate: now.addingTimeInterval(TimeInterval(seconds)), pausedRemaining: seconds)
    }
    func remaining(at now: Date = Date()) -> Int {
        if let e = endDate { return max(0, Int(ceil(e.timeIntervalSince(now)))) }
        return pausedRemaining
    }
    func isFinished(at now: Date = Date()) -> Bool { endDate != nil && remaining(at: now) == 0 }
    mutating func pause(at now: Date = Date()) { pausedRemaining = remaining(at: now); endDate = nil }
    mutating func resume(at now: Date = Date()) { if endDate == nil { endDate = now.addingTimeInterval(TimeInterval(pausedRemaining)) } }
    var progress: Double { total == 0 ? 0 : 1 - Double(remaining()) / Double(total) }
}

/// Messages over WatchConnectivity (application context / messages are [String: Any]; we send one JSON blob).
struct WatchBridgePayload: Codable, Equatable {
    struct Session: Codable, Equatable { var accessToken: String; var refreshToken: String; var expiresAt: Double; var userID: String; var email: String }
    struct CookMirror: Codable, Equatable {
        var recipeID: String; var recipeTitle: String; var stepIndex: Int; var stepCount: Int; var stepText: String
        var timerEnd: Date?; var timerRemaining: Int?
    }
    var session: Session?
    var signedOut: Bool = false
    var cook: [CookMirror] = []
    var sentAt: Date = Date()

    static let key = "ate.bridge.v1"
    func dictionary() -> [String: Any] { [Self.key: (try? JSONEncoder().encode(self)) ?? Data()] }
    static func from(_ dict: [String: Any]) -> WatchBridgePayload? {
        guard let d = dict[key] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchBridgePayload.self, from: d)
    }
}

/// Supabase email-OTP sign-in for the watch (type the 6-digit code from the email; no browser on the wrist).
enum WatchAuthRequests {
    static func otp(base: URL, email: String) -> (URL, [String: Any]) {
        (base.appendingPathComponent("auth/v1/otp"), ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "create_user": false])
    }
    static func verify(base: URL, email: String, code: String) -> (URL, [String: Any]) {
        (base.appendingPathComponent("auth/v1/verify"),
         ["type": "email", "email": email.trimmingCharacters(in: .whitespaces).lowercased(), "token": code.filter(\.isNumber)])
    }
    static func refreshURL(base: URL) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        return c.url!
    }
    static func rowsURL(base: URL) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/user_recipes"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "select", value: "kind,id,data,updated_at,deleted")]
        return c.url!
    }
    static func isValidCode(_ s: String) -> Bool { let d = s.filter(\.isNumber); return d.count >= 6 && d.count <= 8 }
    static func isPlausibleEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces); return t.contains("@") && t.split(separator: "@").last?.contains(".") == true
    }
    static func needsRefresh(expiresAt: Double, now: Date = Date()) -> Bool { expiresAt - now.timeIntervalSince1970 < 120 }
}

/// Shared between the watch app and its Smart Stack widget via the App Group (falls back to standard defaults).
enum WatchTimerStore {
    static let groupID = "group.com.melusik.ate"
    static let key = "ate.watch.timer.v1"
    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }
    static func save(_ t: WatchStepTimer?) {
        defaults.set(t.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
    static func load() -> WatchStepTimer? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchStepTimer.self, from: $0) }
    }
}
