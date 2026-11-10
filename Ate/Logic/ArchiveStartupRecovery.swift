import Foundation

/// Actual state-machine executor. Registered handlers must be supplied by composition;
/// no private path, URL or executable from a recovery record is trusted as a handler.
/// Must run under held lease BEFORE AppStore/JournalStore/repository initialization.
@MainActor
struct ArchiveStartupRecovery {
    struct Handler {
        let component: String
        let restoreBefore: (Data?) throws -> Void
        let verifyBefore: (Data?) throws -> Void
        let verifyAfter: (Data?) throws -> Void
    }
    struct JournalMediaHandler {
        let compensate: (Data) throws -> Void
        let verifyBefore: (Data) throws -> Void
        let verifyAfter: (Data) throws -> Void
        let finishCommitted: (Data) throws -> Void
    }
    enum Failure: Error { case ownershipMismatch, componentMismatch, multipleTransactions }
    let journal: DiskArchiveRecoveryJournal
    let handlers: [Handler]
    let journalMedia: JournalMediaHandler

    /// beforeRetire runs AFTER every verification, restoration and cleanup succeeded and
    /// BEFORE the transaction's atomic retirement. The startup binding uses it to land the
    /// pending durable generation commit: a crash between that commit and the retire leaves
    /// an unresolved committed record, which the next startup completes via the
    /// authorized-advance path without advancing again. A throw skips the retire and keeps
    /// the transaction unresolved for the next startup.
    func run(ownerIdentity: String, beforeRetire: (UUID) throws -> Void = { _ in }) throws {
        try journal.lease.validate()
        let ids = try journal.transactions()
        guard ids.count <= 1 else { throw Failure.multipleTransactions }
        guard let id = ids.first else { return }
        let record = try journal.read(id)
        let history = try journal.history(id)
        let generation = journal.lease.generation
        // A validated historical commit authorizes exactly one generation advance.
        // phase alone loses that fact after committed -> compensating -> rolledBack.
        // This does not advance or repair a generation; unexpected values block.
        let exactGeneration = record.storeGeneration == generation
        let authorizedAdvance = history.hasCommittedMarker && record.storeGeneration < UInt64.max &&
            generation == record.storeGeneration + 1
        guard record.ownerIdentity == ownerIdentity,
              exactGeneration || authorizedAdvance else { throw Failure.ownershipMismatch }
        guard Set(record.images.map(\.component)) == Set(handlers.map(\.component)),
              Set(handlers.map(\.component)).count == handlers.count else { throw Failure.componentMismatch }
        let status = history.phase
        let images = Dictionary(uniqueKeysWithValues: record.images.map { ($0.component, $0) })
        var failures: [String] = []
        if status == .committed {
            // Never undo a committed transaction. Verify after-images, then cleanup.
            for handler in handlers {
                do { try journal.lease.validate(); try handler.verifyAfter(images[handler.component]!.after) }
                catch { failures.append("verify committed \(handler.component): \(error)") }
            }
            do { try journalMedia.verifyAfter(record.journalAndMediaRecovery) }
            catch { failures.append("verify committed journal/media: \(error)") }
            guard failures.isEmpty else {
                throw ArchiveRestoreFailure.recoveryRequired(original: "startup committed verification", compensationFailures: failures)
            }
            try journal.lease.validate()
            try journalMedia.finishCommitted(record.journalAndMediaRecovery)
        } else {
            if status != .compensating && status != .rolledBack {
                // Durable undo intent BEFORE any component rollback can run.
                try journal.transition(id, to: .compensating)
            }
            // Applying intent covers ALL planned writes; prepared-only is also verified
            // against before-images. Each registered undo must recheck its own ownership.
            for handler in handlers.reversed() {
                do {
                    try journal.lease.validate()
                    if status != .rolledBack { try handler.restoreBefore(images[handler.component]!.before) }
                    try handler.verifyBefore(images[handler.component]!.before)
                } catch { failures.append("restore \(handler.component): \(error)") }
            }
            do {
                try journal.lease.validate()
                if status != .rolledBack { try journalMedia.compensate(record.journalAndMediaRecovery) }
                try journalMedia.verifyBefore(record.journalAndMediaRecovery)
            } catch { failures.append("journal/media: \(error)") }
            guard failures.isEmpty else {
                throw ArchiveRestoreFailure.recoveryRequired(original: "startup compensation", compensationFailures: failures)
            }
            if status != .rolledBack { try journal.transition(id, to: .rolledBack) }
        }
        try beforeRetire(id)
        try journal.retire(id)
    }
}
