import SwiftUI

/// Event-bound composer: Save uses the explicitly selected journal and retained cook, not the current recipe.
/// The presentation owner must retain this session when the sheet is dismissed.
struct CookedJournalReflectionComposer: View {
    @Bindable var session: CookedJournalReflectionSession
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Cooked \(session.event.recipeTitle)") {
                    Text(session.event.completedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.footnote).foregroundStyle(Theme.mutedForeground)
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

/// Both actual Cook Mode entrances share the same completion and Journal handoff.
struct JournalBoundCookMode: View {
    let recipeID: String
    var onExit: (() -> Void)? = nil
    @Environment(AppStore.self) private var store

    var body: some View {
        CookModeView(recipeID: recipeID, completionOutbox: store.cookJournalOutbox, offerPolicy: store.cookJournalOfferPolicy, onExit: onExit,
                     onReflect: { event in store.requestCookedReflection(event) })
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
        if !pending.isEmpty || readFailed || !offered.isEmpty {
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
        }
        // An always-present loader is needed even when there are initially no visible rows.
        Color.clear.frame(height: 0).listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 0)
            .onAppear(perform: reload)
            .onChange(of: store.journalRevision) { _, _ in reload() }
    }

    private func reload() {
        do { pending = try store.cookJournalOutbox.load(); readFailed = false }
        catch { pending = []; readFailed = true }
    }
}
