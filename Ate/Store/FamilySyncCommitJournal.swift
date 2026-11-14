import Foundation
import SwiftData
import CryptoKit
import Darwin

/// The family fields of `SyncMeta` carried by the commit journal's durable authority
/// (issue #34, Reviewer). The journal owns ONLY these fields: recipe/shopping stamps
/// keep their existing writers, so replaying family authority can never roll back a
/// later recipe/shopping metadata write. `ownerID` binds the metadata to the receipt.
struct FamilySyncMetadata: Codable, Equatable {
    var journalStamps: [String: Double]?
    var journalTombs: [String: Double]?
    var insightStamps: [String: Double]?
    var insightTombs: [String: Double]?
    var goalsStamps: [String: Double]?
    var goalsTombs: [String: Double]?
    var goalsSyncedPayload: Data?
    /// Confirmation scope PER FAMILY (Reviewer): a family that failed its round keeps its
    /// old scope, so the aggregate commit never promotes a failed family's stale stamps
    /// into the new owner/epoch. A scope whose generation is behind the live receipt is
    /// simply not current (never a leak): the owner must always match the receipt.
    var journalScope: AccountDataScope?
    var insightScope: AccountDataScope?
    var goalsScope: AccountDataScope?
    var ownerID: String
}

extension SyncMeta {
    /// The current family fields as a journal-owned value.
    func familySyncMetadata(ownerID: String) -> FamilySyncMetadata {
        FamilySyncMetadata(journalStamps: journalStamps, journalTombs: journalTombs,
                           insightStamps: insightStamps, insightTombs: insightTombs,
                           goalsStamps: goalsStamps, goalsTombs: goalsTombs,
                           goalsSyncedPayload: goalsSyncedPayload,
                           journalScope: journalScope, insightScope: insightScope,
                           goalsScope: goalsScope, ownerID: ownerID)
    }

    /// Replaces ONLY the family fields from journal authority; recipe/shopping fields
    /// and any other metadata stay exactly as they are.
    mutating func applyFamilySyncMetadata(_ metadata: FamilySyncMetadata) {
        journalStamps = metadata.journalStamps
        journalTombs = metadata.journalTombs
        insightStamps = metadata.insightStamps
        insightTombs = metadata.insightTombs
        goalsStamps = metadata.goalsStamps
        goalsTombs = metadata.goalsTombs
        goalsSyncedPayload = metadata.goalsSyncedPayload
        journalScope = metadata.journalScope
        insightScope = metadata.insightScope
        goalsScope = metadata.goalsScope
    }
}

/// Dormant durable redo journal for #34 family commits - a direct port of #532's
/// `RecipeShoppingSyncCommitJournal` protocol to the journal/insight/goals families:
/// same checksummed envelope, same temp/fsync/rename/dir-sync/readback install, same
/// versioned intent + authority files, same owner/epoch (receipt) binding on every
/// commit AND replay, same retire-last protocol, same fail-closed reads. When #532
/// lands, the two journals converge on one shared generic; until then this type has
/// no production call site (the family host seam is nil) and exists for the reviewed
/// round + tests.
///
/// REDO, never rollback: the intent records the complete TARGET (after) image of every
/// family store plus the complete family metadata after-image, AND the before-image each
/// family matched when the commit was admitted. Every apply step is an idempotent
/// full-scope drive to the after-image, so an interrupted commit is completed by replay
/// instead of undone - no rollback can run under the wrong owner or race an ordinary edit.
/// Replay re-admits each family independently: content already at the after-image is left
/// alone, content still at the recorded before-image is driven forward, and ANY other
/// content (an ordinary edit that landed after a crash, foreign or corrupt rows) REFUSES
/// the replay and preserves both the content and the intent - changed content is never
/// overwritten by a stale recording. Replay also requires `authorize` to re-prove the
/// CURRENT session + live generation receipt against the intent's recorded receipt: a
/// pending intent from account A (or an old generation) refuses to replay under B and
/// blocks fail-closed until the reset composition erases the directory
/// (`clearAllComponent`, wired with the reset inventory in production).
/// UserDefaults is only a projection of the durable metadata authority.
@MainActor
final class FamilySyncCommitJournal {
    enum Failure: Error {
        case unsafePath, unverifiedRecord, pendingCommit, durabilityUnverified, ownerChanged
    }
    /// Crash-injection points, in execution order. Tests throw from `checkpoint` and
    /// then recover with a FRESH journal over the same directory (real disk reopen).
    enum Boundary: String, CaseIterable {
        case beforeIntentWrite, afterIntentTempSync, afterIntentRename, afterIntentWrite
        case beforeJournalApply, afterJournalApply, beforeInsightApply, afterInsightApply
        case beforeGoalsApply, afterGoalsApply
        case afterAuthorityTempSync, afterAuthorityRename, afterAuthorityWrite
        case afterDefaultsWrite, beforeIntentRetire, afterIntentUnlink, afterIntentRetire
    }
    struct Authority: Codable, Equatable {
        let version: Int
        let transaction: UUID
        let receipt: AccountGenerationPolicy.Receipt
        /// Encoded `FamilySyncMetadata` (complete family after-image).
        let metadata: Data
    }
    /// The complete target image of every family store. A nil family is not part of
    /// the commit (its staging failed this round) and is neither applied nor replayed.
    struct Images: Codable, Equatable {
        var journal: [JournalEntrySyncPayload]?
        var insight: [String: InsightLifecycleRecord]?
        var goals: DailyNutritionGoals?
    }
    private struct Intent: Codable {
        let version: Int
        let authority: Authority
        /// The exact local content the commit's second local read proved; replay drives a
        /// family forward ONLY from this image.
        let before: Images
        /// The complete target image; replay skips a family already at it.
        let after: Images
    }
    private struct Envelope: Codable { let payload: Data; let sha256: String }

    static let directoryName = "FamilySyncCommit"
    private let directory: URL
    private let container: ModelContainer
    private let insightStore: (String) -> InsightLifecycleStore
    private let goals: NutritionGoalsRepository
    private let defaults: UserDefaults
    private let authorize: (AccountGenerationPolicy.Receipt) throws -> Void
    private let checkpoint: (Boundary) throws -> Void
    private let withWriterEffect: (() throws -> Void) throws -> Void
    private let applyJournal: ([JournalEntrySyncPayload], [String]) throws -> Void
    /// Insight content is refused unless this TEST-ONLY flag is on (Reviewer, #34 split):
    /// InsightLifecycleStore is UserDefaults-volatile, so committing insight images is
    /// unsafe until the store is crash-durable. The round produces no insight images;
    /// this blocks any future binding from inheriting the capability by accident.
    private let allowsInsightContent: Bool
    private let goalsDurabilityCheckpoint: (FamilySyncGoalsDurability.Step) throws -> Void
    private var intentURL: URL { directory.appendingPathComponent("pending-v1.json") }
    private var authorityURL: URL { directory.appendingPathComponent("metadata-v1.json") }

    /// No implicit directory provisioning/fallback. Production composition provisions
    /// one immutable directory under the real shared control root and binds its erase
    /// inventory; tests pass a scratch directory they created. `applyJournal` is a test
    /// seam for real apply-failure injection; the default drives the SwiftData bridge.
    init(directory: URL, container: ModelContainer, goals: NutritionGoalsRepository,
         defaults: UserDefaults,
         authorize: @escaping (AccountGenerationPolicy.Receipt) throws -> Void,
         withWriterEffect: @escaping (() throws -> Void) throws -> Void,
         insightStore: @escaping (String) -> InsightLifecycleStore = { InsightLifecycleStore(accountID: $0) },
         applyJournal: (([JournalEntrySyncPayload], [String]) throws -> Void)? = nil,
         allowsInsightContent: Bool = false,
         goalsDurabilityCheckpoint: @escaping (FamilySyncGoalsDurability.Step) throws -> Void = { _ in },
         checkpoint: @escaping (Boundary) throws -> Void = { _ in }) throws {
        #if !DEBUG
        guard !allowsInsightContent else { throw Failure.unverifiedRecord }
        #endif
        self.directory = directory; self.container = container; self.goals = goals
        self.defaults = defaults; self.authorize = authorize
        self.withWriterEffect = withWriterEffect; self.checkpoint = checkpoint
        self.insightStore = insightStore
        self.allowsInsightContent = allowsInsightContent
        self.goalsDurabilityCheckpoint = goalsDurabilityCheckpoint
        self.applyJournal = applyJournal ?? { upserts, deletes in
            try JournalSyncBridge.apply(upserts: upserts, deletes: deletes, container: container)
        }
        try validateDirectory()
    }

    private func validateDirectory() throws {
        var st = stat()
        guard directory.isFileURL, directory.standardizedFileURL == directory,
              lstat(directory.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            throw Failure.unsafePath
        }
    }

    /// Fail-closed read: absence is nil; ANY other irregularity (unreadable, non-regular
    /// file) throws. Corrupt content is never treated as absent.
    private func read(_ url: URL) throws -> Data? {
        try validateDirectory()
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            if errno == ENOENT { return nil }
            throw Failure.unverifiedRecord
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else { throw Failure.unsafePath }
        return try Data(contentsOf: url)
    }

    private func temporary(_ url: URL) -> URL { url.appendingPathExtension("tmp") }

    private func syncDirectory() throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.durabilityUnverified }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure.durabilityUnverified }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(value)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return try encoder.encode(Envelope(payload: payload, sha256: digest))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes),
              SHA256.hash(data: envelope.payload).map({ String(format: "%02x", $0) }).joined() == envelope.sha256,
              let value = try? JSONDecoder().decode(type, from: envelope.payload) else {
            throw Failure.unverifiedRecord
        }
        return value
    }

    /// Plain deterministic encoding for the authority's metadata field; the envelope's
    /// checksum covers it once the whole authority is installed.
    private func encodeMetadata(_ metadata: FamilySyncMetadata) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(metadata)
    }

    /// Atomic replacement + file/parent durability/readback. Retain unresolved temp
    /// evidence on failure; replay may promote only exactly matching expected bytes.
    private func install(_ bytes: Data, at destination: URL) throws {
        _ = try read(destination)
        let temp = temporary(destination)
        if let existingTemp = try read(temp) {
            guard existingTemp == bytes else { throw Failure.unverifiedRecord }
        } else {
            let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw Failure.durabilityUnverified }
            defer { close(fd) }
            try bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { throw Failure.unverifiedRecord }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw Failure.durabilityUnverified }
                    offset += count
                }
            }
            guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw Failure.durabilityUnverified }
        }
        let verifyFD = open(temp.path, O_RDONLY | O_NOFOLLOW)
        guard verifyFD >= 0 else { throw Failure.durabilityUnverified }
        defer { close(verifyFD) }
        guard fsync(verifyFD) == 0, fcntl(verifyFD, F_FULLFSYNC) == 0 else { throw Failure.durabilityUnverified }
        try checkpoint(tempSyncBoundary(for: destination))
        guard rename(temp.path, destination.path) == 0 else { throw Failure.durabilityUnverified }
        try checkpoint(renameBoundary(for: destination))
        try syncDirectory()
        guard try read(destination) == bytes else { throw Failure.durabilityUnverified }
    }

    private func tempSyncBoundary(for destination: URL) -> Boundary {
        destination == intentURL ? .afterIntentTempSync : .afterAuthorityTempSync
    }

    private func renameBoundary(for destination: URL) -> Boundary {
        destination == intentURL ? .afterIntentRename : .afterAuthorityRename
    }

    private func validate(_ authority: Authority) throws {
        guard authority.version == 1, !authority.receipt.ownerID.isEmpty,
              authority.receipt.generation >= 0,
              let metadata = try? JSONDecoder().decode(FamilySyncMetadata.self, from: authority.metadata),
              metadata.ownerID == authority.receipt.ownerID
        else { throw Failure.unverifiedRecord }
        // Per-family scopes may lag the receipt's generation (a family that failed a later
        // round keeps its older confirmation) but must never name another owner.
        for scope in [metadata.journalScope, metadata.insightScope, metadata.goalsScope] {
            if let scope, scope.ownerID != authority.receipt.ownerID { throw Failure.unverifiedRecord }
        }
        // Real current session + live receipt/scope proof, supplied by the composition.
        try authorize(authority.receipt)
    }

    private func validate(_ intent: Intent) throws {
        guard intent.version == 1 else { throw Failure.unverifiedRecord }
        // Insight content is refused while insight sync is dormant (see allowsInsightContent).
        guard allowsInsightContent
                || (intent.before.insight == nil && intent.after.insight == nil) else {
            throw Failure.unverifiedRecord
        }
        for images in [intent.before, intent.after] {
            if let journal = images.journal {
                guard journal.allSatisfy({ !$0.id.isEmpty }),
                      Set(journal.map(\.id)).count == journal.count else { throw Failure.unverifiedRecord }
            }
            if let insight = images.insight {
                guard insight.keys.allSatisfy({ !$0.isEmpty }) else { throw Failure.unverifiedRecord }
            }
        }
        // Every driven family needs its admission image: without it replay could not
        // distinguish "interrupted" from "changed behind our back".
        if intent.after.journal != nil, intent.before.journal == nil { throw Failure.unverifiedRecord }
        if intent.after.insight != nil, intent.before.insight == nil { throw Failure.unverifiedRecord }
        if intent.after.goals != nil, intent.before.goals == nil { throw Failure.unverifiedRecord }
        try validate(intent.authority)
    }

    private func existingAuthority() throws -> Authority? {
        guard let bytes = try read(authorityURL) else { return nil }
        let value = try decode(Authority.self, bytes)
        try validate(value)
        return value
    }

    /// The metadata a commit records. `verify` is the round's second local read: it runs
    /// inside the admitted boundary BEFORE the intent is written, so a local change that
    /// landed during the upload refuses the commit while nothing is yet recorded.
    struct Commit {
        let receipt: AccountGenerationPolicy.Receipt
        let metadata: FamilySyncMetadata
        /// The local content the second local read proved at admission (per driven family).
        let before: Images
        /// The complete target image per driven family (nil family = not part of the commit).
        let after: Images
        let verify: () throws -> Void
    }

    /// Drives every family store and the family metadata to the recorded target.
    /// Returns the metadata for in-memory adoption. On ANY throw the intent stays
    /// durable and the next replay completes the same target - no rollback ever runs.
    func commit(_ commit: Commit) throws -> FamilySyncMetadata {
        var result: FamilySyncMetadata?
        var performed = false
        try withWriterEffect {
            performed = true
            result = try commitHeld(commit)
        }
        guard performed, let result else { throw Failure.durabilityUnverified }
        return result
    }

    private func commitHeld(_ commit: Commit) throws -> FamilySyncMetadata {
        // Every confirmed family's scope names this commit's owner; a family outside the
        // commit keeps its carried-over scope (older generation is fine, foreign owner is not).
        for scope in [commit.metadata.journalScope, commit.metadata.insightScope, commit.metadata.goalsScope] {
            if let scope, scope.ownerID != commit.receipt.ownerID { throw Failure.unverifiedRecord }
        }
        try authorize(commit.receipt)
        // A pending intent belongs to an interrupted earlier commit: replay it first
        // (recoverAndProject), never overwrite it with a newer target.
        guard try read(intentURL) == nil, try read(temporary(intentURL)) == nil,
              try read(temporary(authorityURL)) == nil else { throw Failure.pendingCommit }
        // Foreign/corrupt authority is never silently overwritten.
        _ = try existingAuthority()
        let intent = Intent(version: 1,
                            authority: Authority(version: 1, transaction: UUID(),
                                                 receipt: commit.receipt,
                                                 metadata: try encodeMetadata(commit.metadata)),
                            before: commit.before,
                            after: commit.after)
        try validate(intent)
        // Second local read under the held boundary, BEFORE anything is recorded.
        try commit.verify()
        try checkpoint(.beforeIntentWrite)
        try install(encode(intent), at: intentURL)
        try checkpoint(.afterIntentWrite)
        try apply(intent)
        return commit.metadata
    }

    private func apply(_ intent: Intent) throws {
        try validate(intent)
        let base = try projectionBase()
        guard base.userID == nil || base.userID == intent.authority.receipt.ownerID else {
            throw Failure.ownerChanged
        }
        // PREFLIGHT (Reviewer): resolve every driven family's disposition AND the metadata
        // ownership (validate above) BEFORE any write. A foreign or changed family refuses
        // the whole replay with NOTHING mutated - never a partial drive.
        var journalDrive: (upserts: [JournalEntrySyncPayload], deletes: [String])?
        if let image = intent.after.journal, let before = intent.before.journal {
            try checkpoint(.beforeJournalApply)
            guard let current = try? JournalSyncBridge.export(container: container) else {
                throw Failure.unverifiedRecord
            }
            let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let expected = Dictionary(image.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            if currentByID != expected {
                let beforeByID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                guard currentByID == beforeByID else { throw Failure.unverifiedRecord }
                let imageIDs = Set(image.map(\.id))
                journalDrive = (image, current.map(\.id).filter { !imageIDs.contains($0) })
            }
        }
        var insightDrive = false
        if let image = intent.after.insight, let before = intent.before.insight {
            try checkpoint(.beforeInsightApply)
            let current = insightStore(intent.authority.receipt.ownerID).exportRecords()
            if current != image {
                guard current == before else { throw Failure.unverifiedRecord }
                insightDrive = true
            }
        }
        var goalsDrive = false
        if let image = intent.after.goals, let before = intent.before.goals {
            try checkpoint(.beforeGoalsApply)
            guard let current = try? goals.load() else { throw Failure.unverifiedRecord }
            if current != image {
                guard current == before else { throw Failure.unverifiedRecord }
                goalsDrive = true
            }
        }
        // DRIVE: each family is an idempotent full-scope drive to the recorded image.
        if let drive = journalDrive, let image = intent.after.journal {
            try applyJournal(drive.upserts, drive.deletes)
            let applied = try Dictionary(
                JournalSyncBridge.export(container: container).map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a })
            guard applied == Dictionary(image.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) else {
                throw Failure.unverifiedRecord
            }
        }
        if intent.after.journal != nil { try checkpoint(.afterJournalApply) }
        if let image = intent.after.insight {
            let store = insightStore(intent.authority.receipt.ownerID)
            if insightDrive {
                store.applySyncedRecords(image)
                guard store.exportRecords() == image else { throw Failure.unverifiedRecord }
            }
            try checkpoint(.afterInsightApply)
            // NOTE (Reviewer, #34 split): insight CONTENT is UserDefaults-volatile and this
            // journal deliberately does NOT paper over that with a post-retire repair image
            // (a repair layer cannot distinguish a lost volatile apply from a deliberate
            // local removal without local tombstones). Insight family sync is dormant until
            // InsightLifecycleStore gains crash-durable storage - see the #34 doc follow-ups.
        }
        if let image = intent.after.goals {
            if goalsDrive {
                try goals.save(image)
                guard (try? goals.load()) == image else { throw Failure.unverifiedRecord }
            }
            // Seal even when the store already equals the target: a prior interrupted
            // save may have reached readback without reaching file/parent durability.
            guard let storage = goals.storage as? any FamilySyncGoalsFileStorage else {
                throw Failure.durabilityUnverified
            }
            try FamilySyncGoalsDurability(fileURL: storage.fileURL,
                                          checkpoint: goalsDurabilityCheckpoint).seal(image)
            try checkpoint(.afterGoalsApply)
        }
        // Metadata authority is durable BEFORE the defaults projection and the intent
        // retire: a crash anywhere after this point recovers from authority alone.
        try install(encode(intent.authority), at: authorityURL)
        try checkpoint(.afterAuthorityWrite)
        // Defaults may disappear after readback. Durable authority above is ALWAYS the
        // source of truth; every recovery projects it again before ordinary load.
        try projectToDefaults(intent.authority)
        try checkpoint(.afterDefaultsWrite)
        try validate(intent.authority)
        try checkpoint(.beforeIntentRetire)
        guard unlink(intentURL.path) == 0 else { throw Failure.durabilityUnverified }
        try checkpoint(.afterIntentUnlink)
        try syncDirectory()
        try checkpoint(.afterIntentRetire)
    }

    /// Merges the authority's family fields into the CURRENT defaults metadata (leaving
    /// recipe/shopping fields untouched) and verifies the readback. Fail-closed (Reviewer):
    /// existing `ate.sync.v1` bytes that are absent decode from an empty base, but bytes
    /// that are PRESENT and undecodable (or not Data at all) refuse the write - the
    /// projection never overwrites unreadable recipe/shopping metadata with an empty base.
    private func projectToDefaults(_ authority: Authority) throws {
        let metadata = try JSONDecoder().decode(FamilySyncMetadata.self, from: authority.metadata)
        var current = try projectionBase()
        // Every caller, including bare-authority recovery and reset, must preserve
        // a foreign owner's existing metadata rather than merge confirmations into it.
        guard current.userID == nil || current.userID == authority.receipt.ownerID else {
            throw Failure.ownerChanged
        }
        current.applyFamilySyncMetadata(metadata)
        let bytes = try JSONEncoder().encode(current)
        defaults.set(bytes, forKey: "ate.sync.v1")
        guard defaults.data(forKey: "ate.sync.v1") == bytes else { throw Failure.unverifiedRecord }
    }

    private func projectionBase() throws -> SyncMeta {
        if let raw = defaults.object(forKey: "ate.sync.v1") {
            guard let data = raw as? Data,
                  let decoded = try? JSONDecoder().decode(SyncMeta.self, from: data) else {
                throw Failure.unverifiedRecord
            }
            return decoded
        }
        return SyncMeta()
    }

    /// Call at the start of every family round, BEFORE validation and staging. Replays
    /// the recorded local result only, never repeats any cloud upload. Returns the
    /// projected metadata for in-memory adoption, nil when no authority exists.
    /// Fail-closed: a corrupt, foreign or stale-epoch intent/authority THROWS and
    /// blocks the round; nothing is mutated and the evidence is preserved.
    @discardableResult
    func recoverAndProject() throws -> FamilySyncMetadata? {
        var result: FamilySyncMetadata??
        var performed = false
        try withWriterEffect {
            performed = true
            result = try recoverHeld()
        }
        guard performed, let result else { throw Failure.durabilityUnverified }
        return result
    }

    private func recoverHeld() throws -> FamilySyncMetadata? {
        let pending = try read(intentURL), temp = try read(temporary(intentURL))
        // Both present means an unresolved crash mid-rename with ambiguous truth.
        guard pending == nil || temp == nil else { throw Failure.unverifiedRecord }
        if let bytes = pending ?? temp {
            let intent = try decode(Intent.self, bytes)
            try validate(intent)
            _ = try existingAuthority()
            if pending == nil {
                // Crash between temp sync and rename: promote only the exact bytes.
                try install(bytes, at: intentURL)
            }
            try apply(intent)
            return try JSONDecoder().decode(FamilySyncMetadata.self, from: intent.authority.metadata)
        }
        guard try read(temporary(authorityURL)) == nil else { throw Failure.unverifiedRecord }
        if let authority = try existingAuthority() {
            try projectToDefaults(authority)
            return try JSONDecoder().decode(FamilySyncMetadata.self, from: authority.metadata)
        }
        try syncDirectory()
        return nil
    }

    /// Epoch reset (generation changed): replaces the authority with cleared family
    /// metadata authorized against the CURRENT receipt, and re-projects defaults. A
    /// pending intent is NOT touched - it belongs to the old epoch, keeps refusing
    /// replay, and is erased only by the reset composition (`clearAllComponent`).
    func resetMetadata(_ metadata: FamilySyncMetadata,
                       receipt: AccountGenerationPolicy.Receipt) throws {
        try withWriterEffect {
            let authority = Authority(version: 1, transaction: UUID(), receipt: receipt,
                                      metadata: try encodeMetadata(metadata))
            try validate(authority)
            try install(encode(authority), at: authorityURL)
            try projectToDefaults(authority)
        }
    }

    func requireDirectory(_ expected: URL) throws {
        guard directory == expected else { throw Failure.unsafePath }
        try validateDirectory()
    }

    /// Personal intent/authority files must be erased by account-wide Clear all.
    /// This is the exact component to append to the family reset inventory.
    func clearAllComponent(validateResetGate: @escaping () throws -> Void) -> ClearAllLocalData.Component {
        ClearAllLocalData.directory(name: "family-sync-commit", url: directory,
                                    validateWriterGate: validateResetGate)
    }
}
