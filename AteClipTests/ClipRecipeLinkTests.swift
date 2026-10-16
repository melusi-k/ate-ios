import XCTest
@testable import AteClip

final class ClipRecipeLinkTests: XCTestCase {
    func testParsesSupportedHTTPSForms() {
        let cases: [(String, String)] = [
            ("https://melusi-k.github.io/ate-legal/r/?s=abc12345", "abc12345"),
            ("https://ate.app/r/abc12345", "abc12345"),
            ("https://ate.app/recipe/abc12345", "abc12345"),
            ("https://example.com/r/?slug=Abcd1234", "Abcd1234")
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ClipRecipeLink.slug(from: URL(string: raw)!), expected, raw)
        }
    }

    func testRejectsInvalidLinksAndSlugs() {
        let cases = [
            "ate://recipe/abc12345",
            "https://ate.app/",
            "https://ate.app/r/",
            "https://ate.app/r/abc",
            "https://ate.app/r/invalid-slug",
            "https://ate.app/r/abc12345?slug=bad!"
        ]
        for raw in cases {
            XCTAssertNil(ClipRecipeLink.slug(from: URL(string: raw)!), raw)
        }
    }
}
