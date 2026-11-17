import Foundation

/// Fixed process-local stages only. No user data, notification/recipe identifiers,
/// persistent files or telemetry. Not observable and never drives presentation.
@MainActor
enum CookPlanCancelDiagnostic {
    enum Stage: String {
        case queueWait, queueAdmitted, queueReturned
        case removeBegin, removeReturned, verifyBegin, verifyReturned
        case cancelEntered, localDeleteReturned, cancelOSReturned, cancelFailed, dismissRequested
    }
    private static var rows: [String] = []
    static let maximumEntries = 32
    static func record(_ stage: Stage) {
        let row = "\(stage.rawValue):\(Int(ProcessInfo.processInfo.systemUptime * 1000))"
        rows.append(row)
        if rows.count > maximumEntries { rows.removeFirst(rows.count - maximumEntries) }
        NSLog("ATE-COOK-CANCEL %@", row)
    }
    static var summary: String { rows.joined(separator: ",") }
}
