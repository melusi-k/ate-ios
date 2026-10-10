import XCTest
@testable import Ate

@MainActor
final class SharedInboxTests: XCTestCase {
    func testQueueIsFIFOAndCapped() {
        let d = UserDefaults(suiteName: "inbox-test-\(UUID())")!
        XCTAssertNil(SharedInbox.pop(d))
        for i in 0..<25 { SharedInbox.push(.init(url: "https://x.test/\(i)"), d) }
        XCTAssertEqual(SharedInbox.load(d).count, 20)
        XCTAssertEqual(SharedInbox.pop(d)?.url, "https://x.test/5")
        XCTAssertEqual(SharedInbox.load(d).count, 19)
    }
    func testFirstURLInCaption() {
        XCTAssertEqual(SharedInbox.firstURL(in: "omg try this 🍝 https://www.tiktok.com/@chef/video/123 #pasta"),
                       "https://www.tiktok.com/@chef/video/123")
        XCTAssertNil(SharedInbox.firstURL(in: "no links here"))
    }
    func testImportDeepLinkPicksUpInbox() {
        let store = AppStore(context: nil, backend: MockBackend())
        SharedInbox.save([])
        SharedInbox.push(.init(url: "https://example.com/soup"))
        store.tab = .settings
        store.handle(url: URL(string: "ate://import")!)
        XCTAssertEqual(store.pendingImport?.url, "https://example.com/soup")
        XCTAssertEqual(store.tab, .library)
    }
    func testDeepLinksSelectTabs() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.tab = .shopping
        store.handle(url: URL(string: "ate://recipe/abc")!)
        XCTAssertEqual(store.tab, .library)
        XCTAssertEqual(store.path, [.shared("abc")])
    }
}
