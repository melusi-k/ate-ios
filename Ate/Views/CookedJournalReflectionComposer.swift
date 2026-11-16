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
                    Button("Later") { dismiss() }
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

/// Loading belongs to the containing List's lifecycle, never to a hidden List row.
@MainActor
struct PendingCookedReflectionState {
    var pending: [CookCompletionEvent] = []
    var readFailed = false

    mutating func reload(store: AppStore) {
        do { pending = try store.cookJournalOutbox.load(); readFailed = false }
        catch { pending = []; readFailed = true }
    }
}

/// Explicit recovery entry point, including after relaunch or a dismissed optional offer.
struct PendingCookedReflectionSection: View {
    @Environment(AppStore.self) private var store
    let state: PendingCookedReflectionState
    let retry: () -> Void

    private var offered: [CookCompletionEvent] { store.availableCookedReflections(queued: state.pending) }

    var body: some View {
        if !state.pending.isEmpty || state.readFailed || !offered.isEmpty {
            Section {
                // Put the title inside the card, not in a native section header. All home
                // cards then share the same outer gap instead of adding header clearance.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes about cooking").font(AteFont.body(15, .semibold))
                    if state.readFailed {
                        Text("Ate could not read its saved cooks. This is not an empty history.")
                        Button("Try again", action: retry)
                    }
                    ForEach(offered) { event in
                        Button("Write about \(event.recipeTitle)") { store.requestCookedReflection(event) }
                            .accessibilityIdentifier("cookJournal.pending.\(event.id)")
                    }
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("journal.cookingNotesCard")
            }
        }
    }
}
