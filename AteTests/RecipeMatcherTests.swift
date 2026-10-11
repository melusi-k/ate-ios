import XCTest
@testable import Ate

@MainActor
final class RecipeMatcherTests: XCTestCase {
    let lib = [RecipeCard(id: "nyama", title: "Nyama yenkomo with pap and chakalaka"),
               RecipeCard(id: "mog", title: "Mogodu"),
               RecipeCard(id: "chak", title: "Chakalaka")]

    func testMisspellingMatchesMogodu() {
        let hits = RecipeMatcher.rank(lib, query: "Mugod")
        XCTAssertEqual(hits.first?.recipe.id, "mog")
        XCTAssertFalse(hits.contains { $0.recipe.id == "nyama" })
    }
    func testPrefixAndContains() {
        XCTAssertEqual(RecipeMatcher.rank(lib, query: "mogo").first?.recipe.id, "mog")
        XCTAssertTrue(RecipeMatcher.isConfident(RecipeMatcher.rank(lib, query: "Mogodu")))
    }
    func testUnrelatedReturnsNothing() {
        XCTAssertTrue(RecipeMatcher.rank(lib, query: "lasagne").isEmpty)
    }
    func testQueryNeverPicksUnrelated() async throws {
        let s = AppStore(context: nil, backend: MockBackend()); s.recipes = lib
        let r = try await RecipeEntityQuery().entities(matching: "Mugod")
        XCTAssertEqual(r.map(\.id), ["mog"])
        let none = try await RecipeEntityQuery().entities(matching: "lasagne")
        XCTAssertTrue(none.isEmpty)
    }
    func testIntentSaysNoMatch() async throws {
        let s = AppStore(context: nil, backend: MockBackend()); s.recipes = lib
        QAProbe.shared.lastIntent = "none"
        _ = try await StartCookModeIntent(name: "lasagne").perform()
        XCTAssertNotEqual(QAProbe.shared.lastIntent, "cook")
    }
}
