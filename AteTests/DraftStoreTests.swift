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

    func testPendingGenerationSurvivesRelaunchAndRetryUntilSuccess() throws {
        let input = String(repeating: "recipe ", count: 700)
        store.begin(mode: "Prompt", text: input)

        // A fresh instance models a new app process reading the same persisted defaults.
        let relaunched = DraftStore(defaults: defaults, enabled: true)
        let pending = try XCTUnwrap(relaunched.pending)
        XCTAssertEqual(pending.mode, "Prompt")
        XCTAssertEqual(pending.text.count, 4000)
        XCTAssertGreaterThan(pending.startedAt, 0)

        // A retry starts a new attempt using the same recoverable input. Merely relaunching
        // or starting the retry must not erase that input before a successful result exists.
        relaunched.begin(mode: pending.mode, text: pending.text, imageData: pending.imageData)
        let retryAttempt = try XCTUnwrap(DraftStore(defaults: defaults, enabled: true).pending)
        XCTAssertEqual(retryAttempt.mode, pending.mode)
        XCTAssertEqual(retryAttempt.text, pending.text)

        // Only a completed, persisted draft ends the pending request.
        relaunched.saveDraft(RecipeCard(title: "Recovered recipe"))
        let completed = DraftStore(defaults: defaults, enabled: true)
        XCTAssertNil(completed.pending)
        XCTAssertEqual(try XCTUnwrap(completed.draft).title, "Recovered recipe")
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

extension DraftStoreTests {
    func testRetiredDraftWriterCannotCreateOrRemoveRecoveryBytes() throws {
        enum Stale: Error { case epoch }
        var admitted = true, effects = 0
        let boundary = FoodJournalWriterBoundary { work in
            guard admitted else { throw Stale.epoch }
            effects += 1; try work()
        }
        let old = DraftStore(defaults: defaults, enabled: true, writerBoundary: boundary)
        XCTAssertTrue(old.begin(mode: "Prompt", text: "Synthetic retained input"))
        admitted = false
        let before = defaults.dictionaryRepresentation()
        XCTAssertFalse(old.saveDraft(RecipeCard(title: "Late completion")))
        XCTAssertFalse(old.end())
        XCTAssertFalse(old.clear())
        XCTAssertFalse(old.begin(mode: "Prompt", text: "Late request"))
        XCTAssertEqual(defaults.data(forKey: "ate.draft.pending.v1"), before["ate.draft.pending.v1"] as? Data)
        XCTAssertNil(defaults.object(forKey: "ate.draft.card.v1"))
        XCTAssertEqual(effects, 1)
        let replacement = DraftStore(defaults: defaults, enabled: true, writerBoundary: .legacy)
        XCTAssertTrue(replacement.saveDraft(RecipeCard(title: "New admitted work")))
        XCTAssertFalse(old.clear(), "old graph cannot clear the replacement's draft")
        XCTAssertEqual(replacement.draft?.title, "New admitted work")
    }
}
