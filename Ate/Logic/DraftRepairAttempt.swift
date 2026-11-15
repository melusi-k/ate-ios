import Foundation

/// Owns the repair task and its admission token. A backend may ignore Task
/// cancellation, so invalidation must also close the post-await write gate.
@MainActor
final class DraftRepairAttempt {
    private var token: UUID?
    private var task: Task<Void, Never>?
    var isRunning: Bool { token != nil }

    func invalidate() {
        token = nil
        task?.cancel()
        task = nil
    }

    func start(operation: @escaping @MainActor () async throws -> RecipeCard,
               apply: @escaping @MainActor (RecipeCard) throws -> Void,
               failed: @escaping @MainActor (Error) -> Void,
               finished: @escaping @MainActor () -> Void) {
        invalidate()
        let admitted = UUID()
        token = admitted
        task = Task { @MainActor [weak self] in
            defer {
                if let self, self.token == admitted {
                    self.token = nil
                    self.task = nil
                    finished()
                }
            }
            do {
                let result = try await operation()
                guard let self, self.token == admitted, !Task.isCancelled else { return }
                // Synchronous MainActor apply cannot interleave with discard.
                try apply(result)
            } catch {
                guard let self, self.token == admitted, !Task.isCancelled else { return }
                failed(error)
            }
        }
    }
}
