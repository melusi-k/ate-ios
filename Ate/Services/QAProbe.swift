import Foundation
import Observation

/// Test-only counters for side effects XCUITest can't observe directly
/// (Live Activity requests, chime, finish haptic). Shown as an `qa.probe` label in UI-testing builds.
@MainActor @Observable
final class QAProbe {
    static let shared = QAProbe()
    var liveActivityRequests = 0
    var chimes = 0
    var finishHaptics = 0
    var summary: String { "la=\(liveActivityRequests) chime=\(chimes) haptic=\(finishHaptics)" }
}

extension AppConfig {
    /// `-qaFastTimers`: step timers run 30× faster (min 2 s) so QA can watch one finish.
    static var qaFastTimers: Bool { isUITesting && ProcessInfo.processInfo.arguments.contains("-qaFastTimers") }
    /// `-qaPersistServer`: the mock sync server survives relaunches (second-launch pull test).
    static var qaPersistServer: Bool { isUITesting && ProcessInfo.processInfo.arguments.contains("-qaPersistServer") }
}
