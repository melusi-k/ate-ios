import XCTest
@testable import Ate

final class SharedInboxPathTests: XCTestCase {
    func testOnlyGeneratedImageNamesResolveInsideInbox() {
        let root = URL(fileURLWithPath: "/tmp/ate-inbox", isDirectory: true)
        XCTAssertEqual(SharedInbox.safeImageURL("123E4567-E89B-12D3-A456-426614174000.jpg", in: root)?.deletingLastPathComponent(), root.standardizedFileURL)
        XCTAssertNil(SharedInbox.safeImageURL("../outside.jpg", in: root))
        XCTAssertNil(SharedInbox.safeImageURL("subdir/123E4567-E89B-12D3-A456-426614174000.jpg", in: root))
        XCTAssertNil(SharedInbox.safeImageURL("123E4567-E89B-12D3-A456-426614174000.png", in: root))
        XCTAssertNil(SharedInbox.safeImageURL("", in: root))
    }
}