#if DEBUG
import XCTest

/// Bounded to two call sites in one return journey. No extra action or wait.
/// Capture before the potentially blocking query, then only if it returns.
enum ReturnBoundaryReceipt {
    static func capture(_ app: XCUIApplication, phase: String) {
        print("RETURN-BOUNDARY-RECEIPT " + phase)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "return-boundary-" + phase
        screenshot.lifetime = .keepAlways
        XCTContext.runActivity(named: "return-boundary-" + phase) { activity in
            activity.add(screenshot)
            let hierarchy = app.debugDescription
            print(hierarchy)
            let frames = XCTAttachment(string: hierarchy)
            frames.name = "return-boundary-frames-" + phase
            frames.lifetime = .keepAlways
            activity.add(frames)
        }
    }
}
#endif
