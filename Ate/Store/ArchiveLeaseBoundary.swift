import Foundation

/// APPROVED cross-slice seam (2026-11-09, slices A/B + central, lock-order "Shape A"):
/// the account gate holds the single per-effect flock on the shared writer-gate-v1.lock
/// (OUTER); the archive side does NO flock in nested mode and only validates and advances
/// the durable UInt64 generation chain (INNER). Generations stay separate by design:
/// the account UUID epoch is volatile, the archive generation is durable - no merging.
///
/// The durable generation must advance after EVERY covered committed write (meal,
/// reflection, defaults, import) so a prepared recovery record's storeGeneration can never
/// be wrongly treated as current. Exactly one advance per committed unit; throwing work
/// commits nothing.
///
/// When the covered unit is a journaled import, its committed recovery transaction stays
/// UNRESOLVED through the advance: the caller retires Result.committedTransactionID only
/// AFTER withNestedLease returns, so a crash between commit and advance (or between
/// advance and retire) is completed exactly once by startup recovery.
protocol ArchiveNestedLeaseBoundary {
    func withNestedLease<T>(_ work: () throws -> T) throws -> T
}

/// Per-effect nested boundary: holds no lease and no flock for any lifetime. Each effect
/// acquires a nested (no-flock) POSIXArchiveWriterLease, validates the generation chain,
/// runs the covered unit, commits exactly one generation on success, and releases.
/// The caller's held account-gate flock on writer-gate-v1.lock is the mutual exclusion;
/// this type never opens or flocks any lock file.
@MainActor
final class ArchiveNestedGenerationBoundary: ArchiveNestedLeaseBoundary {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func withNestedLease<T>(_ work: () throws -> T) throws -> T {
        let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
        defer { lease.release() }
        try lease.validate()
        let result = try work()
        try lease.commitGeneration(lease.generation + 1)
        return result
    }
}

enum ArchiveStandaloneLeaseFailure: LocalizedError {
    /// A reset control record exists: archive import/startup sessions refuse to start
    /// while a reset is pending, so the two writers can never interleave.
    case resetPending

    var errorDescription: String? {
        switch self {
        case .resetPending: "A data reset is still finishing. The archive is untouched."
        }
    }
}

/// Standalone lease for startup recovery and import sessions: a lifetime exclusive flock
/// retargeted to the ONE shared writer-gate-v1.lock in the control root (never unlinked),
/// refused while a reset control record exists.
enum ArchiveStandaloneLeaseFactory {
    static let sharedLockName = "writer-gate-v1.lock"

    static func lease(controlDirectory: URL, resetPending: () throws -> Bool) throws -> POSIXArchiveWriterLease {
        guard try !resetPending() else { throw ArchiveStandaloneLeaseFailure.resetPending }
        let lease = try POSIXArchiveWriterLease(directory: controlDirectory, lockName: sharedLockName)
        // A reset control record created between the pre-check and the flock is caught
        // here, under the held lock: release and refuse rather than interleave with the
        // reset writer.
        do {
            guard try !resetPending() else { throw ArchiveStandaloneLeaseFailure.resetPending }
        } catch {
            lease.release()
            throw error
        }
        return lease
    }
}

/// Standalone import session: holds the lifetime flock on the shared lock file and owns the
/// single generation advance for the import's committed unit. UnifiedArchiveImportBinding
/// deliberately never advances the generation itself.
@MainActor
struct ArchiveStandaloneImportSession {
    let lease: POSIXArchiveWriterLease
    let recoveryJournal: DiskArchiveRecoveryJournal

    init(controlDirectory: URL, resetPending: () throws -> Bool) throws {
        lease = try ArchiveStandaloneLeaseFactory.lease(controlDirectory: controlDirectory,
                                                        resetPending: resetPending)
        recoveryJournal = DiskArchiveRecoveryJournal(lease: lease)
    }

    /// Runs one journaled import as one committed unit, then advances the durable
    /// generation exactly once, then retires the committed transaction. A throwing import
    /// commits nothing. A crash between the durable commit and the advance, or between
    /// the advance and the retire, is completed exactly once by startup recovery from the
    /// unresolved transaction (see UnifiedArchiveImportBinding.importArchive).
    func importArchive(_ archive: AteUnifiedArchive,
                       binding: UnifiedArchiveImportBinding,
                       checkpoint: (ArchiveRestoreBoundary) throws -> Void = { _ in }) throws -> UnifiedArchiveImportBinding.Result {
        let result = try binding.importArchive(archive, checkpoint: checkpoint)
        try lease.commitGeneration(lease.generation + 1)
        try binding.recoveryJournal.retire(result.committedTransactionID)
        return result
    }
}
