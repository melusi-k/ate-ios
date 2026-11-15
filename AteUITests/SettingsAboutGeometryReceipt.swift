#if DEBUG
import XCTest

/// At most two receipts in the existing journey. No extra scroll, tap or wait.
/// The first failed geometry check is followed by the next check after its swipe.
struct SettingsAboutGeometryReceipt {
    private var phase = 0

    mutating func observe(visible: Bool, heading: XCUIElement, app: XCUIApplication) {
        guard phase < 2, phase > 0 || !visible else { return }
        let checkpoint = phase == 0 ? "first-failed-check" : "after-scroll-check"
        phase += 1
        func geometry(_ element: XCUIElement) -> String {
            guard element.exists else { return "missing" }
            return String(describing: element.frame)
        }
        let window = app.windows.firstMatch
        let navigation = app.navigationBars["Settings"]
        let tabs = app.tabBars.firstMatch
        let accessory = app.descendants(matching: .any)["bottomAccessory"].firstMatch
        print("SETTINGS-ABOUT-GEOMETRY \(checkpoint) visible=\(visible) heading=\(heading.identifier) row=\(geometry(heading)) window=\(geometry(window)) nav=\(geometry(navigation)) tab=\(geometry(tabs)) accessory=\(geometry(accessory))")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "settings-about-geometry-" + checkpoint
        screenshot.lifetime = .keepAlways
        XCTContext.runActivity(named: "settings-about-geometry-" + checkpoint) { $0.add(screenshot) }
    }
}
#endif
