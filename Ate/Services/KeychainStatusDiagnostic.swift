import Foundation
import Security

/// Real Security-call results only. Never receives queries, values, identifiers,
/// entitlement contents or credentials. Bounded, process-local and not telemetry.
final class KeychainStatusDiagnostic: @unchecked Sendable {
    enum Operation: String { case update, add, delete, read }
    static let shared = KeychainStatusDiagnostic()
    static let maximumEntries = 24
    private let lock = NSLock()
    private var rows: [(Operation, OSStatus)] = []

    /// Invokes the real operation exactly once, returns its unchanged status.
    @discardableResult
    func capture(_ operation: Operation, _ work: () -> OSStatus) -> OSStatus {
        let status = work()
        lock.lock()
        rows.append((operation, status))
        if rows.count > Self.maximumEntries { rows.removeFirst(rows.count - Self.maximumEntries) }
        lock.unlock()
        // Numeric status and a fixed operation token only, including successes
        // and item-not-found so update->add paths can be distinguished.
        NSLog("ATE-KEYCHAIN operation=%@ status=%d", operation.rawValue, status)
        return status
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        return rows.map { "\($0.0.rawValue):\($0.1)" }.joined(separator: ",")
    }
}

/// Fixed cleanup stages only, no row identifiers, text, counts or notification IDs.
/// Not observable: receipts must not drive presentation or reschedule the cleanup.
@MainActor
enum CleanupPhaseDiagnostic {
    enum Stage: String {
        case clearConfirmed, clearEntered, clearRefused, clearPlansBegin, clearPlansReturned, clearPlansFailed
        case clearEraseBegin, clearEraseReturned, clearFailed
        case planStoreClearBegin, planStoreClearReturned
        case cancelEntered, cancelLocalReturned, cancelOSReturned, cancelFailed, cancelDismiss
        case singleRemoveBegin, singleRemoveReturned, singleVerifyBegin, singleVerifyReturned
        case allPendingBegin, allPendingReturned, allRemoveBegin, allRemoveReturned
        case allDeliveredBegin, allDeliveredReturned, allVerifyBegin, allVerifyReturned
    }
    private static var rows: [String] = []
    static let maximumEntries = 48
    static func record(_ stage: Stage) {
        let row = "\(stage.rawValue):\(Int(ProcessInfo.processInfo.systemUptime * 1000))"
        rows.append(row)
        if rows.count > maximumEntries { rows.removeFirst(rows.count - maximumEntries) }
        NSLog("ATE-CLEANUP %@", row)
    }
    static var summary: String { rows.joined(separator: ",") }
}
