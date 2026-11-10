import Foundation
import Darwin
import CryptoKit

/// Non-destructive existing-install reconciliation for unified Journal activation
/// (#245, slice B). Central calls reconcile() from ResetAwareStartup's async
/// authorizeAdmission phase: after captureAdmission, before final validation and
/// buildGraph. reconcile() NEVER holds the writer flock across an await: local reads
/// and the snapshot RPC run unfenced; everything they decided is re-checked after the
/// await; only the final preservation+stamp runs inside the injected short gate effect.
/// The synchronous authorizeLocalState callback remains strict receipt/control
/// validation only.
///
/// A wipe is NEVER automatic here. Blocked outcomes throw
/// JournalStartupAuthorizationError.blocked (central type) with a stable reason; central
/// mounts the visible recovery screen. On every blocked path this type has mutated
/// nothing except, where stated, a verified preservation copy.
///
/// ASSUMPTION (flagged for review, per central 2026-11-09): the server generation is a
/// RESET COUNTER - clear_account_data is the only operation that bumps it;
/// put_user_recipe fences by caller generation but never increments - and no shipped
/// client has ever had the reset contract. Adoption therefore treats
/// "no receipt + generation 0" as "no reset has ever committed for this account".
/// A MISSING reset contract does NOT establish the server epoch (central 2026-11-10):
/// signed-in startup with an unverifiable snapshot - including contractMissing - is
/// blocked with zero mutation, never treated as generation 0. Signed-out adoption
/// never consults the server and is unchanged.
@MainActor
struct JournalInstallReconciliation {
    /// Successful authorization outcomes. Blocked outcomes throw instead.
    enum Decision: Equatable {
        /// Receipt matches the current identity and (online) the remote generation.
        case proceed
        /// First-launch receipt stamped for the local or signed-in identity at
        /// generation 0, after verified preservation of legacy bytes.
        case adoptedExistingInstall
        /// A local-identity receipt transferred to the signed-in account, same
        /// generation (normal first sign-in after a signed-out adoption).
        case adoptedAccountOwnership
    }

    /// Exact-bytes preservation evidence captured BEFORE a receipt is stamped. Copies
    /// are personal data: JournalLocalReset erases this directory in every wipe.
    struct PreservationManifest: Codable, Equatable {
        struct Item: Codable, Equatable {
            let name: String
            let sha256: String
            let bytes: Data
        }
        var items: [Item]
    }

    static let preservationFileName = "adoption-preservation-v1.json"

    private let receiptStore: AccountGenerationReceiptStore
    private let control: ResetControlPersistence
    private let preservationDirectory: URL
    private let legacyDiary: NutritionDiaryRepository
    private let goals: NutritionGoalsRepository
    private let snapshot: (AuthSession) async throws -> AccountSnapshot
    private let currentSession: () -> AuthSession?
    private let localIdentity: String
    /// Short composed writer effect (e.g. from JournalWriterBoundaryComposition) used
    /// ONLY for the final preservation+stamp. No await ever happens inside it.
    private let stampEffect: (() throws -> Void) throws -> Void

    init(receiptStore: AccountGenerationReceiptStore,
         control: ResetControlPersistence,
         preservationDirectory: URL,
         legacyDiary: NutritionDiaryRepository,
         goals: NutritionGoalsRepository,
         snapshot: @escaping (AuthSession) async throws -> AccountSnapshot,
         currentSession: @escaping () -> AuthSession?,
         localIdentity: String,
         stampEffect: @escaping (() throws -> Void) throws -> Void) {
        self.receiptStore = receiptStore
        self.control = control
        self.preservationDirectory = preservationDirectory
        self.legacyDiary = legacyDiary
        self.goals = goals
        self.snapshot = snapshot
        self.currentSession = currentSession
        self.localIdentity = localIdentity
        self.stampEffect = stampEffect
    }

    func reconcile() async throws -> Decision {
        // Phase 1 (unfenced reads): durable control and receipt state.
        try requireNoControlRecord()
        let receipt = try readReceipt()
        let session = currentSession()

        // Phase 2 (unfenced await): the remote generation when signed in.
        var remoteGeneration: Int64?
        if let session {
            guard let generation = await self.remoteGeneration(session) else {
                throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable")
            }
            remoteGeneration = generation
        }

        // Phase 3 (short gate effect): re-check everything the await could have
        // invalidated, then preserve and stamp. No mutation survives a failed re-check.
        var decision: Decision?
        do {
            try stampEffect {
                try requireNoControlRecord()
                let current = try readReceipt()
                guard current == receipt else {
                    throw JournalStartupAuthorizationError.blocked("generation receipt changed during startup")
                }
                guard currentSession()?.userID == session?.userID else {
                    throw JournalStartupAuthorizationError.blocked("signed-in account changed during startup")
                }
                decision = try decideAndStamp(receipt: receipt, session: session,
                                              remoteGeneration: remoteGeneration)
            }
        } catch let error as JournalStartupAuthorizationError {
            throw error
        } catch {
            throw JournalStartupAuthorizationError.blocked("writer boundary refused startup authorization")
        }
        guard let decision else {
            throw JournalStartupAuthorizationError.blocked("startup authorization produced no decision")
        }
        return decision
    }

    // MARK: decision table (runs inside the stamp effect; synchronous, no awaits)

    private func decideAndStamp(receipt: AccountGenerationPolicy.Receipt?,
                                session: AuthSession?,
                                remoteGeneration: Int64?) throws -> Decision {
        if let receipt {
            // Offline: the existing receipt (local OR account identity) fences writes;
            // there is no new authority to check and the local store is not owner-scoped.
            // Generation reconciliation happens on the next online sync/admission.
            guard let session else { return .proceed }
            if receipt.ownerID == session.userID {
                guard let remoteGeneration else {
                    throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable")
                }
                if remoteGeneration == receipt.generation { return .proceed }
                throw remoteGeneration > receipt.generation
                    ? JournalStartupAuthorizationError.blocked("remote reset committed; confirmed local erase required")
                    : JournalStartupAuthorizationError.blocked("remote generation regressed")
            }
            // First sign-in after a signed-out adoption: transfer the receipt to the
            // account, same generation. Anything else is another account's data: block,
            // never adopt account B over account A's records.
            guard receipt.ownerID == localIdentity else {
                throw JournalStartupAuthorizationError.blocked("local records belong to a different account")
            }
            guard let remoteGeneration else {
                throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable")
            }
            guard remoteGeneration == receipt.generation else {
                throw remoteGeneration > receipt.generation
                    ? JournalStartupAuthorizationError.blocked("remote reset committed; confirmed local erase required")
                    : JournalStartupAuthorizationError.blocked("remote generation regressed")
            }
            try preserveLegacyBytes()
            do { try receiptStore.save(.init(ownerID: session.userID, generation: receipt.generation)) }
            catch { throw JournalStartupAuthorizationError.blocked("generation receipt could not be persisted") }
            return .adoptedAccountOwnership
        }

        // Adoption: no receipt anywhere. Verify preservation BEFORE stamping; stamp at
        // generation 0 only while no reset can have committed (see header assumption).
        let ownerID = session?.userID ?? localIdentity
        guard !ownerID.isEmpty else {
            throw JournalStartupAuthorizationError.blocked("no stable identity supplied")
        }
        if session != nil {
            guard let remoteGeneration else {
                throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable")
            }
            guard remoteGeneration == 0 else {
                throw JournalStartupAuthorizationError.blocked("remote reset committed; confirmed local erase required")
            }
        }
        try preserveLegacyBytes()
        do { try receiptStore.save(.init(ownerID: ownerID, generation: 0)) }
        catch { throw JournalStartupAuthorizationError.blocked("generation receipt could not be persisted") }
        return .adoptedExistingInstall
    }

    // MARK: durable state reads

    private func requireNoControlRecord() throws {
        do {
            if try control.read() != nil {
                throw JournalStartupAuthorizationError.blocked("a reset control record is present")
            }
        } catch let error as JournalStartupAuthorizationError {
            throw error
        } catch {
            throw JournalStartupAuthorizationError.blocked("reset control unreadable")
        }
    }

    private func readReceipt() throws -> AccountGenerationPolicy.Receipt? {
        do { return try receiptStore.read() }
        catch { throw JournalStartupAuthorizationError.blocked("generation receipt unreadable") }
    }

    /// nil = unverifiable: transport, structure, AND contractMissing. An absent reset
    /// contract proves nothing about whether a reset committed, so it can never stand
    /// in for generation 0.
    private func remoteGeneration(_ session: AuthSession) async -> Int64? {
        do { return try await snapshot(session).generation }
        catch { return nil }
    }

    // MARK: preservation (exact bytes, verified readback, durable write)

    private func preserveLegacyBytes() throws {
        var items: [PreservationManifest.Item] = []
        func add(_ name: String, _ data: Data?) {
            guard let data else { return }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            items.append(.init(name: name, sha256: digest, bytes: data))
        }
        add("nutrition-diary-v1", legacyDiary.defaults.data(forKey: NutritionDiaryRepository.storageKey))
        add("nutrition-goals-file", try goals.storage.read())
        add("nutrition-goals-legacy-defaults", goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey))
        guard !items.isEmpty else { return }   // nothing to preserve: stamping is still safe
        let manifest = PreservationManifest(items: items)
        let encoded = try JSONEncoder().encode(manifest)
        do {
            try Self.durableWrite(encoded, named: Self.preservationFileName, in: preservationDirectory)
            let back = try Data(contentsOf: preservationDirectory.appendingPathComponent(Self.preservationFileName))
            guard back == encoded,
                  (try? JSONDecoder().decode(PreservationManifest.self, from: back)) == manifest else {
                throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
            }
        } catch let error as JournalStartupAuthorizationError {
            throw error
        } catch {
            throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
        }
    }

    /// Unique-temp write, fsync/fullsync, atomic rename, directory sync - the same
    /// durability bar as AccountGenerationReceiptStore.
    private static func durableWrite(_ bytes: Data, named name: String, in directory: URL) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/") else {
            throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(name)-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed") }
        var renamed = false
        defer {
            close(fd)
            if !renamed { try? FileManager.default.removeItem(at: temp) }
        }
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
            }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
                }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              rename(temp.path, directory.appendingPathComponent(name).path) == 0 else {
            throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
        }
        renamed = true
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dir >= 0 else {
            throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
        }
        defer { close(dir) }
        guard fsync(dir) == 0 else {
            throw JournalStartupAuthorizationError.blocked("legacy-byte preservation failed")
        }
    }
}
