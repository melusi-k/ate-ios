import XCTest
import UIKit
@testable import Ate

@MainActor
final class JournalDeleteConfirmationTests: XCTestCase {
    func testNativeAlertHasExactlyTwoDistinctActionsWithOriginalCopyAndRoles() {
        let alert = JournalDeleteConfirmation.makeAlert(onDelete: {}, onCancel: {})
        XCTAssertEqual(alert.preferredStyle, .alert)
        XCTAssertEqual(alert.title, "Delete this journal entry?")
        XCTAssertEqual(alert.message, "This can't be undone. It's only stored on this iPhone.")
        XCTAssertEqual(alert.actions.count, 2)
        let cancel = alert.actions.filter { $0.accessibilityIdentifier == "journal.delete.cancel" }
        let delete = alert.actions.filter { $0.accessibilityIdentifier == "journal.delete.confirm" }
        XCTAssertEqual(cancel.count, 1)
        XCTAssertEqual(delete.count, 1)
        XCTAssertEqual(cancel.first?.title, "Cancel")
        XCTAssertEqual(cancel.first?.style, .cancel)
        XCTAssertEqual(delete.first?.title, "Delete")
        XCTAssertEqual(delete.first?.style, .destructive)
        XCTAssertTrue(alert.actions.allSatisfy(\.isEnabled))
    }

    func testDistinctConfirmationsDoNotShareNativeActions() {
        let first = JournalDeleteConfirmation.makeAlert(onDelete: {}, onCancel: {})
        let retry = JournalDeleteConfirmation.makeAlert(onDelete: {}, onCancel: {})
        XCTAssertFalse(first === retry)
        XCTAssertFalse(first.actions[0] === retry.actions[0])
        XCTAssertFalse(first.actions[1] === retry.actions[1])
        XCTAssertEqual(retry.actions.count, 2)
    }
}

@MainActor
final class JournalDeleteConfirmationHostTests: XCTestCase {
    @MainActor
    private final class Driver {
        var attached = true
        var presentations = 0
        var dismissals = 0
        var completions: [() -> Void] = []
        var deletes = 0
        var cancels = 0
        lazy var host = JournalDeleteConfirmation.Host(attached: { [unowned self] _ in
            self.attached
        }, present: { [unowned self] _, _ in
            self.presentations += 1
        }, dismiss: { [unowned self] _, _, completion in
            self.dismissals += 1
            self.completions.append(completion)
        })
        func update(_ requested: Bool) {
            host.update(requested: requested, onDelete: { [unowned self] in self.deletes += 1 },
                        onCancel: { [unowned self] in self.cancels += 1 })
        }
    }

    func testUpdateAndAppearDuringDismissKeepIdentityAndConsumeDeleteOnce() throws {
        let d = Driver(); d.update(true)
        let token = try XCTUnwrap(d.host.presentationToken)
        d.host.finish(token: token, delete: true)
        d.update(true); d.host.viewDidAppear(false)
        XCTAssertEqual(d.host.presentationToken, token)
        XCTAssertEqual(d.presentations, 1)
        XCTAssertEqual(d.dismissals, 1)
        XCTAssertEqual(d.deletes, 0)
        d.host.finish(token: token, delete: true)
        d.completions[0]()
        d.completions[0]()
        XCTAssertEqual(d.deletes, 1)
        XCTAssertNil(d.host.presentationToken)
    }

    func testFalseTransitionInvalidatesPendingDeleteEvenIfTrueReturns() throws {
        let d = Driver(); d.update(true)
        let token = try XCTUnwrap(d.host.presentationToken)
        d.host.finish(token: token, delete: true)
        d.update(false); d.update(true)
        XCTAssertEqual(d.host.presentationToken, token)
        XCTAssertEqual(d.presentations, 1)
        d.completions[0]()
        XCTAssertEqual(d.deletes, 0)
        XCTAssertNil(d.host.presentationToken)
        // A new explicit request gets fresh identity; old actions/completions
        // cannot dismiss or authorize that new presentation.
        d.update(true)
        let next = try XCTUnwrap(d.host.presentationToken)
        XCTAssertNotEqual(next, token)
        d.host.finish(token: token, delete: true)
        d.completions[0]()
        XCTAssertEqual(d.host.presentationToken, next)
        XCTAssertEqual(d.deletes, 0)
    }

    func testRetireDuringDismissInvalidatesLateCompletionAndNewUpdates() throws {
        let d = Driver(); d.update(true)
        let token = try XCTUnwrap(d.host.presentationToken)
        d.host.finish(token: token, delete: true)
        d.host.retire(); d.update(true)
        XCTAssertEqual(d.host.presentationToken, token)
        XCTAssertEqual(d.dismissals, 1)
        d.completions[0]()
        XCTAssertEqual(d.deletes, 0)
        XCTAssertEqual(d.presentations, 1)
        XCTAssertNil(d.host.presentationToken)
    }

    func testDetachDuringDismissInvalidatesLateCompletionAfterReattachment() throws {
        let d = Driver(); d.update(true)
        let token = try XCTUnwrap(d.host.presentationToken)
        d.host.finish(token: token, delete: true)
        d.attached = false; d.host.detach()
        d.attached = true; d.update(true)
        XCTAssertEqual(d.host.presentationToken, token)
        d.completions[0]()
        XCTAssertEqual(d.deletes, 0)
        XCTAssertEqual(d.presentations, 1)
    }

    func testCancelInvalidatesImmediatelyAndReopenUsesNewIdentity() throws {
        let d = Driver(); d.update(true)
        let token = try XCTUnwrap(d.host.presentationToken)
        d.host.finish(token: token, delete: false)
        XCTAssertEqual(d.cancels, 1)
        d.host.finish(token: token, delete: true)
        d.update(true)
        XCTAssertEqual(d.presentations, 1)
        XCTAssertEqual(d.host.presentationToken, token)
        d.completions[0]()
        XCTAssertEqual(d.deletes, 0)
        d.update(true)
        XCTAssertNotEqual(d.host.presentationToken, token)
        XCTAssertEqual(d.presentations, 2)
    }
}
