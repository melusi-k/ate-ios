import Foundation

/// One admitted graph's host transition. UI retirement is required and awaited,
/// not guessed from assigning a sheet boolean. The host supplies concrete removal
/// and rebuild actions; no ordinary owner can reopen on partial failure.
@MainActor
final class FoodJournalGraphTransitions {
    enum Failure: Error { case transitionInProgress, oldOwnerAlreadyClosed }
    private let graph: FoodJournalProductionGraph
    private let retireEditors: () async throws -> Void
    private let rebuild: () async throws -> Void
    private var transitioning = false
    private var retired = false

    init(graph: FoodJournalProductionGraph,
         retireEditors: @escaping () async throws -> Void,
         rebuild: @escaping () async throws -> Void) {
        self.graph = graph; self.retireEditors = retireEditors; self.rebuild = rebuild
    }

    private func close() async throws {
        guard !transitioning else { throw Failure.transitionInProgress }
        guard !retired else { throw Failure.oldOwnerAlreadyClosed }
        try graph.validate()
        transitioning = true
        retired = true
        // The host must remove editors and await their task cancellation before
        // the lifecycle changes epoch. Uncooperative work still drains below.
        do { try await retireEditors() }
        catch {
            // UI retirement failure must still revoke/drain the old owner. Keep
            // the original error; neither old UI nor a replacement may publish.
            try? await graph.quiesce()
            transitioning = false
            throw error
        }
    }

    func changeSession(_ persistSession: () throws -> Void) async throws {
        try await close()
        defer { transitioning = false }
        try await graph.quiesce()
        try graph.handoff(persistSession)
        try await rebuild()
    }

    func importArchive(_ data: Data) async throws -> UnifiedArchiveImportBinding.Result {
        // Structural validation before retiring an otherwise healthy graph.
        let archive = try JSONDecoder().decode(AteUnifiedArchive.self, from: data)
        try UnifiedArchiveImportBinding.validate(archive)
        try await close()
        defer { transitioning = false }
        do {
            let result = try await graph.archiveImport.importData(data)
            try await rebuild()
            return result
        } catch {
            // Import has pre-quiescence checks (links, migration and identity).
            // Once editors retire, EVERY error must still close/drain this graph.
            // Preserve the original import/rebuild error even if cleanup also fails.
            try? await graph.quiesce()
            throw error
        }
    }

    /// Reset owns its durable control/receipt protocol after the closed owner's
    /// proof. An unverified result must throw so rebuild cannot publish ordinary UI.
    func reset(_ performReset: () async throws -> Void) async throws {
        try await close()
        defer { transitioning = false }
        try await graph.quiesce()
        try graph.handoff { }
        try await performReset()
        try await rebuild()
    }
}
