import Foundation
import CryptoKit
import Darwin

/// Dormant existing-install adoption only. Unknown owners and advanced generation
/// cannot stamp or delete. No StoreRecovery fallback, no automatic reset/switch.
@MainActor
final class RecipeShoppingLegacyAdmission {
    enum Refusal: Error { case existingReceipt, ownerChanged, advancedGeneration, changedInventory, unsafePath, preservationUnverified, invalidSnapshot }
    struct Preservation: Codable {
        let version: Int
        let ownerID: String
        let generation: Int64
        let image: ArchiveRecipeShoppingImage
        let metadata: Data
    }
    private struct Envelope: Codable { let payload: Data; let sha256: String }
    private let gate: AccountWriterGate, lease: UUID
    private let receipts: AccountGenerationReceiptStore
    private let rpc: AccountDataResetService
    private let directory: URL
    private let currentSession: () -> AuthSession?
    private let captureRaw: () throws -> RecipeShoppingRawInventory

    init(gate: AccountWriterGate, lease: UUID, receiptStore: AccountGenerationReceiptStore,
         rpc: AccountDataResetService, preservationDirectory: URL,
         currentSession: @escaping () -> AuthSession?, captureRaw: @escaping () throws -> RecipeShoppingRawInventory) {
        self.gate = gate; self.lease = lease; self.receipts = receiptStore; self.rpc = rpc
        self.directory = preservationDirectory; self.currentSession = currentSession; self.captureRaw = captureRaw
    }
    private func validateSession(_ session: AuthSession) throws {
        try Task.checkCancellation()
        guard !session.userID.isEmpty, currentSession() == session else { throw Refusal.ownerChanged }
        try gate.validateWriter(lease)
    }
    /// Raw capture must use strict non-repairing store reads, not AppStore arrays.
    /// It is inspected again under the same gate after snapshot await. Preservation
    /// is exact bytes and fsynced/readback before the first receipt can be stamped.
    func adoptKnownLegacyOwner(session: AuthSession) async throws -> AccountGenerationPolicy.Receipt {
        let before: RecipeShoppingRawInventory = try gate.withWriterEffect(lease) {
            try validateSession(session)
            guard try receipts.read() == nil else { throw Refusal.existingReceipt }
            let raw = try captureRaw()
            _ = try raw.validate(ownerID: session.userID)
            return raw
        }
        let snapshot = try await rpc.snapshot(session: session)
        try validateSession(session)
        // First adoption never promotes legacy bytes into a generation that has
        // already observed a reset, even if the server currently looks empty.
        guard snapshot.generation == 0 else { throw Refusal.advancedGeneration }
        guard snapshot.rows.allSatisfy({ $0.user_id == session.userID }) else { throw Refusal.invalidSnapshot }
        return try gate.withWriterEffect(lease) {
            try validateSession(session)
            guard try receipts.read() == nil else { throw Refusal.existingReceipt }
            let after = try captureRaw()
            _ = try after.validate(ownerID: session.userID)
            guard before.image == after.image, before.metadataBytes == after.metadataBytes,
                  let metadata = after.metadataBytes else { throw Refusal.changedInventory }
            let receipt = AccountGenerationPolicy.Receipt(ownerID: session.userID, generation: 0)
            try preserve(Preservation(version: 1, ownerID: receipt.ownerID, generation: receipt.generation,
                image: after.image, metadata: metadata))
            try validateSession(session)
            try receipts.save(receipt)
            return receipt
        }
    }
    private var file: URL { directory.appendingPathComponent("legacy-recipe-shopping-v1.json") }
    private func bytes(_ url: URL) throws -> Data? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            if errno == ENOENT { return nil }
            throw Refusal.preservationUnverified
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else { throw Refusal.unsafePath }
        return try Data(contentsOf: url)
    }
    private func preserve(_ record: Preservation) throws {
        var st = stat()
        guard directory.isFileURL, directory.standardizedFileURL == directory,
              directory.resolvingSymlinksInPath().standardizedFileURL == directory,
              lstat(directory.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { throw Refusal.unsafePath }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(record)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let encoded = try encoder.encode(Envelope(payload: payload, sha256: digest))
        let temp = file.appendingPathExtension("tmp")
        if let previous = try bytes(file) {
            guard previous == encoded, try bytes(temp) == nil else { throw Refusal.preservationUnverified }
            let fd = open(file.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Refusal.preservationUnverified }
            defer { close(fd) }
            let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard parent >= 0 else { throw Refusal.preservationUnverified }
            defer { close(parent) }
            guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0, fsync(parent) == 0 else { throw Refusal.preservationUnverified }
            return // exact prior preservation is reusable, never silently replaced
        }
        if let partial = try bytes(temp) {
            guard partial == encoded else { throw Refusal.preservationUnverified }
        } else {
            let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw Refusal.preservationUnverified }
            defer { close(fd) }
            try encoded.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { throw Refusal.preservationUnverified }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw Refusal.preservationUnverified }
                    offset += count
                }
            }
            guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw Refusal.preservationUnverified }
        }
        let fd = open(temp.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Refusal.preservationUnverified }
        defer { close(fd) }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              rename(temp.path, file.path) == 0 else { throw Refusal.preservationUnverified }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Refusal.preservationUnverified }
        defer { close(parent) }
        guard fsync(parent) == 0, try bytes(file) == encoded else { throw Refusal.preservationUnverified }
    }
    func clearAllComponent(validateResetGate: @escaping () throws -> Void) -> ClearAllLocalData.Component {
        ClearAllLocalData.directory(name: "legacy-recipe-shopping-preservation", url: directory,
            validateWriterGate: validateResetGate)
    }
}
