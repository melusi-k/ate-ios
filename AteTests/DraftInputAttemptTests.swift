import XCTest
@testable import Ate

@MainActor
final class DraftInputAttemptTests: XCTestCase {
    private final class Loader {
        var continuation: CheckedContinuation<String, Never>?
        func load() async -> String { await withCheckedContinuation { continuation = $0 } }
        func complete(_ text: String) { continuation?.resume(returning: text); continuation = nil }
    }

    func testLaterPhotoSelectionWinsEvenWhenOldLoaderIgnoresCancellation() async {
        let attempt = DraftInputAttempt(), old = Loader(), fresh = Loader()
        let oldStarted = expectation(description: "old started"), freshStarted = expectation(description: "fresh started")
        let freshApplied = expectation(description: "fresh applied"), oldReturned = expectation(description: "old returned")
        var selected = "original"
        attempt.start(load: { oldStarted.fulfill(); let result = await old.load(); oldReturned.fulfill(); return result },
                      apply: { selected = $0; XCTFail("Old load applied") })
        await fulfillment(of: [oldStarted], timeout: 2)
        attempt.start(load: { freshStarted.fulfill(); return await fresh.load() },
                      apply: { selected = $0; freshApplied.fulfill() })
        await fulfillment(of: [freshStarted], timeout: 2)
        fresh.complete("latest")
        await fulfillment(of: [freshApplied], timeout: 2)
        old.complete("stale")
        await fulfillment(of: [oldReturned], timeout: 2)
        XCTAssertEqual(selected, "latest")
    }

    func testDiscardSaveOrDisappearInvalidationRefusesLateInput() async {
        let attempt = DraftInputAttempt(), loader = Loader()
        let started = expectation(description: "started"), returned = expectation(description: "returned")
        var writes = 0
        attempt.start(load: { started.fulfill(); let result = await loader.load(); returned.fulfill(); return result },
                      apply: { _ in writes += 1; XCTFail("Revoked input applied") })
        await fulfillment(of: [started], timeout: 2)
        attempt.invalidate()
        loader.complete("late")
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(writes, 0)
    }

    func testCoverSelectionCannotWriteDifferentRegeneratedDraft() async {
        let attempt = DraftInputAttempt(), loader = Loader()
        let started = expectation(description: "started"), returned = expectation(description: "returned")
        var draftID = "first", cover: String?
        let selectedRecipeID = draftID
        attempt.start(load: { started.fulfill(); return await loader.load() }, apply: { value in
            defer { returned.fulfill() }
            guard draftID == selectedRecipeID else { return }
            cover = value
        })
        await fulfillment(of: [started], timeout: 2)
        draftID = "replacement"
        loader.complete("first-cover")
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertNil(cover)
        XCTAssertEqual(draftID, "replacement")
    }
}
