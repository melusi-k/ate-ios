import Foundation

/// Bounds a system callback that may never arrive after XPC service loss. A task
/// group race would still await its noncooperative child on scope exit. Instead,
/// exactly one callback/deadline/cancellation resumes the continuation; late or
/// duplicate callbacks cannot change the reported outcome. No service success is
/// fabricated, and cancelling the wait does not claim to cancel the OS operation.
final class SystemCleanupCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var completion: (@Sendable (Bool) -> Void)?

    private func install(_ completion: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        if let result {
            lock.unlock()
            completion(result)
        } else {
            self.completion = completion
            lock.unlock()
        }
    }

    func finish(_ value: Bool) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(value)
    }

    static func wait(timeout: TimeInterval,
                     start: (@escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        guard timeout.isFinite, timeout > 0 else { return false }
        let terminal = SystemCleanupCompletion()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                terminal.install { continuation.resume(returning: $0) }
                if Task.isCancelled { terminal.finish(false); return }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    terminal.finish(false)
                }
                start { terminal.finish($0) }
            }
        }, onCancel: {
            terminal.finish(false)
        })
    }
}
