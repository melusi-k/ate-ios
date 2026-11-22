import Foundation
import XCTest

/// Receipts for the named red journeys only. No app mutation, launch retry or wait tuning.
/// Emit a flushed line BEFORE a possibly blocking UI operation, so a watchdog has a last step.
final class NamedRedReceipt {
    let journey: String
    private var sequence = 0

    init(_ test: XCTestCase, _ journey: String) {
        self.journey = journey
    }

    private func emit(_ text: String) {
        let line = "UI-RED journey=\(journey) seq=\(sequence) uptime=\(ProcessInfo.processInfo.systemUptime) \(text)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    @discardableResult
    func step<T>(_ name: String, pixels: Bool = false, _ action: () -> T) -> T {
        sequence += 1
        emit("BEGIN step=\(name)")
        return XCTContext.runActivity(named: "\(journey): \(name)") { activity in
            if pixels {
                emit("BEFORE-SCREENSHOT step=\(name)")
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "\(journey)-\(sequence)-before-\(name)"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
                emit("AFTER-SCREENSHOT step=\(name)")
            }
            let result = action()
            emit("END step=\(name)")
            return result
        }
    }

    /// Diagnostic boundary only. Do not resolve an element again for logging:
    /// exists/frame/identifier/label can each start a blocking remote AX query.
    /// Callers may supply plain values they already captured for an assertion.
    /// The element argument remains for source compatibility; it is never read.
    func inspect(_ name: String, _: XCUIElement, capturedValues: String? = nil) {
        step("inspect-\(name)") {
            emit("ELEMENT name=\(name) capture=phase-only")
            if let capturedValues {
                emit("CAPTURED name=\(name) values=\(capturedValues)")
            }
        }
    }
}
