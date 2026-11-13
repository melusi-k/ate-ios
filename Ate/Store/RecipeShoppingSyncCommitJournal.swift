import Foundation
import SwiftData
import CryptoKit
import Darwin

/// Dormant durable redo protocol. All ordinary recipe/shopping AND metadata writers
/// must use this authority before production wiring. UserDefaults is only a projection.
/// Retains/holds the ORIGINAL admitted account gate/lease across each synchronous
/// call. Recovery requires fresh snapshot admission before any replay/projection.
@MainActor
final class RecipeShoppingSyncCommitJournal {
    enum Failure: Error { case unsafePath, unverifiedRecord, pendingCommit, durabilityUnverified, ownerChanged }
    enum Boundary: String, CaseIterable {
        case beforeIntentWrite, afterIntentTempSync, afterIntentRename, afterIntentWrite, beforeStoreSave, afterStoreSave
        case afterAuthorityTempSync, afterAuthorityRename, afterAuthorityWrite, afterDefaultsWrite
        case beforeIntentRetire, afterIntentUnlink, afterIntentRetire
    }
    struct Authority: Codable, Equatable {
        let version: Int
        let transaction: UUID
        let receipt: AccountGenerationPolicy.Receipt
        let metadata: Data
    }
    private struct Intent: Codable {
        let version: Int
        let authority: Authority
        let image: ArchiveRecipeShoppingImage
    }
    private struct Envelope: Codable { let payload: Data; let sha256: String }
    static let directoryName = "RecipeShoppingSyncCommit"
    private let gate: AccountWriterGate
    private let writerLease: UUID
    private let directory: URL
    private let container: ModelContainer
    private let defaults: UserDefaults
    private let authorize: (AccountGenerationPolicy.Receipt) throws -> Void
    private let checkpoint: (Boundary) throws -> Void
    private let validateWriterRouting: () throws -> Void
    private let save: (ModelContext) throws -> Void
    private var intentURL: URL { directory.appendingPathComponent("pending-v1.json") }
    private var authorityURL: URL { directory.appendingPathComponent("metadata-v1.json") }

    /// No implicit directory provisioning/fallback. Final composition provisions one
    /// immutable directory under the real shared control root and binds its erase inventory.
    init(directory: URL, gate: AccountWriterGate, writerLease: UUID, container: ModelContainer, defaults: UserDefaults,
         authorize: @escaping (AccountGenerationPolicy.Receipt) throws -> Void,
         validateWriterRouting: @escaping () throws -> Void,
         save: @escaping (ModelContext) throws -> Void = { try $0.save() },
         checkpoint: @escaping (Boundary) throws -> Void = { _ in }) throws {
        self.gate = gate; self.writerLease = writerLease
        self.directory = directory; self.container = container; self.defaults = defaults
        self.authorize = authorize; self.checkpoint = checkpoint
        self.validateWriterRouting = validateWriterRouting; self.save = save
        try validateDirectory()
    }
    private func validateDirectory() throws {
        var st = stat()
        guard directory.isFileURL, directory.standardizedFileURL == directory,
              lstat(directory.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { throw Failure.unsafePath }
    }
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
              let value = try? JSONDecoder().decode(type, from: envelope.payload) else { throw Failure.unverifiedRecord }
        return value
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
        try checkpoint(destination == intentURL ? .afterIntentTempSync : .afterAuthorityTempSync)
        guard rename(temp.path, destination.path) == 0 else { throw Failure.durabilityUnverified }
        try checkpoint(destination == intentURL ? .afterIntentRename : .afterAuthorityRename)
        try syncDirectory()
        guard try read(destination) == bytes else { throw Failure.durabilityUnverified }
    }
    private func validate(_ authority: Authority) throws {
        guard authority.version == 1, !authority.receipt.ownerID.isEmpty, authority.receipt.generation >= 0,
              let metadata = try? JSONDecoder().decode(RecipeShoppingSyncStage.Metadata.self, from: authority.metadata),
              metadata.userID == authority.receipt.ownerID else { throw Failure.unverifiedRecord }
        try authorize(authority.receipt) // real current session + receipt + original gate
        try validateWriterRouting() // no retirement/admission while any writer bypasses authority
    }
    private func existingAuthority() throws -> Authority? {
        guard let bytes = try read(authorityURL) else { return nil }
        let value = try decode(Authority.self, bytes)
        try validate(value)
        return value
    }
    private func validate(_ intent: Intent) throws {
        guard intent.version == 1,
              Set(intent.image.recipes.map(\.id)).count == intent.image.recipes.count,
              Set(intent.image.shopping.map(\.id)).count == intent.image.shopping.count,
              intent.image.recipes.enumerated().allSatisfy({ $0.offset == $0.element.position && !$0.element.id.isEmpty }),
              intent.image.shopping.enumerated().allSatisfy({ $0.offset == $0.element.position && !$0.element.id.isEmpty }) else {
            throw Failure.unverifiedRecord
        }
        try validate(intent.authority)
    }

    func commit(_ stage: RecipeShoppingSyncStage, receipt: AccountGenerationPolicy.Receipt) throws {
        try gate.withWriterEffect(writerLease) { try commitHeld(stage, receipt: receipt) }
    }
    private func commitHeld(_ stage: RecipeShoppingSyncStage, receipt: AccountGenerationPolicy.Receipt) throws {
        try authorize(receipt)
        guard try read(intentURL) == nil, try read(temporary(intentURL)) == nil,
              try read(temporary(authorityURL)) == nil else { throw Failure.pendingCommit }
        _ = try existingAuthority() // foreign/corrupt authority is never silently overwritten
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let image = ArchiveRecipeShoppingImage(
            recipes: try stage.recipes.enumerated().map { index, card in
                ArchiveRawRecipeImage(id: card.id, createdAt: card.createdAt, position: index, json: try encoder.encode(card))
            }, shopping: try stage.shopping.enumerated().map { index, item in
                ArchiveRawShoppingImage(id: item.id, position: index, json: try encoder.encode(item))
            })
        let intent = Intent(version: 1, authority: Authority(version: 1, transaction: UUID(), receipt: receipt,
            metadata: try encoder.encode(stage.metadata)), image: image)
        try validate(intent)
        try checkpoint(.beforeIntentWrite)
        try install(encode(intent), at: intentURL)
        try checkpoint(.afterIntentWrite)
        try apply(intent)
    }
    private func apply(_ intent: Intent) throws {
        try validate(intent)
        // Existing exact raw image service, no model normalization or fallback.
        try UnifiedArchiveStartupRecovery.restoreRecipeShopping(intent.image, container: container, save: { context in
            try self.checkpoint(.beforeStoreSave)
            try self.save(context)
            try self.checkpoint(.afterStoreSave)
        })
        guard try UnifiedArchiveImportBinding.snapshotRecipeShopping(container) == intent.image else {
            throw Failure.unverifiedRecord
        }
        try validate(intent.authority)
        try install(encode(intent.authority), at: authorityURL)
        try checkpoint(.afterAuthorityWrite)
        // Defaults may disappear after readback. Durable authority above is ALWAYS
        // the source of truth; every startup projects it again before ordinary load.
        defaults.set(intent.authority.metadata, forKey: "ate.sync.v1")
        guard defaults.data(forKey: "ate.sync.v1") == intent.authority.metadata else { throw Failure.unverifiedRecord }
        try checkpoint(.afterDefaultsWrite)
        try validate(intent.authority)
        try checkpoint(.beforeIntentRetire)
        guard unlink(intentURL.path) == 0 else { throw Failure.durabilityUnverified }
        try checkpoint(.afterIntentUnlink)
        try syncDirectory()
        try checkpoint(.afterIntentRetire)
    }

    /// Call after current snapshot admission, BEFORE load/normalization/new merge.
    /// Replays the recorded local result only, never repeats any cloud upload.
    @discardableResult
    func recoverAndProject() throws -> Bool {
        try gate.withWriterEffect(writerLease) { try recoverHeld() }
    }
    private func recoverHeld() throws -> Bool {
        let pending = try read(intentURL), temp = try read(temporary(intentURL))
        guard pending == nil || temp == nil else { throw Failure.unverifiedRecord }
        if let bytes = pending ?? temp {
            let intent = try decode(Intent.self, bytes)
            try validate(intent)
            _ = try existingAuthority()
            if pending == nil { try install(bytes, at: intentURL) }
            try apply(intent)
            return true
        }
        guard try read(temporary(authorityURL)) == nil else { throw Failure.unverifiedRecord }
        if let authority = try existingAuthority() {
            defaults.set(authority.metadata, forKey: "ate.sync.v1")
            guard defaults.data(forKey: "ate.sync.v1") == authority.metadata else { throw Failure.unverifiedRecord }
        }
        try syncDirectory()
        return false
    }

    /// Personal intent/authority files must be erased by account-wide Clear all.
    /// This is the exact component to append to the standalone reset inventory.
    func clearAllComponent(validateResetGate: @escaping () throws -> Void) -> ClearAllLocalData.Component {
        ClearAllLocalData.directory(name: "recipe-shopping-sync-commit", url: directory,
            validateWriterGate: validateResetGate)
    }
}
