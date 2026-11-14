import SwiftUI
import OSLog

struct CookingTrackerView: View {
    @Environment(AppStore.self) private var store
    private var history: CookingHistory { store.journalCookingHistory }
    @State private var selectedDate: Date?
    /// Recipe chosen in the day sheet. The day sheet is dismissed first and the recipe sheet is
    /// presented from its onDismiss, so only one sheet is ever up: RecipeSheet's Cook mode
    /// handoff to the root full-screen cover then works exactly as it does from Insights.
    @State private var pendingRecipeID: String?
    @State private var openRecipe: RecipeSheetTarget?
    /// The day the recipe was opened from. Done or a swipe-down returns to that day's sheet;
    /// leaving for Cook mode or another route (RecipeSheet reports it) does not reopen it.
    @State private var returnDate: Date?
    @State private var leftRecipeForElsewhere = false
    /// UI-test-only state trace. Booleans only: no date, recipe identity or content.
    private func traceDaySheet(_ phase: String) {
        guard AppConfig.isUITesting else { return }
        Logger(subsystem: "com.melusik.ate", category: "day-sheet-presentation")
            .notice("phase=\(phase, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) selected=\(selectedDate != nil, privacy: .public) pendingRecipe=\(pendingRecipeID != nil, privacy: .public) openRecipe=\(openRecipe != nil, privacy: .public) returnDay=\(returnDate != nil, privacy: .public)")
    }
    private func invalidateDayReturn() {
        returnDate = nil
        pendingRecipeID = nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cooking tracker").font(AteFont.display(18))
                Spacer()
                Label("\(history.streak()) day streak", systemImage: "flame.fill")
                    .font(AteFont.body(12, .semibold)).foregroundStyle(Theme.primary)
            }
            Text("Finish cooking in Cook Mode to record a day. Tap a date to see what you cooked.")
                .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            CookingDotGrid(history: history, selectedDate: $selectedDate)
                // Preserve child accessibility so month navigation and day buttons remain individually testable.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("insights.cookingCalendar")
            HStack {
                Circle().fill(Theme.primary).frame(width: 9, height: 9)
                Text("Cooked").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                Circle().fill(Theme.input).frame(width: 9, height: 9)
                Text("No cooking recorded").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
            }
        }
        .cardSurface(padding: 16)
        .sheet(item: Binding(get: { selectedDate.map { TrackerDate(date: $0) } }, set: {
            selectedDate = $0?.date
            traceDaySheet("binding-set")
        }),
               onDismiss: {
                   traceDaySheet("on-dismiss")
                   guard let id = pendingRecipeID else { return }
                   pendingRecipeID = nil
                   openRecipe = RecipeSheetTarget(id: id)
               }) { item in
            CookingDaySheet(date: item.date, recipeIDs: history.recipeIDs(on: item.date), recipes: store.recipes) { id in
                pendingRecipeID = id
                returnDate = item.date
                selectedDate = nil
            }
            .onAppear { traceDaySheet("content-appear") }
            .onDisappear { traceDaySheet("content-disappear") }
            .presentationDetents([.medium])
        }
        // Leaving the tracker context (tab, pushed route, or the host going away) cancels any
        // pending return to the day sheet, so a later dismissal never requeues an old day.
        .onChange(of: selectedDate) { _, _ in traceDaySheet("selected-date-changed") }
        .onChange(of: store.tab) { _, _ in invalidateDayReturn() }
        .onChange(of: store.path) { _, _ in invalidateDayReturn() }
        .onChange(of: store.trackerPath) { _, _ in invalidateDayReturn() }
        .onDisappear { invalidateDayReturn() }
        .sheet(item: $openRecipe, onDismiss: {
            let leaving = leftRecipeForElsewhere
            leftRecipeForElsewhere = false
            let day = returnDate
            returnDate = nil
            if !leaving, let day { selectedDate = day }
        }) { t in
            RecipeSheet(recipeID: t.id, recordsHealthSuggestionEvidence: false,
                        onLeaveForElsewhere: { leftRecipeForElsewhere = true })
                .environment(store)
        }
    }
}

private struct TrackerDate: Identifiable { let date: Date; var id: Date { date } }

enum CookingTrackerPresentation {
    static func recipeTitle(for id: String, recipes: [RecipeCard]) -> String {
        recipes.first(where: { $0.id == id })?.title ?? "Recipe no longer in your library"
    }
    /// Only recipes still in the library can be opened; a deleted recipe keeps the plain,
    /// non-tappable fallback row (its cooking history is never touched).
    static func isInLibrary(_ id: String, recipes: [RecipeCard]) -> Bool {
        recipes.contains(where: { $0.id == id })
    }
}

private struct CookingDotGrid: View {
    let history: CookingHistory
    @Binding var selectedDate: Date?
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let start = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return (0..<symbols.count).map { symbols[(start + $0) % symbols.count] }
    }

    private var monthDates: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = dayRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        let cells: [Date?] = Array(repeating: nil, count: leading) + days.map(Optional.some)
        let trailing = (7 - cells.count % 7) % 7
        return cells + Array(repeating: nil, count: trailing)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    if let previous = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                        withAnimation(Motion.anim(.snappy)) { displayedMonth = previous }
                    }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")
                .accessibilityIdentifier("tracker.previousMonth")

                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(AteFont.body(14, .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("tracker.displayedMonth")
                Spacer()

                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                        withAnimation(Motion.anim(.snappy)) { displayedMonth = next }
                    }
                } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)
                .accessibilityLabel("Next month")
                .accessibilityIdentifier("tracker.nextMonth")
            }

            let monthSummary = CookingMonthSummary.make(events: history.events, month: displayedMonth, calendar: calendar)
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(monthSummary.daysText)
                    .font(AteFont.body(16, .semibold)).foregroundStyle(Theme.foreground)
                Text(monthSummary.recipesText)
                    .font(AteFont.body(16, .medium)).foregroundStyle(Theme.secondaryForeground)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recorded this month: " + monthSummary.text)
            .accessibilityIdentifier("tracker.monthSummary")

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday.uppercased())
                        .font(AteFont.body(9, .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let cooked = history.cooked(on: date)
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let isToday = calendar.isDateInToday(date)
                        Button { selectedDate = date } label: {
                            Circle()
                                .fill(cooked ? Theme.primary : Theme.input)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(calendar.component(.day, from: date).description)
                                        .font(.system(.caption2, design: .rounded, weight: isToday ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.7)
                                        .foregroundStyle(cooked ? .white : Theme.mutedForeground)
                                }
                                .overlay {
                                    Circle().strokeBorder(isSelected ? Theme.foreground : .clear, lineWidth: 2)
                                }
                                .overlay {
                                    if isToday && !isSelected {
                                        Circle().strokeBorder(Theme.primary, lineWidth: 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (cooked ? ", cooked" : ", no cooking recorded") + (isToday ? ", today" : ""))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("tracker.day.\(calendar.component(.day, from: date))")
                    } else {
                        Color.clear.frame(height: 32).accessibilityHidden(true)
                    }
                }
            }
        }
        .onChange(of: displayedMonth) { _, month in
            if let selectedDate, !calendar.isDate(selectedDate, equalTo: month, toGranularity: .month) {
                self.selectedDate = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            // Keep the visible month aligned with the device's new local calendar without
            // rewriting previously stored YYYY-MM-DD event keys.
            displayedMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
            selectedDate = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            displayedMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
            selectedDate = nil
        }
    }
}

private struct CookingDaySheet: View {
    let date: Date
    let recipeIDs: Set<String>
    let recipes: [RecipeCard]
    let openRecipe: (String) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section(date.formatted(date: .complete, time: .omitted)) {
                    if recipeIDs.isEmpty { Text("Nothing recorded for this day.").foregroundStyle(.secondary) }
                    ForEach(Array(recipeIDs).sorted(), id: \.self) { id in
                        let title = CookingTrackerPresentation.recipeTitle(for: id, recipes: recipes)
                        if CookingTrackerPresentation.isInLibrary(id, recipes: recipes) {
                            Button { openRecipe(id) } label: {
                                HStack {
                                    Label(title, systemImage: "fork.knife")
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel(title)
                            .accessibilityHint("Opens the recipe")
                            .accessibilityIdentifier("tracker.recipe." + id)
                        } else {
                            Label(title, systemImage: "fork.knife")
                                .accessibilityIdentifier("tracker.recipe." + id)
                        }
                    }
                }
            }.navigationTitle("Cooked that day").navigationBarTitleDisplayMode(.inline)
        }
    }
}


/// Journal tab root: the Journal, with one named route to Insights & Cooking History (calendar, Health
/// insights and the journal card keep their existing behaviour there).
struct CookingTrackerScreen: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.foodJournalRuntime != nil {
            JournalTimelineView(isTabRoot: true)
        } else {
            JournalListView(isTabRoot: true)
        }
    }
}
