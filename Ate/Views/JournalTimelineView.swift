import SwiftUI

/// What the timeline screen shows, decided by plain values so the empty-vs-error choice is unit-testable (#245).
enum JournalTimelineScreenState: Equatable {
    case loading
    /// The store could not be read. Never presented as "no entries".
    case failed(JournalTimelineReadError)
    case loaded([JournalTimelineItem])
}

/// What the body renders for a state, filter and query.
enum JournalTimelineContent: Equatable {
    case loading
    case readError(JournalTimelineReadError)
    case emptyJournal
    case noMatches
    case sections([JournalTimelineSection])

    static func make(state: JournalTimelineScreenState, filter: JournalTimelineFilter, query: String) -> JournalTimelineContent {
        switch state {
        case .loading: return .loading
        case .failed(let error): return .readError(error)
        case .loaded(let items):
            if items.isEmpty { return .emptyJournal }
            let sections = JournalTimeline.sections(items: items, filter: filter, query: query)
            return sections.isEmpty ? .noMatches : .sections(sections)
        }
    }
}

/// Unified Food Journal timeline: meals and reflections in one day-grouped list.
/// Reads through the bound runtime; editing stays in each entry's existing owner.
struct JournalTimelineView: View {
    @Environment(AppStore.self) private var store
    /// Tests inject items or a failure; nil reads the shared store.
    var stateOverride: JournalTimelineScreenState? = nil
    var openStateOverride: JournalOpenState? = nil
    /// The canonical tab uses this same timeline, not a second reflection-only list.
    var isTabRoot = false
    @State private var loaded: JournalTimelineScreenState = .loading
    /// Private picker selection (the #272 filter enum stays untouched); mapped to `JournalTimelineFilter` below.
    private enum Show: Hashable, CaseIterable {
        case all, meals, reflections, recipes
        var title: String {
            switch self {
            case .all: return "All"
            case .meals: return "Meals"
            case .reflections: return "Reflections"
            case .recipes: return "Recipes"
            }
        }
    }
    @State private var show: Show = .all
    /// nil = every meal type. Only offered while "Meals" is selected.
    @State private var mealType: NutritionMeal? = nil
    @State private var query = ""

    private var state: JournalTimelineScreenState { stateOverride ?? Self.qaState() ?? loaded }

    /// Filter and search only operate on a journal that was actually read: in the loading and
    /// read-failure states they are hidden, so a read error cannot be filtered or searched into
    /// looking like an empty journal.
    static func controlsVisible(for state: JournalTimelineScreenState) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    var body: some View {
        let openState = openStateOverride ?? store.journalStore.openState
        let content = JournalTimelineContent.make(state: state, filter: filter, query: query)
        List {
            if isTabRoot {
                PendingCookedReflectionSection()
                Section {
                    NavigationLink(value: Route.insights) {
                        Label("Insights & Cooking History", systemImage: "heart.text.square")
                    }.accessibilityIdentifier("journal.insightsHistory")
                    NavigationLink(value: Route.nutritionDiary) {
                        Label("Log food and view meals", systemImage: "fork.knife")
                    }.accessibilityIdentifier("journal.meals")
                }
                Section { JournalReflectionCard() }
            }
            if openState != .ok {
                Section { JournalOpenStateBanner(state: openState) }
            }
            if Self.controlsVisible(for: state) { filterBar }
            switch content {
            case .loading:
                ProgressView("Loading journal").accessibilityIdentifier("journal.timeline.loading")
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
                .accessibilityIdentifier("journal.timeline.error")
            case .emptyJournal:
                // With a non-ok open state the banner carries the honest state; do not add "no entries yet".
                if openState == .ok {
                    ContentUnavailableView("No journal entries yet", systemImage: "book.closed",
                                           description: Text("Meals and reflections you save appear here."))
                        .accessibilityIdentifier("journal.timeline.empty")
                }
            case .noMatches:
                ContentUnavailableView.search(text: query).accessibilityIdentifier("journal.timeline.noMatches")
            case .sections(let sections):
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            timelineRow(item)
                                .accessibilityIdentifier("journal.timeline.row")
                        }
                    } header: {
                        Text(Self.dayTitle(section.dayKey)).accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .searchableWhenReadable(Self.controlsVisible(for: state), text: $query)
        .navigationTitle("Food Journal")
        .ateRootNavigationChrome(logoID: "journal.logo", enabled: isTabRoot)
        .toolbar {
            if isTabRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.beginManualJournal() } label: {
                        Label("New journal entry", systemImage: "square.and.pencil")
                    }.accessibilityIdentifier("journal.newEntry")
                }
            }
        }
        .onChange(of: store.journalRevision) { _, _ in
            if stateOverride == nil, Self.qaState() == nil { reload() }
        }
        .onChange(of: Self.controlsVisible(for: state)) { _, readable in
            // A failed or superseded read carries no query into the next successful one.
            if !readable { query = "" }
        }
        .onAppear { if stateOverride == nil, Self.qaState() == nil { reload() } }
    }

    enum EntryDestination: Equatable {
        case reflection(String)
        case mealDay(String)
        case unavailable
    }

    static func destination(for item: JournalTimelineItem, canonicalAvailable: Bool) -> EntryDestination {
        if item.kind == .reflection { return .reflection(item.id) }
        guard canonicalAvailable, item.meal != nil else { return .unavailable }
        return .mealDay(item.dayKey)
    }

    @ViewBuilder
    private func timelineRow(_ item: JournalTimelineItem) -> some View {
        switch Self.destination(for: item, canonicalAvailable: store.foodJournalRuntime != nil) {
        case .reflection(let id):
            NavigationLink(value: Route.journalEntry(id)) { JournalTimelineRow(item: item) }
        case .mealDay(let dayKey):
            if let runtime = store.foodJournalRuntime {
                // Open the retained local meal day, never today's diary or the current time zone's day.
                NavigationLink {
                    CanonicalNutritionDiaryView(coordinator: runtime.coordinator,
                        goalsRepository: runtime.goalsRepository, repair: runtime.repair,
                        selectedDayKey: dayKey)
                } label: { JournalTimelineRow(item: item) }
            }
        case .unavailable:
            // A missing meal payload is visible but never guessed into an editable meal.
            JournalTimelineRow(item: item)
        }
    }

    private var filter: JournalTimelineFilter {
        switch show {
        case .all: return .all
        case .meals: return .meals(mealType)
        case .reflections: return .reflections
        case .recipes: return .recipeLinked
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Show", selection: $show) {
                ForEach(Show.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("journal.timeline.filter")
            if show == .meals {
                // A meal row whose details are missing has no meal type: it shows under "All meals" only.
                Picker("Meal type", selection: $mealType) {
                    Text("All meals").tag(NutritionMeal?.none)
                    ForEach(NutritionMeal.allCases) { Text($0.title).tag(NutritionMeal?.some($0)) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("journal.timeline.mealType")
            }
        }
    }

    /// Reads on the main actor (the store is @MainActor and shares JournalStore's main context): two fetches and a map,
    /// the same cost class as JournalListView's entries() read on appear. The result is snapshotted into @State; the
    /// open-state banner re-reads the bound journal openState whenever the body re-evaluates.
    private func reload() {
        do {
            loaded = .loaded(try store.journalTimelineItems())
        }
        catch let error as JournalTimelineReadError { loaded = .failed(error) }
        catch { loaded = .failed(.readFailed) }
    }

    /// UI-test hook (`-qaJournalTimeline <fixture|failure|empty>`): fixed states so the real screen can be
    /// exercised and photographed through the app's own route. Inert unless `AppConfig.isUITesting`.
    static func qaState(args: [String] = ProcessInfo.processInfo.arguments) -> JournalTimelineScreenState? {
        guard AppConfig.isUITesting, let i = args.firstIndex(of: "-qaJournalTimeline"), i + 1 < args.count else { return nil }
        func item(_ id: String, _ kind: JournalEntryKind, _ day: String, _ at: TimeInterval, meal: NutritionMeal?,
                  link: Bool, _ summary: String) -> JournalTimelineItem {
            JournalTimelineItem(id: id, kind: kind, createdAt: Date(timeIntervalSince1970: at), dayKey: day, meal: meal,
                                hasRecipeLink: link, searchText: summary, summary: summary)
        }
        switch args[i + 1] {
        case "fixture":
            return .loaded([
                item("qa-meal", .meal, "2026-11-02", 1_793_600_000, meal: .breakfast, link: true, "Oat porridge"),
                item("qa-orphan", .meal, "2026-11-02", 1_793_590_000, meal: nil, link: false, "Meal details unavailable"),
                item("qa-legacy", .reflection, "2026-11-01", 1_793_500_000, meal: nil, link: false, "Soup was the best part")])
        case "failure": return .failed(.readFailed)
        case "empty": return .loaded([])
        default: return nil
        }
    }

    /// Formats in the calendar's own time zone so the header names the stored local day, whatever zone the phone is in now.
    static func dayTitle(_ dayKey: String, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        guard let date = NutritionDiaryDayKey.date(for: dayKey, calendar: calendar) else { return dayKey }
        return date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar,
                                               timeZone: calendar.timeZone))
    }
}

/// One timeline row. A meal whose payload is missing stays visible; reflections get their own icon and label.
struct JournalTimelineRow: View {
    let item: JournalTimelineItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.kind == .meal ? "fork.knife" : "text.quote").accessibilityHidden(true)
                Text(kindLabel + " · " + time)
                if item.hasRecipeLink { Image(systemName: "book").accessibilityHidden(true) }
            }
            .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            Text(shownSummary).font(AteFont.body(15)).lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kindLabel), \(time). \(shownSummary)\(item.hasRecipeLink ? ". Linked recipe" : "")")
    }

    private var time: String { item.createdAt.formatted(date: .omitted, time: .shortened) }

    /// Never a blank row: an entry with no text still says what it is.
    private var shownSummary: String {
        let t = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return item.kind == .meal ? "Meal details unavailable" : "Reflection with no text"
    }

    private var kindLabel: String {
        switch item.kind {
        case .meal: return item.meal?.title ?? "Meal"
        case .reflection: return "Reflection"
        }
    }
}
