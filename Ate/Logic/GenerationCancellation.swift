import Foundation

/// Cancellation is an interrupted attempt, never a decoding error or a usable
/// partial result. Optional quality repair may keep the first card on ordinary
/// repair failure, but must not turn a cancelled attempt into success.
enum GenerationCancellation {
    static func check(_ error: Error? = nil) throws {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
    }

    static func optionalRepair<T>(original: T, operation: () async throws -> T,
                                  prefer: (T, T) -> Bool) async throws -> T {
        try check()
        do {
            let repaired = try await operation()
            try check()
            return prefer(repaired, original) ? repaired : original
        } catch {
            try check(error)
            return original
        }
    }
}
