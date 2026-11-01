import XCTest
import SwiftUI
import UIKit
@testable import Ate

/// #245: the Food Journal must be easy to find inside the existing navigation (no tab-bar
/// addition). These render the actual Insights destination link and verify the visible wording,
/// the stable identifier, and that discovery never depends on entry count. Snapshots are attached
/// and exported to the log in base64 chunks for CI review.
@MainActor
final class JournalDiscoveryTests: XCTestCase {
    private var window: UIWindow!

    override func setUpWithError() throws {
        try super.setUpWithError()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
    }
    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    @discardableResult
    private func render<V: View>(_ root: V, name: String, height: CGFloat = 120,
                                 file: StaticString = #filePath, line: UInt = #line) -> UIView {
        let host = UIHostingController(rootView: root)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        host.view.backgroundColor = .white
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let image = renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let png = image.pngData() else {
            XCTFail("snapshot encoding failed", file: file, line: line)
            return host.view
        }
        let b64 = png.base64EncodedString()
        print("SNAPSHOT-BEGIN \(name) \(b64.count)")
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 4000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("SNAPSHOT-CHUNK \(name) \(b64[i..<j])")
            i = j
        }
        print("SNAPSHOT-END \(name)")
        return host.view
    }

    private func accessibilityPairs(in view: UIView) -> [(id: String?, label: String?)] {
        var out: [(String?, String?)] = []
        func walk(_ v: UIView) {
            if v.isAccessibilityElement || v.accessibilityIdentifier != nil {
                out.append((v.accessibilityIdentifier, v.accessibilityLabel))
            }
            for element in (v.accessibilityElements ?? []) {
                if let view = element as? UIView {
                    out.append((view.accessibilityIdentifier, view.accessibilityLabel))
                    continue
                }
                guard let o = element as? NSObject else { continue }
                // The Xcode 27 SDK exposes the informal accessibility properties only on
                // concrete classes, so prove selector support before reading via KVC;
                // an unsupported key must never become an undefined-key exception.
                let id = o.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    ? o.value(forKey: "accessibilityIdentifier") as? String : nil
                let label = o.responds(to: NSSelectorFromString("accessibilityLabel"))
                    ? o.value(forKey: "accessibilityLabel") as? String : nil
                out.append((id, label))
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return out
    }

    /// Zero entries: the door into the journal still renders, worded as an open invitation.
    /// Before this change the Insights card offered no way into the Journal at all here.
    func testDestinationLinkRendersWithNoEntries() {
        let view = render(NavigationStack { FoodJournalDestinationLink(entryCount: 0) },
                          name: "discover-empty")
        let pairs = accessibilityPairs(in: view)
        XCTAssertTrue(pairs.contains { $0.id == "insights.openFoodJournal" }, "destination must be exposed: \(pairs)")
        let allText = pairs.compactMap(\.label).joined(separator: " | ")
        XCTAssertTrue(allText.contains("Open Food Journal"), allText)
    }

    /// With entries, the same door reads as the full-history link.
    func testDestinationLinkRendersWithEntries() {
        let view = render(NavigationStack { FoodJournalDestinationLink(entryCount: 7) },
                          name: "discover-entries")
        let pairs = accessibilityPairs(in: view)
        XCTAssertTrue(pairs.contains { $0.id == "insights.openFoodJournal" }, "destination must be exposed: \(pairs)")
        let allText = pairs.compactMap(\.label).joined(separator: " | ")
        XCTAssertTrue(allText.contains("See all 7 entries"), allText)
    }
}
