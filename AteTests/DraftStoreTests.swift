import XCTest
@testable import Ate

final class DraftStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: DraftStore!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "draft-store-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = DraftStore(defaults: defaults, enabled: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testPendingGenerationSurvivesStoreRecreationAndCanBeRetried() {
        let input = String(repeating: "recipe ", count: 700)
        store.begin(mode: "Prompt", text: input)

        // A fresh instance models a new app process reading the same persisted defaults.
        let relaunched = DraftStore(defaults: defaults, enabled: true)
        let pending = try? XCTUnwrap(relaunched.pending)
        XCTAssertEqual(pending??.mode, "Prompt")
        XCTAssertEqual(pending??.text.count, 4000)
        XCTAssertNotNil(pending??.startedAt)

        relaunched.end()
        XCTAssertNil(DraftStore(defaults: defaults, enabled: true).pending)
    }

    func testSavingDraftEndsPendingGenerationAndPersistsCard() throws {
        store.begin(mode: "Link", text: "https://example.com/recipe")
        let card = RecipeCard(title: "Tomato soup", servings: 2)
        store.saveDraft(card)

        let relaunched = DraftStore(defaults: defaults, enabled: true)
        XCTAssertNil(relaunched.pending)
        XCTAssertEqual(try XCTUnwrap(relaunched.draft).title, "Tomato soup")
    }

    func testClearRemovesPendingGenerationAndUnsavedCard() {
        store.begin(mode: "Image", text: "")
        store.saveDraft(RecipeCard(title: "Pap"))
        store.clear()

        let relaunched = DraftStore(defaults: defaults, enabled: true)
        XCTAssertNil(relaunched.pending)
        XCTAssertNil(relaunched.draft)
    }

    func testDisabledStoreDoesNotPersistInterruptedWork() {
        let disabled = DraftStore(defaults: defaults, enabled: false)
        disabled.begin(mode: "Prompt", text: "Miso salmon")
        disabled.saveDraft(RecipeCard(title: "Miso salmon"))

        XCTAssertNil(disabled.pending)
        XCTAssertNil(disabled.draft)
    }
}
