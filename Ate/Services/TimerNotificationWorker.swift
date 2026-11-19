import Foundation
import UserNotifications

/// Serial submission to the notification daemon, away from the caller's thread.
/// An add completes before the next cancel or clear is sent. The worker never
/// holds the account writer gate while a system service is unresponsive.
final class TimerNotificationWorker {
    typealias Completion = () -> Void
    typealias Operation = (@escaping Completion) -> Void
    private let queue = DispatchQueue(label: "ate.timer-notifications", qos: .userInitiated)
    private var pending: [Operation] = []
    private var running: UUID?
    private let remove: (String) -> Void
    private let add: (UNNotificationRequest, @escaping Completion) -> Void
    private let clearAndVerify: (@escaping (Bool) -> Void) -> Void

    init(remove: @escaping (String) -> Void,
         add: @escaping (UNNotificationRequest, @escaping Completion) -> Void,
         clearAndVerify: @escaping (@escaping (Bool) -> Void) -> Void) {
        self.remove = remove
        self.add = add
        self.clearAndVerify = clearAndVerify
    }

    /// Called within TimerCenter's existing synchronous writer boundary. Admission
    /// is ordered here, but daemon IPC runs only on this worker, without that lock.
    func replace(identifier: String, request: (() -> UNNotificationRequest)?) {
        submit { done in
            self.remove(identifier)
            guard let request else { done(); return }
            self.add(request(), done)
        }
    }

    func cancel(identifier: String) {
        replace(identifier: identifier, request: nil)
    }

    /// The clear-all owner holds its reset gate while awaiting this barrier. Every
    /// previously admitted effect finishes first, then removal and real read-back.
    /// It cannot report success and leave an older queued schedule behind it.
    func removeAllAndVerify() async -> Bool {
        await withCheckedContinuation { continuation in
            removeAllAndVerify { continuation.resume(returning: $0) }
        }
    }

    func removeAllAndVerify(completion: @escaping (Bool) -> Void) {
        submit { done in
            self.clearAndVerify { verified in
                completion(verified)
                done()
            }
        }
    }

    private func submit(_ operation: @escaping Operation) {
        queue.async {
            self.pending.append(operation)
            self.startNext()
        }
    }

    private func startNext() {
        guard running == nil, !pending.isEmpty else { return }
        let token = UUID()
        running = token
        let operation = pending.removeFirst()
        operation {
            self.queue.async {
                guard self.running == token else { return }
                self.running = nil
                self.startNext()
            }
        }
    }
}
