import Foundation

/// Cloud sync of the remaining user data families (issue #34): Food Journal entries
/// (meals + reflections), insight lifecycle states, and nutrition goals.
///
/// Recipes and shopping already sync through `SupabaseSync` (kind "recipe" / "shopping").
/// This extends the same per-user `user_recipes` table with new kinds
/// ("journal" / "insight" / "goals") so one RLS surface covers all user data.
///
/// Design and rollout contract: docs/implementation/34_USER_DATA_SYNC.md.
///
/// Rollout: default ON as a product preference; `-qaUserDataSyncOff` or the
/// `AteUserDataSync` Info.plist key ("off") disables it. The preference ships client
/// behavior only - it does not grant production changes. The kind-widening migration
/// stays an unapplied file until the owner explicitly applies it; while the backend
/// predates the new kinds (check-constraint violation 23514) or the generation-fenced RPC
/// contract is not deployed, the affected family degrades to local-only for that round:
/// the round is skipped, nothing is written or deleted, and recipe/shopping sync, Library
/// and Cook are never touched.
enum UserDataFamily: String, CaseIterable, Codable {
    case journal, insight, goals
    /// The `user_recipes.kind` value on the wire.
    var kind: String { rawValue }
}

/// The whole-family outcome of one sync round, for status presentation.
enum UserDataSyncStatus: Equatable {
    case synced
    /// Local-only this round. The string is diagnostic detail, not user copy.
    case unavailable(String)
}

// MARK: - Wire payloads

/// Full-fidelity Codable mirror of a SwiftData `JournalEntry` row plus its optional
/// one-to-one `JournalMealPayload`. Dates travel as whole milliseconds since 1970 so the
/// LWW stamp is byte-stable across devices. Media BYTES are out of scope (phase 1):
/// `mediaFileNames` syncs so a restore knows what the entry referenced, but the files
/// themselves stay on the device that captured them.
struct JournalEntrySyncPayload: Codable, Equatable {
    var id: String
    var createdAtMs: Int64
    var prompt: String
    var text: String
    var stateRaw: String
    var recipeIDs: [String]
    var journalingSuggestionTitle: String?
    var momentDateMs: Int64?
    var sourceRaw: String
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var mediaFileNames: [String]
    var editedAtMs: Int64?
    var kindRaw: String
    var dayKey: String?
    var recipeSnapshotsRaw: String?
    /// Present iff kindRaw == JournalEntryKind.meal.rawValue.
    var meal: JournalMealSyncPayload?

    /// The last-write-wins stamp: an edit moves it, an untouched entry keeps its creation time.
    var stampMs: Int64 { editedAtMs ?? createdAtMs }
}

/// Flat mirror of `JournalMealPayload` (see FoodJournalModels.swift). A nil nutrient means
/// unknown and is never replaced with an estimate - same contract as `NutritionSnapshot`.
struct JournalMealSyncPayload: Codable, Equatable {
    var mealRaw: String
    var foodName: String
    var quantity: Double
    var quantityUnit: String
    var servings: Double
    var sourceRaw: String
    var sourceName: String
    var sourceIdentifier: String
    var verificationNote: String
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?
}

/// Insight lifecycle syncs as the existing `InsightLifecycleRecord` verbatim
/// (status + evidence fingerprint + timestamps). Insight ids are stable candidate ids;
/// the fingerprint already captures "this exact evidence version", so LWW on updatedAt
/// is correct per id.
/// Nutrition goals sync as the existing `DailyNutritionGoals` verbatim under one row id.
enum UserDataSyncID {
    static let goals = "current"
}

// MARK: - Pure planning (unit-tested, no I/O)

struct UserDataSyncPlan {
    /// The merged final data map (local + remote winners), keyed by record id.
    var data: [String: Data]
    /// Payload bytes to write locally, keyed by record id (remote won LWW).
    var applyUpserts: [String: Data]
    /// Ids to delete locally (remote tombstone won LWW).
    var applyDeletes: [String]
    /// Rows to write remotely (local won LWW, or local tombstone to propagate).
    var push: [SyncRecord]
    /// The stamp/tombstone maps to persist after apply+push succeed.
    var stamps: [String: Double]
    var tombstones: [String: Double]
}

enum UserDataSyncPlanner {
    /// Locally deleted = an id this device synced before (present in persisted stamps) whose
    /// entry is gone from the live export. It becomes a tombstone stamped now, so the delete
    /// propagates instead of the entry resurrecting on the next pull. Ids already tombstoned
    /// keep their original stamp (a re-delete is not a newer fact).
    static func localWithDeletes(data: [String: Data], stamps: [String: Double],
                                 tombstones: [String: Double], previouslySynced: [String: Double],
                                 now: Double) -> SyncMerge.Local {
        var stamps = stamps, tombstones = tombstones
        for id in previouslySynced.keys where data[id] == nil && tombstones[id] == nil {
            tombstones[id] = now
            stamps[id] = nil
        }
        return SyncMerge.Local(data: data, stamps: stamps, tombstones: tombstones)
    }

    /// Thin typed wrapper over `SyncMerge.merge` (the recipe/shopping engine): same
    /// last-write-wins semantics, same whole-millisecond comparison, plus the local
    /// apply-set the stores need.
    static func plan(kind: String, userID: String, local: SyncMerge.Local, remote: [SyncRecord]) -> UserDataSyncPlan {
        let r = SyncMerge.merge(local: local, remote: remote)
        let applyUpserts = r.data.filter { local.data[$0.key] != $0.value }
        let applyDeletes = local.data.keys.filter { r.data[$0] == nil }.sorted()
        func rec(_ id: String, _ data: Data?, _ stamp: Double, _ del: Bool) -> SyncRecord {
            SyncRecord(user_id: userID, kind: kind, id: id, data: data.map { AnyJSON($0) }, stampMs: stamp, deleted: del)
        }
        var push: [SyncRecord] = []
        push += r.push.map { rec($0, r.data[$0], r.stamps[$0] ?? 0, false) }
        push += r.pushDeletes.map { rec($0, nil, r.tombstones[$0] ?? 0, true) }
        return UserDataSyncPlan(data: r.data, applyUpserts: applyUpserts, applyDeletes: applyDeletes,
                                push: push, stamps: r.stamps, tombstones: r.tombstones)
    }
}

// MARK: - Per-record sync state (privacy copy)

/// The account + generation a successful family commit confirmed against. Confirmation is
/// a historical fact keyed to this scope: "THAT account's server holds this version".
struct AccountDataScope: Equatable, Codable {
    var ownerID: String
    var generation: Int64
}

/// Per-record cloud state for Journal privacy copy. The aggregate round status never
/// speaks for a single record: a record is `confirmed` only when the server holds its
/// current version, `pending` while its current version exists only on this iPhone and
/// sync can carry it, `cloudCopyOnly` when the account's server holds a version of it
/// (the CURRENT version when `currentVersion` is true, an EARLIER one when false) but
/// sync currently cannot run (off, signed out, unbound graph, backend refusing), and
/// `localOnly` when no version of this record was ever confirmed and none can upload now.
enum JournalRecordSyncState: Equatable {
    case localOnly, pending, confirmed
    case cloudCopyOnly(currentVersion: Bool)
}

// MARK: - Remote snapshot validation

/// Strict identity and structural validation of every family row in a snapshot BEFORE any
/// local write or upload. The planner keys merged rows by wire id while decoders trust
/// payload ids, and SwiftData apply writes whatever decodes - so an inconsistent or
/// malformed remote row must reject the whole round, never partially apply.
enum RemoteSnapshotValidator {
    /// Throws `UserDataSyncError.remoteRejected` on the first violation.
    static func validate(rows: [SyncRecord]) throws {
        var seen: Set<String> = []
        for row in rows {
            // Rows of other kinds (recipe/shopping) belong to their own transport.
            guard let family = UserDataFamily(rawValue: row.kind) else { continue }
            guard !row.id.isEmpty else { throw reject(row.kind, row.id, "empty wire id") }
            guard seen.insert("\(row.kind)/\(row.id)").inserted else {
                throw reject(row.kind, row.id, "duplicate wire id")
            }
            guard row.updated_at >= 0 else { throw reject(row.kind, row.id, "negative LWW stamp") }
            // Tombstones carry no payload; identity + stamp checks above are sufficient.
            guard !row.deleted else { continue }
            guard let bytes = row.data?.raw else {
                throw reject(row.kind, row.id, "live row without a payload")
            }
            switch family {
            case .journal: try validateJournal(id: row.id, stamp: row.updated_at, bytes: bytes)
            case .insight: try validateInsight(id: row.id, stamp: row.updated_at, bytes: bytes)
            case .goals: try validateGoals(id: row.id, bytes: bytes)
            }
        }
    }

    private static func reject(_ kind: String, _ id: String, _ detail: String) -> UserDataSyncError {
        .remoteRejected("\(kind)/\(id.isEmpty ? "<empty>" : id): \(detail)")
    }

    private static func validateJournal(id: String, stamp: Int64, bytes: Data) throws {
        guard let p = try? JSONDecoder().decode(JournalEntrySyncPayload.self, from: bytes) else {
            throw reject("journal", id, "undecodable payload")
        }
        // Strict identity: the payload's id must equal the wire id the planner keys by.
        guard p.id == id else { throw reject("journal", id, "payload id does not match wire id") }
        // Stamp agreement: the LWW clock on the row must be the payload's own version stamp.
        guard stamp == p.stampMs else { throw reject("journal", id, "wire stamp disagrees with payload version") }
        guard let kind = JournalEntryKind(rawValue: p.kindRaw) else {
            throw reject("journal", id, "unknown entry kind")
        }
        switch kind {
        case .meal:
            guard p.meal != nil else { throw reject("journal", id, "meal entry without a meal payload") }
            // Meals are grouped by their local calendar day (#245); a meal without a valid
            // day key cannot be placed on the diary.
            guard let day = p.dayKey, NutritionDiaryDayKey.date(for: day) != nil else {
                throw reject("journal", id, "meal entry without a valid day key")
            }
        case .reflection:
            guard p.meal == nil else { throw reject("journal", id, "reflection carrying a meal payload") }
            if let day = p.dayKey, NutritionDiaryDayKey.date(for: day) == nil {
                throw reject("journal", id, "malformed day key")
            }
        }
        // Empty stateRaw means "no Health reading recorded"; anything else must be known.
        guard p.stateRaw.isEmpty || HealthState(rawValue: p.stateRaw) != nil else {
            throw reject("journal", id, "unknown health state")
        }
        guard JournalEntrySource(rawValue: p.sourceRaw) != nil else {
            throw reject("journal", id, "unknown entry source")
        }
        guard p.createdAtMs > 0 else { throw reject("journal", id, "non-positive creation stamp") }
        if let edited = p.editedAtMs, edited < p.createdAtMs {
            throw reject("journal", id, "edit stamp precedes creation stamp")
        }
        if let lat = p.latitude, !(lat.isFinite && abs(lat) <= 90) {
            throw reject("journal", id, "invalid latitude")
        }
        if let lon = p.longitude, !(lon.isFinite && abs(lon) <= 180) {
            throw reject("journal", id, "invalid longitude")
        }
        // Media file names become sandbox paths on restore; refuse traversal up front.
        guard p.mediaFileNames.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") }) else {
            throw reject("journal", id, "unsafe media file name")
        }
        if let m = p.meal {
            guard NutritionMeal(rawValue: m.mealRaw) != nil else {
                throw reject("journal", id, "unknown meal slot")
            }
            guard NutritionEntrySource(rawValue: m.sourceRaw) != nil else {
                throw reject("journal", id, "unknown nutrient source")
            }
            guard m.quantity.isFinite, m.quantity > 0 else {
                throw reject("journal", id, "invalid quantity")
            }
            guard m.servings.isFinite, m.servings > 0 else {
                throw reject("journal", id, "invalid servings")
            }
            for value in [m.energyKcal, m.proteinGrams, m.carbohydratesGrams, m.fatGrams, m.fibreGrams] {
                if let value, !(value.isFinite && value >= 0) {
                    throw reject("journal", id, "invalid nutrient value")
                }
            }
        }
    }

    private static func validateInsight(id: String, stamp: Int64, bytes: Data) throws {
        // The status enum is enforced by Codable: an unknown status fails the decode.
        guard let r = try? JSONDecoder().decode(InsightLifecycleRecord.self, from: bytes) else {
            throw reject("insight", id, "undecodable payload")
        }
        guard r.updatedAt.timeIntervalSince1970.isFinite, r.updatedAt.timeIntervalSince1970 > 0 else {
            throw reject("insight", id, "invalid update time")
        }
        // Stamp agreement: the LWW clock on the row must be the record's own updatedAt.
        guard stamp == Int64((r.updatedAt.timeIntervalSince1970 * 1000).rounded()) else {
            throw reject("insight", id, "wire stamp disagrees with payload version")
        }
        if let snoozed = r.snoozedUntil, !snoozed.timeIntervalSince1970.isFinite {
            throw reject("insight", id, "invalid snooze time")
        }
    }

    private static func validateGoals(id: String, bytes: Data) throws {
        guard id == UserDataSyncID.goals else { throw reject("goals", id, "unexpected goals row id") }
        guard let g = try? JSONDecoder().decode(DailyNutritionGoals.self, from: bytes) else {
            throw reject("goals", id, "undecodable payload")
        }
        for value in [g.energyKcal, g.proteinGrams, g.carbohydratesGrams, g.fatGrams, g.fibreGrams] {
            if let value, !(value.isFinite && value >= 0) {
                throw reject("goals", id, "invalid goal value")
            }
        }
    }
}

/// Whole-cycle exclusion shared by EVERY account-data sync transport (the recipe/shopping
/// cycle and the issue #34 family cycle). `GenerationFencedSync` captures are stateless -
/// snapshot/push carry their authorization with them - so two transports sharing one fenced
/// instance still interleave unless cycle exclusion lives here, at the common owner.
///
/// Semantics: at most one active cycle. `acquire` refuses while another cycle holds the
/// gate (transports keep their existing operation-in-progress behavior; the next scheduled
/// sync retries). `replace` is the abandoned-cycle recovery for two-call transports whose
/// earlier push never ran: it invalidates the orphaned cycle, whose later validate fails
/// as superseded instead of writing under a stale capture.
@MainActor
final class SyncCycleGate {
    enum Failure: Error, Equatable { case cycleInProgress, superseded }
    struct CycleToken: Equatable { fileprivate let id: UUID }
    private var holder: UUID?

    func acquire() throws -> CycleToken {
        guard holder == nil else { throw Failure.cycleInProgress }
        let id = UUID()
        holder = id
        return CycleToken(id: id)
    }

    func replace() -> CycleToken {
        let id = UUID()
        holder = id
        return CycleToken(id: id)
    }

    func validate(_ token: CycleToken) throws {
        guard holder == token.id else { throw Failure.superseded }
    }

    func release(_ token: CycleToken) {
        if holder == token.id { holder = nil }
    }
}

/// Design constraint: family sync writes ONLY through the fenced unified graph.
/// One cycle = one consistent snapshot plus pushes authorized by exactly that snapshot,
/// run inside the shared `SyncCycleGate` so family work never interleaves with the
/// recipe/shopping cycle. The push closure is single-use; `revalidate` re-proves the gate,
/// session and generation so a caller can stage local changes, upload, re-prove, and only
/// then publish locally. There is deliberately NO unfenced production transport (that
/// form was removed after the Builder review).
@MainActor
protocol UserDataSyncTransport {
    /// The account + generation this transport would confirm against right now: the live
    /// session's account and its persisted generation receipt. Nil when there is no session
    /// or no receipt - confirmation then falls back to the persisted commit scope's owner.
    var currentScope: AccountDataScope? { get }
    func cycle<R>(session: AuthSession,
                  work: (AccountSnapshot,
                         _ push: ([SyncRecord]) async throws -> Void,
                         _ revalidate: () throws -> Void) async throws -> R) async throws -> R
}

/// The production transport: `GenerationFencedSync` plus the persisted generation receipt,
/// serialized against the recipe/shopping cycle by the injected gate. Mirrors
/// `FoodJournalGenerationSync`'s require semantics (#532 sync-core; central may unify the
/// two when that lands): one pull capture authorizes its exact push, single-use even on
/// failure, and a stale caller never writes under a generation it did not read.
@MainActor
final class FencedUserDataSyncTransport: UserDataSyncTransport {
    enum Failure: Error {
        case identityChanged, reconciliationRequired, pushAlreadyConsumed
    }

    private let fenced: GenerationFencedSync
    private let receipts: AccountGenerationReceiptStore
    private let currentSession: () -> AuthSession?
    private let validate: () throws -> Void
    private let gate: SyncCycleGate

    var currentScope: AccountDataScope? {
        guard let session = currentSession(),
              let receipt = try? receipts.read(), receipt.ownerID == session.userID else { return nil }
        return AccountDataScope(ownerID: session.userID, generation: receipt.generation)
    }

    init(fenced: GenerationFencedSync, receipts: AccountGenerationReceiptStore,
         currentSession: @escaping () -> AuthSession?, validate: @escaping () throws -> Void,
         gate: SyncCycleGate) {
        self.fenced = fenced; self.receipts = receipts
        self.currentSession = currentSession; self.validate = validate
        self.gate = gate
    }

    /// Single-use authorization for the batch push of one cycle.
    private final class BatchAuthorization {
        private var capture: GenerationFencedSync.Capture?
        init(capture: GenerationFencedSync.Capture) { self.capture = capture }
        func consume() -> GenerationFencedSync.Capture? { let c = capture; capture = nil; return c }
    }

    private func require(_ session: AuthSession, capture: GenerationFencedSync.Capture) throws {
        try validate()
        guard currentSession() == session, capture.ownerID == session.userID else { throw Failure.identityChanged }
        guard let receipt = try receipts.read(),
              receipt.ownerID == capture.ownerID, receipt.generation == capture.generation else {
            throw Failure.reconciliationRequired
        }
    }

    func cycle<R>(session: AuthSession,
                  work: (AccountSnapshot,
                         _ push: ([SyncRecord]) async throws -> Void,
                         _ revalidate: () throws -> Void) async throws -> R) async throws -> R {
        let token = try gate.acquire()
        defer { gate.release(token) }
        try validate()
        guard currentSession() == session else { throw Failure.identityChanged }
        let snap = try await fenced.snapshot()
        try Task.checkCancellation()
        try gate.validate(token)
        try require(session, capture: snap.capture)
        let snapshot = AccountSnapshot(generation: snap.capture.generation, rows: snap.rows)
        let authorization = BatchAuthorization(capture: snap.capture)
        let push: ([SyncRecord]) async throws -> Void = { records in
            // Single use even on failure. Next attempt must snapshot/reconcile again.
            guard let capture = authorization.consume() else { throw Failure.pushAlreadyConsumed }
            try self.gate.validate(token)
            try self.require(session, capture: capture)
            try await self.fenced.push(records, capture: capture)
            try Task.checkCancellation()
            try self.gate.validate(token)
            try self.require(session, capture: capture)
        }
        // Re-prove the cycle still owns the gate, session and generation. Staged callers
        // run this after the authorized upload and before ANY local publication, so a
        // reset or account change mid-cycle leaves local content untouched.
        let revalidate: () throws -> Void = {
            try self.gate.validate(token)
            try self.require(session, capture: snap.capture)
        }
        return try await work(snapshot, push, revalidate)
    }
}

/// Maps a transport failure to the family outcome. A backend that predates issue #34
/// rejects the new kinds two ways: the widened CHECK constraint is missing (23514) or the
/// RPC contract is absent entirely (`contractMissing`). Both mean "local-only this round",
/// never a hard sync failure. A stale generation means account data was cleared elsewhere:
/// the round aborts and the next sync re-snapshots instead of writing under an old epoch.
enum UserDataSyncError: LocalizedError, Equatable {
    /// Backend not migrated yet (23514 / contract missing). Safe to retry every round.
    case familyUnavailable(String)
    /// Account was cleared elsewhere mid-round; discard the plan, re-snapshot next round.
    case generationChanged
    /// A remote row failed strict identity/structural validation. The round is rejected
    /// wholesale: nothing is applied locally and nothing is uploaded from a snapshot this
    /// build cannot trust.
    case remoteRejected(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .familyUnavailable(let d): return "Cloud sync for this data isn't set up on the server yet (\(d))."
        case .generationChanged: return "Account data changed on the server during sync."
        case .remoteRejected(let d): return "The server returned data this app version cannot read (\(d)); nothing was changed on this iPhone."
        case .transport(let d): return d
        }
    }

    static func classify(_ error: Error) -> UserDataSyncError {
        if let e = error as? UserDataSyncError { return e }
        if let e = error as? GenerationFencedSync.Error {
            switch e {
            case .ownerChanged: return .generationChanged
            case .invalidGeneration, .mismatchedRowOwner, .duplicateIdentity:
                return .transport("fenced sync rejected the round")
            }
        }
        if let e = error as? SyncCycleGate.Failure {
            switch e {
            case .cycleInProgress: return .transport("another account-data sync cycle is active")
            case .superseded: return .transport("sync cycle was superseded by a newer cycle")
            }
        }
        if let e = error as? FencedUserDataSyncTransport.Failure {
            switch e {
            case .identityChanged, .reconciliationRequired: return .generationChanged
            case .pushAlreadyConsumed: return .transport("push already consumed for this snapshot")
            }
        }
        guard let e = error as? ResetRPCError else { return .transport(error.localizedDescription) }
        switch e {
        case .contractMissing:
            return .familyUnavailable("sync contract not deployed")
        case .staleGeneration:
            return .generationChanged
        case .unauthorized:
            return .transport(ResetRPCError.unauthorized.errorDescription ?? "")
        case .invalidRequest(let d):
            return .transport("invalid request: \(d)")
        case .outcomeUnverified(let d):
            return .transport("unverified: \(d)")
        case .http(let code, let detail):
            if let detail, detail.contains("23514") {
                return .familyUnavailable("server does not accept this data kind yet (23514)")
            }
            return .transport("HTTP \(code)\(detail.map { ": \($0)" } ?? "")")
        }
    }
}
