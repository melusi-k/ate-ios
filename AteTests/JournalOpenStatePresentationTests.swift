import XCTest
import SwiftUI
import UIKit
@testable import Ate

/// #245 phase 3: the journal open-state banner is user-visible, so these render every state for
/// real (UIHostingController in a key window) and verify the actual wording in the accessibility
/// tree, plus a rendered snapshot per state. Snapshots are attached to the test result and also
/// exported to the log in base64 chunks so the CI run's pixels are reviewable without xcresulttool.
@MainActor
final class JournalOpenStatePresentationTests: XCTestCase {
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
    private func render<V: View>(_ root: V, name: String, height: CGFloat = 220,
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
                if let o = element as? NSObject {
                    let id = (o as? UIAccessibilityIdentification)?.accessibilityIdentifier
                    let label = (o as? UIAccessibility)?.accessibilityLabel
                    out.append((id, label))
                }
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return out
    }

    func testRecoveredBannerRendersExplanationAndBackupName() {
        let view = render(JournalOpenStateBanner(state: .recovered(backupName: "ate-20250101-120000.store")),
                          name: "banner-recovered")
        let pairs = accessibilityPairs(in: view)
        XCTAssertTrue(pairs.contains { $0.id == "journal.openStateBanner" }, "banner must be exposed: \(pairs)")
        let allText = pairs.compactMap(\.label).joined(separator: " | ")
        XCTAssertTrue(allText.contains("Journal recovered"), allText)
        XCTAssertTrue(allText.contains("ate-20250101-120000.store"), "the kept backup is named so it can be found: \(allText)")
    }

    func testInMemoryFallbackBannerRendersTemporaryWarning() {
        let view = render(JournalOpenStateBanner(state: .inMemoryFallback(error: "test")),
                          name: "banner-inmemory")
        let pairs = accessibilityPairs(in: view)
        XCTAssertTrue(pairs.contains { $0.id == "journal.openStateBanner" }, "banner must be exposed: \(pairs)")
        let allText = pairs.compactMap(\.label).joined(separator: " | ")
        XCTAssertTrue(allText.contains("temporary"), allText)
        XCTAssertTrue(allText.contains("disappear"), "the user must hear their saves will not last: \(allText)")
    }

    func testUnavailableBannerRendersHonestFailure() {
        let view = render(JournalOpenStateBanner(state: .unavailable(error: "test")),
                          name: "banner-unavailable")
        let pairs = accessibilityPairs(in: view)
        XCTAssertTrue(pairs.contains { $0.id == "journal.openStateBanner" }, "banner must be exposed: \(pairs)")
        let allText = pairs.compactMap(\.label).joined(separator: " | ")
        XCTAssertTrue(allText.contains("Journal unavailable"), allText)
    }

    func testHealthyStateRendersNoBanner() {
        let view = render(JournalOpenStateBanner(state: .ok), name: "banner-ok", height: 40)
        XCTAssertFalse(accessibilityPairs(in: view).contains { $0.id == "journal.openStateBanner" },
                       "a clean open presents nothing")
    }

    /// List level, forced recovered: banner visible, and the misleading "No journal entries yet"
    /// empty state is suppressed so a recovered-empty journal is never shown as real history.
    func testJournalListWithRecoveredStateShowsBannerNotEmptyState() {
        let view = render(NavigationStack { JournalListView(openStateOverride: .recovered(backupName: "ate-20250101-120000.store")) },
                          name: "journal-list-recovered", height: 600)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let pairs = accessibilityPairs(in: view)
        XCTAssertTrue(pairs.contains { $0.id == "journal.openStateBanner" }, "banner must render in the timeline: \(pairs)")
        let allText = pairs.compactMap(\.label).joined(separator: " | ")
        XCTAssertFalse(allText.contains("No journal entries yet"),
                       "recovered-empty journal must not present as the user's real history: \(allText)")
    }

    /// List level, healthy: no banner. The empty state may or may not show depending on suite
    /// order (other tests may have written to the shared store), so only the banner is asserted.
    func testJournalListHealthyShowsNoBanner() {
        guard JournalStore.shared.openState == .ok else {
            XCTFail("the test host journal should open cleanly, got \(JournalStore.shared.openState)")
            return
        }
        let view = render(NavigationStack { JournalListView() }, name: "journal-list-healthy", height: 600)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertFalse(accessibilityPairs(in: view).contains { $0.id == "journal.openStateBanner" },
                       "healthy timeline presents no banner")
    }
}
