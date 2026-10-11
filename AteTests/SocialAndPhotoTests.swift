import XCTest
@testable import Ate

/// Fixtures captured from real link-preview responses (trimmed).
enum SocialFixtures {
    static let instagramReelHTML = """
    <html><head><meta property="og:title" content="Chef Thandi on Instagram: &quot;Creamy chakalaka pasta 🍝&quot;" />
    <meta property="og:description" content="12K likes, 340 comments - chef.thandi on March 3, 2026: &quot;Creamy chakalaka pasta 🍝 You need 250g penne, 1 onion, 2 cloves garlic, 1 tin chakalaka, 125ml cream and parmesan. Fry the onion 5 min, add chakalaka, simmer 10 min, stir in cream and pasta.&quot;" />
    <meta name="description" content="ignored"></head><body></body></html>
    """
    static let instagramLoginWallHTML = """
    <html><head><meta property="og:title" content="Instagram" /><meta property="og:description" content="Log in" /></head></html>
    """
    static let tiktokOEmbed: [String: Any] = [
        "title": "15-min garlic butter noodles 🧄 200g noodles, 3 tbsp butter, 4 garlic cloves, soy sauce, spring onion. Boil noodles 4 min, melt butter, fry garlic 1 min, toss everything #easyrecipe",
        "author_name": "noodlequeen",
    ]
    static let youtubeHTML = """
    <meta name="description" content="Full recipe below!"><meta property="og:title" content="The BEST Bobotie | Mzansi Kitchen">
    <meta property='og:description' content='Ingredients: 500g beef mince, 2 onions, 2 slices bread, 250ml milk, 2 eggs, 2 tbsp curry powder, 3 tbsp chutney. Bake at 180C for 45 minutes.'>
    """
}

final class SocialLinkTests: XCTestCase {
    func testPlatformDetection() {
        XCTAssertEqual(SocialLinks.platform(of: URL(string: "https://www.instagram.com/reel/CzFazvjsq8M/?mdxt=abc")!), .instagram)
        XCTAssertEqual(SocialLinks.platform(of: URL(string: "https://vm.tiktok.com/ZMabc/")!), .tiktok)
        XCTAssertEqual(SocialLinks.platform(of: URL(string: "https://youtu.be/dQw4w9WgXcQ?si=xyz")!), .youtube)
        XCTAssertEqual(SocialLinks.platform(of: URL(string: "https://m.youtube.com/watch?v=abc")!), .youtube)
        XCTAssertNil(SocialLinks.platform(of: URL(string: "https://www.bbcgoodfood.com/recipes/x")!))
    }

    func testStripsTrackingParams() {
        XCTAssertEqual(SocialLinks.clean(URL(string: "https://www.instagram.com/reel/CzFazvjsq8M/?mdxt=abc&igsh=MXg2&utm_source=ig_web")!).absoluteString,
                       "https://www.instagram.com/reel/CzFazvjsq8M/")
        XCTAssertEqual(SocialLinks.clean(URL(string: "https://www.youtube.com/watch?v=abc123&si=TRACK&feature=share&t=42")!).absoluteString,
                       "https://www.youtube.com/watch?v=abc123&t=42")
        XCTAssertEqual(SocialLinks.clean(URL(string: "https://www.tiktok.com/@a/video/1?is_from_webapp=1&sender_device=pc&lang=en")!).absoluteString,
                       "https://www.tiktok.com/@a/video/1?lang=en")
    }

    func testOEmbedEndpoints() {
        XCTAssertTrue(SocialLinks.oEmbedURL(for: URL(string: "https://www.tiktok.com/@a/video/1")!)!.absoluteString.hasPrefix("https://www.tiktok.com/oembed?url=https%3A%2F%2F"))
        XCTAssertTrue(SocialLinks.oEmbedURL(for: URL(string: "https://youtu.be/x")!)!.absoluteString.contains("youtube.com/oembed?format=json"))
        XCTAssertNil(SocialLinks.oEmbedURL(for: URL(string: "https://www.instagram.com/reel/x/")!))
    }

    func testInstagramCaptionFromOG() {
        let c = SocialLinks.caption(platform: .instagram, oEmbed: nil, meta: SocialLinks.meta(SocialFixtures.instagramReelHTML))
        XCTAssertTrue(c.contains("250g penne"), c)
        XCTAssertFalse(c.contains("12K likes"), "likes/comments prefix stripped: \(c)")
        XCTAssertTrue(SocialLinks.isUseful(c))
    }

    func testLoginWallIsNotACaption() {
        let c = SocialLinks.caption(platform: .instagram, oEmbed: nil, meta: SocialLinks.meta(SocialFixtures.instagramLoginWallHTML))
        XCTAssertFalse(SocialLinks.isUseful(c))
        XCTAssertEqual(SocialCaptionError(platform: .instagram).localizedDescription,
                       "Instagram didn't share the caption — paste the caption text into Prompt instead")
    }

    func testTikTokOEmbedAndYouTubeDescription() {
        let t = SocialLinks.caption(platform: .tiktok, oEmbed: SocialFixtures.tiktokOEmbed, meta: [:])
        XCTAssertTrue(SocialLinks.isUseful(t)); XCTAssertTrue(t.contains("garlic"))
        let m = SocialLinks.meta(SocialFixtures.youtubeHTML)
        XCTAssertEqual(m["og:title"], "The BEST Bobotie | Mzansi Kitchen")
        let y = SocialLinks.caption(platform: .youtube, oEmbed: ["title": "The BEST Bobotie | Mzansi Kitchen"], meta: m)
        XCTAssertTrue(y.contains("500g beef mince")); XCTAssertEqual(y.components(separatedBy: "Bobotie").count, 2, "title not duplicated")
    }

    func testEntityDecoding() {
        XCTAssertEqual(SocialLinks.decodeEntities("Mac &amp; cheese &#x1F9C0; &#39;yum&#39;"), "Mac & cheese 🧀 'yum'")
    }
}

final class PhotoGuessTests: XCTestCase {
    func testScreenshotVsPhoto() {
        XCTAssertTrue(PhotoGuess.isScreenshotText("Ingredients\n2 cups flour\n1 tsp salt\n3 eggs\nMix and bake for 20 minutes at 180C until golden"))
        XCTAssertFalse(PhotoGuess.isScreenshotText(""))
        XCTAssertFalse(PhotoGuess.isScreenshotText("NANDO'S"))
    }
    func testDishPromptFromLabels() {
        let labels: [(String, Float)] = [("food", 0.9), ("pizza", 0.7), ("plate", 0.6), ("cheese", 0.3)]
        XCTAssertEqual(PhotoGuess.dishes(from: labels), ["pizza", "cheese"])
        let p = PhotoGuess.prompt(labels: labels, ocrText: "")!
        XCTAssertTrue(p.contains("pizza, cheese"))
        XCTAssertEqual(RecipeSource.photoGuess.badge, "Guessed from photo")
    }
    func testNoFoodMeansNoGuess() {
        XCTAssertNil(PhotoGuess.prompt(labels: [("plate", 0.8), ("table", 0.5)], ocrText: ""))
        XCTAssertNil(PhotoGuess.prompt(labels: [], ocrText: ""))
    }
    func testObjectsCannotBecomeDishCandidates() {
        let labels: [(String, Float)] = [("food", 0.95), ("wooden_utensil", 0.95), ("plate", 0.82), ("tableware", 0.7)]
        XCTAssertTrue(PhotoGuess.dishes(from: labels).isEmpty)
        guard case .uncertain = PhotoGuess.assess(labels: labels, ocrText: "") else {
            return XCTFail("an object-only recognition must ask the user rather than generate")
        }
        XCTAssertTrue(PhotoGuess.isNonDishObject("wooden utensil"))
    }
}
