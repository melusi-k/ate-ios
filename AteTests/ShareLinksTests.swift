import XCTest
@testable import Ate

final class ShareLinksTests: XCTestCase {
    func testBuildsQueryFormLink() {
        XCTAssertEqual(ShareLinks.url(slug: "abc123"), "https://melusi-k.github.io/ate-legal/r/?s=abc123")
        XCTAssertEqual(ShareLinks.url(slug: "x", template: "https://ate.app/r/{slug}"), "https://ate.app/r/x")
        XCTAssertEqual(ShareLinks.url(slug: "x", template: "no placeholder"), "https://melusi-k.github.io/ate-legal/r/?s=x")
        XCTAssertTrue(AppConfig.shareURL(slug: "q").hasSuffix("?s=q"))
    }

    func testParsesAllIncomingForms() {
        let cases: [(String, String?)] = [
            ("https://melusi-k.github.io/ate-legal/r/?s=abc123", "abc123"),
            ("https://melusi-k.github.io/ate-legal/r/abc123", "abc123"),
            ("https://recipe-transform-ai.lovable.app/r/abc123", "abc123"),
            ("https://ate.app/recipe/abc123", "abc123"),
            ("ate://recipe/abc123", "abc123"),
            ("ate://r/abc123", "abc123"),
            ("https://melusi-k.github.io/ate-legal/privacy.html", nil),
            ("https://melusi-k.github.io/ate-legal/r/", nil),
        ]
        for (s, want) in cases { XCTAssertEqual(ShareLinks.slug(from: URL(string: s)!), want, s) }
    }

    func testShareTextContainsNewLinkOnce() {
        let link = ShareLinks.url(slug: "abc")
        let t = RecipeLogic.text(for: RecipeCard(title: "Pap"), shareURL: link)
        XCTAssertEqual(t.components(separatedBy: link).count, 2)
    }
}
