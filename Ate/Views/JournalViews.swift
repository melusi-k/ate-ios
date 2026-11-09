import SwiftUI
import MapKit

/// What the root Journal list shows: an explicit read state shared with the timeline, so a store
/// that cannot be read is never presented as "No journal entries yet".
enum JournalListScreenState {
    case loading
    case failed(JournalReadError)
    case loaded([JournalEntry])
}

/// What the body renders for a state, open state and filter result. Plain values, unit-testable.
enum JournalListContent: Equatable {
    case loading
    case readError(JournalReadError)
    /// A healthy, readable journal with nothing in it.
    case emptyJournal
    /// No rows with a non-ok open state: the banner carries the honest state, so no empty claim.
    case emptySuppressed
    case noMatches
    case entries

    static func make(state: JournalListScreenState, openState: JournalOpenState, filteredCount: Int) -> JournalListContent {
        switch state {
        case .loading: return .loading
        case .failed(let error): return .readError(error)
        case .loaded(let entries):
            if entries.isEmpty { return openState == .ok ? .emptyJournal : .emptySuppressed }
            return filteredCount == 0 ? .noMatches : .entries
        }
    }
}

extension View {
    /// The search drawer only exists for a successfully read journal. SwiftUI's .searchable has no
    /// disabled mode, and .disabled on the List would also disable the retry button and the
    /// Timeline/Insights navigation links, so the modifier is applied conditionally. The List is
    /// recreated only when the read state flips between loaded and not-loaded (first appear and
    /// retry cycles), never on scroll, filter or content updates within one state.
    @ViewBuilder
    func searchableWhenReadable(_ readable: Bool, text: Binding<String>) -> some View {
        if readable {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search journal")
                .journalSearchChrome()
        } else {
            self
        }
    }
}

/// More › Journal: every Ate journal entry, newest first, with search.
struct JournalListView: View {
    @Environment(AppStore.self) private var store
    /// Tests render the banner and empty-state suppression without mutating the shared store.
    var openStateOverride: JournalOpenState? = nil
    /// Tests inject a read state; nil reads the shared store on appear.
    var stateOverride: JournalListScreenState? = nil
    /// True as the Journal tab root: shows the one named route to Insights & Cooking History.
    var isTabRoot = false
    @State private var readState: JournalListScreenState = .loading
    @State private var query = ""

    private var state: JournalListScreenState { stateOverride ?? readState }

    private var loadedEntries: [JournalEntry] {
        guard case .loaded(let entries) = state else { return [] }
        return entries
    }

    var filtered: [JournalEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return loadedEntries }
        return loadedEntries.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.prompt.localizedCaseInsensitiveContains(q)
            || ($0.locationName ?? "").localizedCaseInsensitiveContains(q) || ($0.recordedHealthState?.title.localizedCaseInsensitiveContains(q) ?? false) }
    }

    /// Search only operates on a journal that was actually read: in the loading and read-failure
    /// states it is hidden, so an unread journal cannot be searched into looking empty.
    static func controlsVisible(for state: JournalListScreenState) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    var body: some View {
        let openState = openStateOverride ?? store.journalStore.openState
        let content = JournalListContent.make(state: state, openState: openState, filteredCount: filtered.count)
        List {
            PendingCookedReflectionSection()
            Section {
                NavigationLink { JournalTimelineView() } label: { Label("Timeline", systemImage: "calendar.day.timeline.left") }
                    .accessibilityIdentifier("journal.timelineLink")
            }
            if isTabRoot {
                Section {
                    NavigationLink(value: Route.insights) {
                        Label("Insights & Cooking History", systemImage: "heart.text.square")
                    }.accessibilityIdentifier("journal.insightsHistory")
                }
                Section { JournalReflectionCard() }
            }
            if openState != .ok {
                Section { JournalOpenStateBanner(state: openState) }
            }
            switch content {
            case .loading:
                ProgressView("Loading journal").accessibilityIdentifier("journal.loading")
            case .readError(let error):
                VStack(alignment: .leading, spacing: 8) {
                    Label(error == .storeUnavailable ? "Journal unavailable" : "Journal could not be read",
                          systemImage: "exclamationmark.triangle")
                    Text(error == .storeUnavailable
                         ? "Ate could not open the journal on this iPhone."
                         : "Ate could not read the journal just now. This is a read problem, not an empty journal.")
                        .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                    Button("Try again") { reload() }.buttonStyle(.borderless)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("journal.readError")
            case .emptyJournal:
                ContentUnavailableView("No journal entries yet", systemImage: "book.closed",
                                       description: Text("Tap New journal entry to write something, or ask Siri to save a journal entry in Ate."))
            case .emptySuppressed:
                // The banner above carries the honest state; an empty claim here would present a
                // recovered-empty journal as real history.
                EmptyView()
            case .noMatches:
                ContentUnavailableView.search(text: query)
            case .entries:
                ForEach(filtered, id: \.id) { e in
                    NavigationLink(value: Route.journalEntry(e.id)) { JournalRow(entry: e) }
                        .accessibilityIdentifier("journal.entry")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchableWhenReadable(Self.controlsVisible(for: state), text: $query)
        .navigationTitle("Journal")
        .ateRootNavigationChrome(logoID: "journal.logo", enabled: isTabRoot)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.beginManualJournal() } label: { Label("New journal entry", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("journal.newEntry")
            }
        }
        .onChange(of: store.journalRevision) { _, _ in reload() }
        .onChange(of: Self.controlsVisible(for: state)) { _, readable in
            // A failed or superseded read carries no query into the next successful one.
            if !readable { query = "" }
        }
        .onAppear { if stateOverride == nil { reload() } }
    }

    private func reload() {
        do { readState = .loaded(try store.journalStore.readReflections()) }
        catch let error as JournalReadError { readState = .failed(error) }
        catch { readState = .failed(.readFailed) }
    }
}

struct JournalRow: View {
    let entry: JournalEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.datedStateLabel)
                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            Text(entry.text).font(AteFont.body(15)).lineLimit(2)
            HStack(spacing: 10) {
                if let l = entry.locationName { Label(l, systemImage: "mappin").lineLimit(1) }
                if !entry.mediaFileNames.isEmpty { Label("\(entry.mediaFileNames.count)", systemImage: "photo") }
                if !entry.recipeIDs.isEmpty { Label("\(entry.recipeIDs.count)", systemImage: "fork.knife") }
            }.font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One journal entry on its own: full text, date, state, linked recipes, location and media, with Edit, Share and Delete.
struct JournalEntryDetailView: View {
    let entryID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entry: JournalEntry?
    /// False until the first read settles: "Entry not found" is only shown after a successful
    /// read returned nil, never on the frame before the read completes.
    @State private var entryReadComplete = false
    /// True only when the store could not be read at all; nil entry with this false means
    /// the entry is genuinely gone.
    @State private var entryReadFailed = false
    @State private var editing = false
    @State private var draft = ""
    @State private var confirmDelete = false
    @State private var openRecipe: RecipeSheetTarget?

    var body: some View {
        Group {
            if let e = entry {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            if let state = e.recordedHealthState {
                                Label(state.title, systemImage: state.symbol).font(AteFont.body(13, .semibold)).foregroundStyle(Theme.primary)
                            }
                            Text(e.createdAt.formatted(date: .complete, time: .shortened)).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                                .accessibilityIdentifier("journal.detail.date")
                            if let t = e.editedAt { Text("Edited " + t.formatted(date: .abbreviated, time: .shortened)).font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground) }
                            if !e.prompt.isEmpty { Text(e.prompt).font(AteFont.body(14, .semibold)) }
                            Text(e.text).font(AteFont.body(16)).textSelection(.enabled).accessibilityIdentifier("journal.detail.text")
                        }.padding(.vertical, 4)
                    }
                    if let line = JournalingMomentMapper.contextLine(title: e.journalingSuggestionTitle, date: e.momentDate) {
                        Section("Moment") { Label(line, systemImage: "book.pages").accessibilityIdentifier("journal.detail.momentContext") }
                    }
                    if let name = e.locationName {
                        Section("Location") {
                            Label(name, systemImage: "mappin.and.ellipse").accessibilityIdentifier("journal.detail.location")
                            if let lat = e.latitude, let lon = e.longitude {
                                Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: lat, longitude: lon), latitudinalMeters: 800, longitudinalMeters: 800))) {
                                    Marker(name, coordinate: .init(latitude: lat, longitude: lon))
                                }
                                .frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 10)).allowsHitTesting(false)
                            }
                        }
                    }
                    let images = e.mediaFileNames.compactMap { UIImage(contentsOfFile: JournalStore.mediaURL($0).path) }
                    if !e.mediaFileNames.isEmpty {
                        Section("Media") {
                            ScrollView(.horizontal) {
                                HStack { ForEach(images.indices, id: \.self) { i in
                                    Image(uiImage: images[i]).resizable().scaledToFill().frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 10))
                                        .accessibilityLabel("Photo \(i + 1) of \(images.count)")
                                } }
                            }.accessibilityIdentifier("journal.detail.media")
                            if images.count < e.mediaFileNames.count {
                                Text("\(e.mediaFileNames.count - images.count) attachment(s) can't be previewed").font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                            }
                        }
                    }
                    let recipes = e.recipeIDs.compactMap { store.recipe($0) }
                    if !recipes.isEmpty {
                        Section("Linked recipes") {
                            ForEach(recipes, id: \.id) { r in
                                Button { openRecipe = RecipeSheetTarget(id: r.id) } label: { Label(r.title, systemImage: "fork.knife") }
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: shareText(e)) { Label("Share", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("journal.detail.share")
                        Menu {
                            Button { draft = e.text; editing = true } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        } label: { Label("More", systemImage: "ellipsis.circle") }
                        .accessibilityIdentifier("journal.detail.menu")
                    }
                }
                // Destructive deletion always needs an explicit, accessible Cancel action.
                // A confirmation popover may omit its cancel row; an alert keeps both choices.
                .alert("Delete this journal entry?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) {
                        store.journalStore.delete(e); store.show("Journal entry deleted")
                        BetaQA.shared.pass("C-JRN-04", note: "Deleted an entry after confirming")
                        entry = nil; dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This can't be undone. It's only stored on this iPhone.") }
                .sheet(isPresented: $editing) {
                    NavigationStack {
                        TextEditor(text: $draft).padding().font(AteFont.body(16)).accessibilityIdentifier("journal.edit.text")
                            .navigationTitle("Edit entry").navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Save") {
                                        store.journalStore.update(e, text: draft); editing = false; reloadEntry()
                                        BetaQA.shared.pass("C-JRN-03", note: "Edited an entry")
                                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                    }
                    .interactiveDismissDisabled(draft != e.text)
                }
                .sheet(item: $openRecipe) { t in NavigationStack { RecipeDetailView(recipeID: t.id) } }
            } else if !entryReadComplete {
                ProgressView("Loading entry").accessibilityIdentifier("journal.detail.loading")
            } else if entryReadFailed {
                ContentUnavailableView {
                    Label("Entry could not be read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("This is a read problem, not a deleted entry.")
                } actions: {
                    Button("Try again") { reloadEntry() }.accessibilityIdentifier("journal.detail.retry")
                }
            } else {
                ContentUnavailableView("Entry not found", systemImage: "book.closed", description: Text("It may have been deleted."))
            }
        }
        .navigationTitle("Journal entry")
        .onAppear {
            reloadEntry()
            if entry != nil { BetaQA.shared.pass("C-JRN-01", note: "Opened an entry on its own") }
        }
    }

    private func reloadEntry() {
        do {
            entry = try store.journalStore.readEntry(entryID)
            entryReadFailed = false
        } catch {
            entry = nil
            entryReadFailed = true
        }
        entryReadComplete = true
    }

    func shareText(_ e: JournalEntry) -> String {
        var s = e.createdAt.formatted(date: .long, time: .shortened)
        if let state = e.recordedHealthState { s += " · " + state.title }
        s += "\n\n"
        if !e.prompt.isEmpty { s += e.prompt + "\n\n" }
        s += e.text
        if let l = e.locationName { s += "\n\n📍 " + l }
        return s
    }
}

/// Honest journal open state (#245 phase 3): a recovered or temporary journal is never
/// presented as the user's real history.
struct JournalOpenStateBanner: View {
    let state: JournalOpenState
    var body: some View {
        Group {
            switch state {
            case .ok:
                EmptyView()
            case .recovered(let backup):
                Label {
                    Text("Journal recovered. The saved journal on this iPhone was damaged, so Ate moved it aside and started a fresh one. The damaged copy is kept in Backups\(backup.map { " (\($0))" } ?? ""); entries saved from Siri with photos or voice notes keep their media on this iPhone.")
                } icon: { Image(systemName: "exclamationmark.arrow.triangle.2.circlepath") }
            case .inMemoryFallback:
                Label {
                        Text("Journal is temporary right now. Ate could not open the saved journal or start a fresh one, so anything you save will disappear when you close Ate.")
                } icon: { Image(systemName: "exclamationmark.triangle") }
            case .unavailable:
                Label {
                    Text("Journal unavailable. Ate could not open the journal on this iPhone.")
                } icon: { Image(systemName: "exclamationmark.triangle") }
            }
        }
        .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journal.openStateBanner")
    }
}


/// Explicit local writing. No Health authorization, generated context or background draft upload.
struct ManualJournalComposer: View {
    @Environment(AppStore.self) private var store
    @Binding var draft: String
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var showSaveError = false
    @FocusState private var editorFocused: Bool
    @State private var confirmDiscard = false
    private var isEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Text(saveError).foregroundStyle(Theme.destructive)
                            .accessibilityIdentifier("journal.compose.error")
                    }
                }
                Section {
                    TextEditor(text: $draft)
                        .focused($editorFocused)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Journal entry")
                        .accessibilityIdentifier("journal.compose.text")
                }
                Section {
                    Text("Saved only on this iPhone. No Health data is needed. Ate cannot write to Apple's Journal app.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    JournalOpenStateBanner(state: store.journalStore.openState)
                }
            }
            .navigationTitle("New journal entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if draft.isEmpty { dismiss() } else { confirmDiscard = true }
                    }.accessibilityIdentifier("journal.compose.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.journalStore.saveManual(text: draft)
                            draft = ""
                            onSaved()
                            dismiss()
                        } catch {
                            // Keep the draft, but never hide the failed-save feedback behind the keyboard.
                            saveError = error.localizedDescription
                            editorFocused = false
                            showSaveError = true
                        }
                    }
                    .disabled(isEmpty)
                    .accessibilityIdentifier("journal.compose.save")
                }
            }
            .alert("Journal entry not saved", isPresented: $showSaveError) {
                Button("Continue writing") { editorFocused = true }
            } message: {
                Text(saveError ?? "Your draft is still here. Please try saving again.")
            }
            .alert("Discard this draft?", isPresented: $confirmDiscard) {
                Button("Keep writing", role: .cancel) { editorFocused = true }
                Button("Discard draft", role: .destructive) { draft = ""; dismiss() }
            } message: { Text("This draft has not been saved.") }
        }
        .interactiveDismissDisabled(!draft.isEmpty)
    }
}

enum ManualJournalHost { case root }

/// Session-level composer host above the replaceable portrait/sidebar trees.
/// Journal, Insights and the bottom action all use this same presentation owner.
struct JournalTaskHost: ViewModifier {
    @Environment(AppStore.self) private var store

    private var rootComposer: Binding<Bool> {
        Binding(get: { store.manualJournalHost == .root }, set: { if !$0 { store.manualJournalHost = nil } })
    }

    func body(content: Content) -> some View {
        @Bindable var store = store
        content
            .sheet(isPresented: rootComposer) {
                ManualJournalComposer(draft: $store.manualJournalDraft) { store.journalRevision += 1 }
                    .environment(store)
            }
    }
}

/// One session draft, owned outside the navigation tree. No Health reading is invented.
@MainActor @Observable
final class JournalReflectionDraft {
    var text = ""
    var prompt: JournalPrompt?
    var pendingMoment: (title: String, date: Date?)?
    var saveError: String?

    @discardableResult
    func save(context: HealthContext?, journal: JournalStore) -> Bool {
        let selected = prompt ?? context?.prompts.first
        guard journal.save(prompt: selected?.text ?? "", text: text,
                           state: context?.insight.state, recipeIDs: context?.suggestions.map(\.recipeID) ?? [],
                           momentTitle: pendingMoment?.title, momentDate: pendingMoment?.date) else {
            saveError = "Your entry could not be saved. Your draft is still here. Try again."
            return false
        }
        text = ""; prompt = nil; pendingMoment = nil; saveError = nil
        return true
    }
}

struct JournalReflectionCard: View {
    @Environment(AppStore.self) private var store
    @FocusState private var editorFocused: Bool
    @State private var model = InsightsModel.shared
    @AppStorage(JournalingSuggestionsGate.settingKey) private var journalingEnabled = false
    @State private var openRecipe: RecipeSheetTarget?

    var body: some View {
        @Bindable var reflection = store.journalReflection
        VStack(alignment: .leading, spacing: 12) {
            Label("Reflect on your day", systemImage: "quote.bubble").font(AteFont.display(18))
                .accessibilityIdentifier("journal.reflection")
            if model.context != nil && model.isSample {
                Label("Sample data", systemImage: "testtube.2")
                    .font(AteFont.body(12, .semibold)).foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("journal.reflection.sampleBadge")
                Text("These prompts use sample Health data, not your Health readings.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            }
            if let context = model.context {
                ForEach(context.prompts) { p in
                    Button { reflection.prompt = p } label: {
                        HStack(alignment: .top) {
                            Image(systemName: (reflection.prompt ?? context.prompts.first) == p ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(Theme.primary)
                            Text(p.text).font(AteFont.body(15)).multilineTextAlignment(.leading)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("insights.prompt")
                }
            } else {
                Text("What would you like to remember about today?").font(AteFont.body(15))
                    .accessibilityIdentifier("journal.reflection.manualPrompt")
            }
            // A selected Journaling Moment or earlier Health prompt stays visible even if
            // a refresh changes the offered prompts or Health becomes unavailable.
            if let selected = reflection.prompt, !(model.context?.prompts.contains(selected) ?? false) {
                Text(selected.text).font(AteFont.body(15)).accessibilityIdentifier("journal.reflection.selectedPrompt")
            }
            if let moment = reflection.pendingMoment {
                Label(moment.title, systemImage: "book.pages").font(AteFont.body(13))
                    .accessibilityIdentifier("journal.reflection.moment")
            }
            TextField("Write a few lines…", text: $reflection.text, axis: .vertical).lineLimit(3...8)
                .focused($editorFocused)
                .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("insights.journalText")
            Button("Save to journal") { save() }
                .buttonStyle(.ate(.primary, full: true))
                .disabled(reflection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("insights.save")
            if let error = reflection.saveError {
                Text(error).font(AteFont.body(13)).foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("insights.journalSaveError")
            }
            if journalingEnabled && JournalingSuggestionsGate.isAvailable && !AppConfig.isUITesting {
                JournalingSuggestionsButton { handle(moment: $0) }
            }
            Text("Saved only on this iPhone. Ate can't write to Apple's Journal app.")
                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
        }
        .task { await model.loadIfNeeded(recipes: store.recipes) }
        .sheet(item: $openRecipe) { target in Self.momentRecipeSheet(target).environment(store) }
    }

    private func save() {
        let reflection = store.journalReflection
        if reflection.save(context: model.context, journal: store.journalStore) {
            editorFocused = false
            store.journalRevision += 1
            store.show("Saved to your Ate journal")
            BetaQA.shared.pass("A-HEALTH-04", note: "Saved a local journal entry")
        }
    }

    static func momentRecipeTarget(id: String) -> RecipeSheetTarget {
        RecipeSheetTarget(id: id, recordsHealthSuggestionEvidence: false)
    }

    static func momentRecipeSheet(_ target: RecipeSheetTarget) -> RecipeSheet {
        RecipeSheet(recipeID: target.id,
                    recordsHealthSuggestionEvidence: target.recordsHealthSuggestionEvidence)
    }

    private func handle(moment: PickedMoment) {
        switch JournalingMomentMapper.map(title: moment.title,
                                          date: moment.date.map { DateInterval(start: $0, duration: 0) },
                                          hasPhotos: !moment.photoURLs.isEmpty, isWorkout: moment.isWorkout) {
        case .recipeDraft(let title, let date):
            let recipe = JournalingMomentMapper.draft(title: title, date: date)
            store.add(recipe); openRecipe = Self.momentRecipeTarget(id: recipe.id)
            store.show("Recipe draft from your Journal moment")
        case .journalEntry(let prompt, let title, let date, let state):
            store.journalReflection.prompt = JournalPrompt(text: prompt, state: state)
            store.journalReflection.pendingMoment = (title, date)
        }
    }
}
