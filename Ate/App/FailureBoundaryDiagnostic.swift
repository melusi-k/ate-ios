#if DEBUG
import SwiftUI
import Observation

/// Numeric, process-local receipt rings, enabled only by each specific UI-test flag.
/// They report boundaries, not successful cancellation, focus or keyboard ownership.
@MainActor @Observable final class FailureBoundaryDiagnostic {
    static let shared = FailureBoundaryDiagnostic()
    enum Surface { case keyboard, cookPlan }
    private var keyboardRows: [String] = []
    private var cookPlanRows: [String] = []
    static func enabled(_ surface: Surface) -> Bool {
        let flag = surface == .keyboard ? "-qaDiaryKeyboardDiagnostic" : "-qaCookPlanCancelDiagnostic"
        return AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains(flag)
    }
    static func record(_ surface: Surface, _ phase: Int, _ first: Int = 0, _ second: Int = 0) {
        guard enabled(surface) else { return }
        let ring = shared
        let count = surface == .keyboard ? ring.keyboardRows.count : ring.cookPlanRows.count
        guard count < 32 else { return }
        let row = "event=\(count + 1) phase=\(phase) uptime=\(ProcessInfo.processInfo.systemUptime) first=\(first) second=\(second)"
        if surface == .keyboard { ring.keyboardRows.append(row) }
        else { ring.cookPlanRows.append(row) }
    }
    func receipt(_ surface: Surface) -> String {
        let rows = surface == .keyboard ? keyboardRows : cookPlanRows
        return "pid=\(ProcessInfo.processInfo.processIdentifier) rows=\(rows.count)|" + rows.joined(separator: "|")
    }
}

/// Reuses an existing button's value. No new controls, input, storage or timers.
struct FailureBoundaryReceipt: ViewModifier {
    let surface: FailureBoundaryDiagnostic.Surface
    func body(content: Content) -> some View {
        if FailureBoundaryDiagnostic.enabled(surface) {
            if surface == .keyboard {
                content.accessibilityValue(FailureBoundaryDiagnostic.shared.receipt(surface))
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        FailureBoundaryDiagnostic.record(.keyboard, 12, 1)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        FailureBoundaryDiagnostic.record(.keyboard, 12, 2)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        FailureBoundaryDiagnostic.record(.keyboard, 12, 3)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                        FailureBoundaryDiagnostic.record(.keyboard, 12, 4)
                    }
            } else {
                content.accessibilityValue(FailureBoundaryDiagnostic.shared.receipt(surface))
            }
        } else { content }
    }
}
#endif
