import SwiftUI
import UIKit

/// A native system alert with one concrete UIKit action per decision. SwiftUI's
/// alert query returned two AX buttons per identifier in #527's exact
/// Journal run. The precise duplicated wrapper was not captured; this replaces
/// that projection rather than guessing which descendant to hide. Do not hide duplicate nodes or make the test choose one of them.
/// Public UIAlertAction identifiers belong to the actions themselves, not a
/// SwiftUI action view that the system can project into multiple AX descendants.
@MainActor
struct JournalDeleteConfirmation: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDelete: () -> Void

    static let title = "Delete this journal entry?"
    static let message = "This can't be undone. It's only stored on this iPhone."

    static func makeAlert(onDelete: @escaping () -> Void,
                          onCancel: @escaping () -> Void) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in onCancel() }
        cancel.accessibilityIdentifier = "journal.delete.cancel"
        let delete = UIAlertAction(title: "Delete", style: .destructive) { _ in onDelete() }
        delete.accessibilityIdentifier = "journal.delete.confirm"
        alert.addAction(cancel)
        alert.addAction(delete)
        return alert
    }

    func makeUIViewController(context: Context) -> Host { Host() }

    func updateUIViewController(_ host: Host, context: Context) {
        host.update(requested: isPresented, onDelete: {
            isPresented = false
            onDelete()
        }, onCancel: { isPresented = false })
    }

    static func dismantleUIViewController(_ host: Host, coordinator: ()) {
        host.retire()
    }

    /// This one host owns one alert, independent of loaded List/model branches.
    /// Presentation only happens when attached and on a requested state edge or
    /// first attachment. No polling, delayed dispatch, presentation retry or lookup
    /// of an arbitrary key-window/topmost controller is involved.
    final class Host: UIViewController {
        private var requested = false
        private var activeAlert: (token: UUID, controller: UIAlertController)?
        private var validToken: UUID?
        private var pendingDelete: UUID?
        private var selectedDelete: (() -> Void)?
        private var dismissing = false
        private var retired = false
        private var onDelete: () -> Void = {}
        private var onCancel: () -> Void = {}

        // Native defaults in production. Injected drivers let lifecycle tests hold
        // dismissal completion without sleeps, windows, or timing assumptions.
        private let attached: ((Host) -> Bool)?
        private let presentAlert: ((Host, UIAlertController) -> Void)?
        private let dismissAlert: ((UIAlertController, Bool, @escaping () -> Void) -> Void)?

        init(attached: ((Host) -> Bool)? = nil,
             present: ((Host, UIAlertController) -> Void)? = nil,
             dismiss: ((UIAlertController, Bool, @escaping () -> Void) -> Void)? = nil) {
            self.attached = attached
            self.presentAlert = present
            self.dismissAlert = dismiss
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("Use init()") }

        private var isAttached: Bool {
            attached?(self) ?? (isViewLoaded && view.window != nil)
        }

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isAccessibilityElement = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfRequested()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if !isAttached { detach() }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil { detach() }
        }

        func update(requested: Bool, onDelete: @escaping () -> Void,
                    onCancel: @escaping () -> Void) {
            guard !retired else { return }
            self.requested = requested
            self.onDelete = onDelete
            self.onCancel = onCancel
            if requested {
                presentIfRequested()
            } else {
                invalidateOperation()
                beginDismiss(animated: true)
            }
        }

        private func presentIfRequested() {
            guard !retired, requested, activeAlert == nil,
                  isAttached, presentedViewController == nil else { return }
            let token = UUID()
            let alert = JournalDeleteConfirmation.makeAlert(onDelete: { [weak self] in
                self?.finish(token: token, delete: true)
            }, onCancel: { [weak self] in
                self?.finish(token: token, delete: false)
            })
            // Retain identity from before presentation through dismissal completion.
            activeAlert = (token, alert)
            validToken = token
            if let presentAlert { presentAlert(self, alert) }
            else { present(alert, animated: true) }
        }

        func finish(token: UUID, delete: Bool) {
            guard !retired, isAttached, requested, !dismissing,
                  validToken == token, activeAlert?.token == token else { return }
            if delete {
                pendingDelete = token
                selectedDelete = onDelete
            } else {
                // Cancel revokes the operation immediately, before dismissal.
                requested = false
                invalidateOperation()
                onCancel()
            }
            beginDismiss(animated: true)
        }

        private func beginDismiss(animated: Bool) {
            guard !dismissing, let active = activeAlert else { return }
            dismissing = true
            let completion: () -> Void = { [weak self] in
                self?.completeDismiss(token: active.token)
            }
            if let dismissAlert { dismissAlert(active.controller, animated, completion) }
            else { active.controller.dismiss(animated: animated, completion: completion) }
        }

        private func completeDismiss(token: UUID) {
            guard activeAlert?.token == token, dismissing else { return }
            let shouldDelete = !retired && isAttached && requested &&
                validToken == token && pendingDelete == token
            let action = selectedDelete
            // Consume before calling out. Duplicate/late completions cannot run
            // this operation again, or consume a later presentation's identity.
            activeAlert = nil
            dismissing = false
            invalidateOperation()
            requested = false
            if shouldDelete { action?() }
        }

        private func invalidateOperation() {
            validToken = nil
            pendingDelete = nil
            selectedDelete = nil
        }

        func detach() {
            requested = false
            invalidateOperation()
            beginDismiss(animated: false)
        }

        func retire() {
            retired = true
            requested = false
            invalidateOperation()
            onDelete = {}; onCancel = {}
            beginDismiss(animated: false)
        }

        // Read-only identity for deterministic lifecycle tests. Actions capture
        // their original token; they never use this to select a new operation.
        var presentationToken: UUID? { activeAlert?.token }
    }
}
