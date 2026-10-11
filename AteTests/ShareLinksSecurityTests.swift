import XCTest
@testable import Ate

final class ShareLinksSecurityTests: XCTestCase {
    func testRejectsMalformedSlugsFromQueryAndPath() {
        for raw in ["../../etc", "abc/def", "abc?x=y", "abc", String(repeating: "a", count: 41)] {
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            XCTAssertNil(ShareLinks.slug(from: URL(string: "https://ate.app/r/?s=\(encoded)")!), raw)
        }
        XCTAssertNil(ShareLinks.slug(from: URL(string: "ate://recipe/../../etc")!))
        XCTAssertNil(ShareLinks.slug(from: URL(string: "file:///r/abc12345")!))
        XCTAssertNil(ShareLinks.slug(from: URL(string: "ftp://ate.app/r/abc12345")!))
    }

    func testAcceptsEdgeFunctionSlugContract() {
        XCTAssertEqual(ShareLinks.slug(from: URL(string: "https://ate.app/r/abc12345")!), "abc12345")
        XCTAssertEqual(ShareLinks.slug(from: URL(string: "https://ate.app/r/?s=Z9a8b7c6")!), "Z9a8b7c6")
    }
}