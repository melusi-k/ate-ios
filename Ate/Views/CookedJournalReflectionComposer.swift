import SwiftUI

/// Dormant host-ready composer: Save uses the runtime-bound journal and retained cook, never the shared store.
/// The presentation owner must retain this session when the sheet is dismissed. No app host activates it yet.
struct CookedJournalReflectionComposer: View {
    @Bindable var session: CookedJournalReflectionSession
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Cooked \(session.event.recipeTitle)") {
                    TextEditor(text: $session.draft)
                        .focused($focused)
                        .disabled(session.isAcknowledgementPending)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Note about this cook")
                        .accessibilityIdentifier("cookJournal.note")
                    Text("This is a reflection about cooking, not a record of food eaten. No Health data is added.")
                        .font(.footnote)
                }
                if let problem = session.problem {
                    Section { Text(problem).accessibilityIdentifier("cookJournal.error") }
                }
            }
            .navigationTitle("Note about this cook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep for later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focused = false
                        if session.save() { onSaved(); dismiss() }
                    }
                    .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("cookJournal.save")
                }
            }
        }
        .interactiveDismissDisabled(!session.draft.isEmpty)
    }
}

/// Both actual Cook Mode entrances share the optional runtime-gated callback. No runtime means no offer.
struct JournalBoundCookMode: View {
    let recipeID: String
    var onExit: (() -> Void)? = nil
    @Environment(AppStore.self) private var store

    var body: some View {
        CookModeView(recipeID: recipeID, completionOutbox: store.foodJournalRuntime?.cookOutbox ?? CookCompletionOutbox(), offerPolicy: store.foodJournalRuntime?.cookOfferPolicy ?? CookReflectionOfferPolicy(), onExit: onExit,
                     onReflect: store.foodJournalRuntime == nil ? nil : { event in store.requestCookedReflection(event) })
            .onAppear { store.cookJournalViewVisible = true }
            .onDisappear { store.cookJournalViewVisible = false; store.presentPendingCookedReflection() }
    }
}

/// One root presentation owner, outside the replaceable portrait/sidebar trees.
struct CookedJournalReflectionHost: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { store.cookedReflectionPresentedID != nil },
                                        set: { if !$0 { store.cookedReflectionPresentedID = nil } }),
                   onDismiss: { store.presentPendingCookedReflection() }) {
                if let id = store.cookedReflectionPresentedID, let session = store.cookedReflectionSessions[id] {
                    CookedJournalReflectionComposer(session: session) {
                        store.journalRevision += 1
                        store.cookedReflectionSessions[id] = nil
                        store.cookedReflectionPresentedID = nil
                    }
                }
            }
            .onChange(of: store.manualJournalHost == nil) { _, _ in store.presentPendingCookedReflection() }
            .onChange(of: store.authSheet == nil) { _, _ in store.presentPendingCookedReflection() }
            .onChange(of: store.showOnboarding) { _, _ in store.presentPendingCookedReflection() }
            .onChange(of: store.path) { _, _ in store.presentPendingCookedReflection() }
            .onChange(of: store.cookedReflectionPendingID) { _, _ in store.presentPendingCookedReflection() }
    }
}

/// Explicit recovery entry point, including after relaunch or a suppressed/dismissed optional offer.
struct PendingCookedReflectionSection: View {
    @Environment(AppStore.self) private var store
    @State private var pending: [CookCompletionEvent] = []
    @State private var readFailed = false

    private var offered: [CookCompletionEvent] { store.availableCookedReflections(queued: pending) }

    var body: some View {
        if store.foodJournalRuntime != nil {
            Section("Notes about cooking") {
                if readFailed {
                    Text("Ate could not read its saved cooks. This is not an empty history.")
                    Button("Try again", action: reload)
                }
                ForEach(offered) { event in
                    Button("Write about \(event.recipeTitle)") { store.requestCookedReflection(event) }
                        .accessibilityIdentifier("cookJournal.pending.\(event.id)")
                }
            }
            .onAppear(perform: reload)
            .onChange(of: store.journalRevision) { _, _ in reload() }
        }
    }

    private func reload() {
        do { pending = try store.foodJournalRuntime?.pendingCookReflections() ?? []; readFailed = false }
        catch { pending = []; readFailed = true }
    }
}
