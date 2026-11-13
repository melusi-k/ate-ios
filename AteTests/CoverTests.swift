import XCTest
@testable import Ate

final class CoverTests: XCTestCase {
    func testSourcePriority() {
        XCTAssertEqual(CoverLogic.pick(userPhoto: true, pageImage: true, generated: true), .userPhoto)
        XCTAssertEqual(CoverLogic.pick(userPhoto: false, pageImage: true, generated: true), .pageImage)
        XCTAssertEqual(CoverLogic.pick(userPhoto: false, pageImage: false, generated: true), .generated)
        XCTAssertEqual(CoverLogic.pick(userPhoto: false, pageImage: false, generated: false), .tile)
        XCTAssertTrue(CoverLogic.Source.userPhoto < .pageImage && CoverLogic.Source.generated < .tile)
    }

    func testFileNameRoundTrip() {
        let n = CoverLogic.fileName(for: "AB-12/..", source: .generated)
        XCTAssertEqual(n, "cover-AB-12-2.jpg")
        XCTAssertEqual(CoverLogic.source(ofFile: n), .generated)
        XCTAssertNil(CoverLogic.source(ofFile: "none"))
    }

    func testOGImageParser() {
        let html = #"<head><meta content="https://ex.com/a&amp;b.jpg" property="og:image"><meta name="twitter:image" content="https://ex.com/t.jpg"></head>"#
        XCTAssertEqual(CoverLogic.pageImage(fromHTML: html)?.absoluteString, "https://ex.com/a&b.jpg")
        let rel = #"<meta property='og:image' content='/img/c.jpg'>"#
        XCTAssertEqual(CoverLogic.pageImage(fromHTML: rel, baseURL: URL(string: "https://site.com/r/1"))?.absoluteString, "https://site.com/img/c.jpg")
        XCTAssertNil(CoverLogic.pageImage(fromHTML: #"<meta property="og:image" content="http://insecure.com/x.jpg">"#))
        let tw = #"<meta property="og:image" content="http://x.com/a.jpg"><meta name="twitter:image" content="https://ex.com/t.jpg">"#
        XCTAssertEqual(CoverLogic.pageImage(fromHTML: tw)?.absoluteString, "https://ex.com/t.jpg")
    }

    func testJSONLDImageFallback() {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"Bread","image":["https://ex.com/b.jpg"],
        "recipeIngredient":["flour"],"recipeInstructions":["Bake"]}</script>
        """
        XCTAssertEqual(CoverLogic.pageImage(fromHTML: html)?.absoluteString, "https://ex.com/b.jpg")
    }

    func testOEmbedThumbnail() {
        XCTAssertEqual(CoverLogic.oEmbedThumbnail(["thumbnail_url": "https://i.ytimg.com/vi/x/hq.jpg"])?.host, "i.ytimg.com")
        XCTAssertNil(CoverLogic.oEmbedThumbnail(["title": "x"]))
    }

    func testTileDeterminism() {
        let a = CoverLogic.tile(title: "Mogodu stew", cuisine: "South African", ingredients: ["tripe", "onion"])
        let b = CoverLogic.tile(title: "Mogodu stew", cuisine: "South African", ingredients: ["tripe", "onion"])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.initial, "M")
        XCTAssertEqual(a.symbol, "frying.pan", "a stew is a stew first")
        XCTAssertTrue(CoverLogic.palettes.indices.contains(a.palette))
        XCTAssertEqual(CoverLogic.tile(title: "  ujeqe", cuisine: nil, ingredients: []).initial, "U")
        XCTAssertEqual(CoverLogic.stableHash("ate"), CoverLogic.stableHash("ate"))
        let fish = CoverLogic.tile(title: "Pan-fried hake", cuisine: nil, ingredients: [])
        XCTAssertEqual(fish.symbol, "fish")
    }

    func testCrop43() {
        let wide = CoverLogic.crop43(width: 1600, height: 900)
        XCTAssertEqual(wide.w / wide.h, 4.0 / 3.0, accuracy: 0.001); XCTAssertEqual(wide.y, 0)
        let tall = CoverLogic.crop43(width: 900, height: 1600)
        XCTAssertEqual(tall.w / tall.h, 4.0 / 3.0, accuracy: 0.001); XCTAssertEqual(tall.x, 0)
    }

    func testConcept() {
        XCTAssertEqual(CoverLogic.concept(title: "Chakalaka", ingredients: ["beans", "carrot", "pepper", "onion"]),
                       "Chakalaka with beans, carrot, pepper, plated food")
    }

    func testRecipeCoverDecodes() throws {
        let c = try JSONDecoder().decode(RecipeCard.self, from: Data(#"{"title":"x","coverImage":"cover-1-0.jpg"}"#.utf8))
        XCTAssertEqual(c.coverImage, "cover-1-0.jpg")
    }
}

@MainActor
final class CoverWriterCaptureTests: XCTestCase {
    private enum Stale: Error { case epoch }

    func testRetainedCaptureNeverUsesReboundSingletonAuthorityAfterAwait() async throws {
        let covers = CoverStore()
        var current = true, oldEffects = 0, replacementEffects = 0
        covers.writerBoundary = FoodJournalWriterBoundary { work in oldEffects += 1; try work() }
        covers.validateWriter = { if !current { throw Stale.epoch } }
        let captured = covers.captureWriter()
        try captured.withEffect {}
        XCTAssertEqual(oldEffects, 1)
        await Task.yield()
        current = false
        covers.writerBoundary = FoodJournalWriterBoundary { work in replacementEffects += 1; try work() }
        covers.validateWriter = {}
        XCTAssertThrowsError(try captured.withEffect { XCTFail("old operation published under replacement graph") })
        XCTAssertEqual(oldEffects, 1)
        XCTAssertEqual(replacementEffects, 0)
        try covers.captureWriter().withEffect {}
        XCTAssertEqual(replacementEffects, 1, "new work is distinct from retained old work")
    }

    func testRefusedGenerateDoesNotWriteAttemptMarkerOrInvokeGenerator() async {
        let covers = CoverStore()
        let recipe = RecipeCard(title: "Synthetic capture")
        let key = "ate.cover.gen.\(recipe.id)"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        covers.writerBoundary = FoodJournalWriterBoundary { _ in throw Stale.epoch }
        let result = await covers.generate(for: recipe)
        XCTAssertNil(result)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }
}
