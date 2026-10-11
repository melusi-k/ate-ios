import XCTest
@testable import Ate

final class JournalTextGuardTests: XCTestCase {
    func testImagePromptsAreRejected() {
        XCTAssertTrue(JournalTextGuard.looksLikeImagePrompt("A top-down, highly detailed photograph of a bowl of mogodu on a wooden table"))
        XCTAssertTrue(JournalTextGuard.looksLikeImagePrompt("Photorealistic food photography, shallow depth of field, 4k"))
        XCTAssertTrue(JournalTextGuard.looksLikeImagePrompt("Mogodu with tripe, onions, plated food, highly detailed"))
    }
    func testRealEntriesAreKept() {
        XCTAssertFalse(JournalTextGuard.looksLikeImagePrompt("Cooked mogodu with Mama tonight, felt great after the long walk."))
        XCTAssertFalse(JournalTextGuard.looksLikeImagePrompt("Tired today. A photo of the sunset made me smile though."))
        XCTAssertFalse(JournalTextGuard.looksLikeImagePrompt("Top-down planning for the week: soup Monday, stew Wednesday."))
    }
}
