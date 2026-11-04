import SwiftUI

/// Food diary on the canonical Food Journal coordinator (#179): real entry editing, visible
/// weekly totals for the selected week, and honest blocked states with the legacy repair route.
/// Unactivated candidate - no production call site constructs this view yet. Central integration
/// owns composition (coordinator, repair adapter, backup directory) and the retirement of the
/// legacy repository-backed NutritionDiaryView; this view never writes the legacy store itself.
struct CanonicalNutritionDiaryView: View {
    @Environment(AppStore.self) private var store
    @State private var controller: NutritionDiaryController
    @State private var editingEntry: NutritionDiaryEntry?
    @State private var showingRepair = false
    @State private var mutationError: String?

    init(coordinator: FoodJournalCoordinator,
         goalsRepository: NutritionGoalsRepository = NutritionGoalsRepository(),
         repair: LegacyDiaryRepair,
         calendar: Calendar = .autoupdatingCurrent) {
        _controller = State(initialValue: NutritionDiaryController(
            coordinator: coordinator, goalsRepository: goalsRepository, repair: repair, calendar: calendar))
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { controller.selectedDate },
            set: { controller.selectedDayKey = NutritionDiaryDayKey.make($0, calendar: controller.calendar) }
        )
    }

    var body: some View {
        @Bindable var store = store
        List {
            if let issue = controller.issue {
                issueSection(issue)
            } else {
                // A recovered journal is never silently shown as ordinary history. Non-durable
                // states (fallback/unavailable) always surface as a typed issue instead, so this
                // banner is the readable `.recovered` case, reusing the Journal's own honest copy.
                if controller.journalOpenState != .ok {
                    Section { JournalOpenStateBanner(state: controller.journalOpenState) }
                }
                diaryContent
            }
            if let mutationError {
                Section { Text(mutationError).foregroundStyle(.red).accessibilityIdentifier("nutritionDiary.error") }
            }
        }
        .navigationTitle("Food diary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.showNutritionDiaryEntry = true } label: { Label("Log food", systemImage: "plus") }
                    .accessibilityIdentifier("nutritionDiary.add")
                    .disabled(controller.issue != nil)
            }
        }
        .sheet(isPresented: $store.showNutritionDiaryEntry) {
            NavigationStack {
                NutritionDiaryEntryEditView(
                    draft: NutritionDiaryEntryDraft(dayKey: controller.selectedDayKey),
                    existing: nil,
                    calendar: controller.calendar
                ) { entry in
                    try controller.add(entry)
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                NutritionDiaryEntryEditView(
                    draft: NutritionDiaryEntryDraft(entry: entry),
                    existing: entry,
                    calendar: controller.calendar
                ) { updated in
                    try controller.update(updated)
                }
            }
        }
        .sheet(isPresented: $showingRepair, onDismiss: { controller.reload() }) {
            NavigationStack {
                LegacyDiaryRepairView(repair: controller.repairAdapter) {
                    _ = try controller.coordinator.readMeals()
                }
            }
        }
        .onAppear {
            store.bottomAddContext = .food
            controller.reload()
        }
    }

    @ViewBuilder
    private func issueSection(_ issue: NutritionDiaryIssue) -> some View {
        Section {
            switch issue {
            case .legacyRepairNeeded(let reason):
                Label("The older diary needs repair before it can move into your Journal. Nothing has been lost or changed.",
                      systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutritionDiary.repairNeeded")
                Text(reason).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                Button("Repair older diary") { showingRepair = true }
                    .accessibilityIdentifier("nutritionDiary.repair")
            case .migrationRetryNeeded(let reason):
                Label("The diary couldn't finish moving into your Journal. Nothing was lost; try again.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutritionDiary.migrationRetry")
                Text(reason).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { controller.retry() }
                    .accessibilityIdentifier("nutritionDiary.retry")
            case .readFailed(let reason):
                Label("The diary couldn't be read safely. This is not an empty diary.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutritionDiary.readFailed")
                Text(reason).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { controller.retry() }
                    .accessibilityIdentifier("nutritionDiary.retry")
            }
        }
    }

    @ViewBuilder
    private var diaryContent: some View {
        Section {
            DatePicker("Diary date", selection: selectedDateBinding, displayedComponents: .date)
                .accessibilityIdentifier("nutritionDiary.date")
        }
        Section("Daily totals") {
            let totals = controller.dayTotals
            let goals = controller.goals()
            ForEach(NutritionGoalField.allCases) { field in
                HStack {
                    Text(field.title)
                    Spacer()
                    if let amount = totals.value(for: field) {
                        Text("\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(field.unit)")
                            .monospacedDigit()
                        if let goal = goals?[field] {
                            Text("/ \(goal.formatted(.number.precision(.fractionLength(0...1))))")
                                .foregroundStyle(Theme.mutedForeground).monospacedDigit()
                        }
                    } else {
                        Text("Unavailable").foregroundStyle(Theme.mutedForeground)
                    }
                }
                .accessibilityIdentifier("nutritionDiary.total.\(field.rawValue)")
            }
            if goals?.isEmpty == true {
                NavigationLink {
                    NutritionGoalsView()
                } label: {
                    Label("Set optional daily goals", systemImage: "target")
                }
                .accessibilityIdentifier("nutritionDiary.configureGoals")
            } else if goals == nil {
                Label("Daily goals couldn't be loaded safely. Open Nutrition goals to retry.", systemImage: "exclamationmark.triangle")
                    .font(AteFont.body(12))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("nutritionDiary.goalsLoadError")
                NavigationLink {
                    NutritionGoalsView()
                } label: {
                    Label("Retry loading daily goals", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("nutritionDiary.retryGoals")
            }
        }
        Section {
            let totals = controller.weekTotals
            ForEach(NutritionGoalField.allCases) { field in
                HStack {
                    Text(field.title)
                    Spacer()
                    if let amount = totals.value(for: field) {
                        Text("\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(field.unit)")
                            .monospacedDigit()
                    } else {
                        Text("Unavailable").foregroundStyle(Theme.mutedForeground)
                    }
                }
                .accessibilityIdentifier("nutritionDiary.week.total.\(field.rawValue)")
            }
        } header: {
            Text(controller.selectedWeekIsCurrent ? "This week" : "Selected week")
        } footer: {
            if let week = controller.weekInterval {
                Text("Totals for \(week.start.formatted(date: .abbreviated, time: .omitted)) to \(week.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)), the week of the selected day. Unavailable means at least one entry that week has an unknown value; Ate never estimates it.")
            }
        }
        if controller.dayEntries.isEmpty {
            ContentUnavailableView("Nothing logged", systemImage: "fork.knife", description: Text("Add food when you’ve eaten it. Cooking a recipe never logs it automatically."))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("nutritionDiary.empty")
        } else {
            ForEach(NutritionMeal.allCases) { meal in
                let mealEntries = controller.dayEntries.filter { $0.meal == meal }
                if !mealEntries.isEmpty {
                    Section(meal.title) {
                        ForEach(mealEntries) { entry in
                            Button { editingEntry = entry } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("nutritionDiary.entry.\(entry.id.uuidString)")
                            .swipeActions {
                                Button("Delete", role: .destructive) { delete(entry) }
                                    .accessibilityIdentifier("nutritionDiary.delete.\(entry.id.uuidString)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: NutritionDiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.foodName).font(AteFont.body(16, .medium))
                Spacer()
                Text("\(entry.servings.formatted(.number.precision(.fractionLength(0...2)))) servings")
                    .foregroundStyle(Theme.mutedForeground)
            }
            Text("\(entry.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(entry.quantityUnit) · \(entry.source.title): \(entry.sourceName)")
                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            if !entry.sourceIdentifier.isEmpty {
                Text("Source ID: \(entry.sourceIdentifier)").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
            }
            if !entry.verificationNote.isEmpty {
                Text(entry.verificationNote).font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func delete(_ entry: NutritionDiaryEntry) {
        do {
            try controller.delete(id: entry.id)
            mutationError = nil
        } catch {
            // Nothing was removed; the entry stays listed and the reason is shown.
            mutationError = "The entry couldn't be deleted: \(error.localizedDescription)"
        }
    }
}

/// Add or edit one diary entry. The draft survives every failure exactly as typed: the editor
/// only dismisses after the coordinator has accepted the change. An edit preserves the entry's
/// identity and original time instant; the day picker is the deliberate, visible day move.
private struct NutritionDiaryEntryEditView: View {
    @State private var draft: NutritionDiaryEntryDraft
    let existing: NutritionDiaryEntry?
    let calendar: Calendar
    let onSave: (NutritionDiaryEntry) throws -> Void
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(draft: NutritionDiaryEntryDraft, existing: NutritionDiaryEntry?, calendar: Calendar,
         onSave: @escaping (NutritionDiaryEntry) throws -> Void) {
        _draft = State(initialValue: draft)
        self.existing = existing
        self.calendar = calendar
        self.onSave = onSave
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { NutritionDiaryDayKey.date(for: draft.dayKey, calendar: calendar) ?? calendar.startOfDay(for: .now) },
            set: { draft.dayKey = NutritionDiaryDayKey.make($0, calendar: calendar) }
        )
    }

    var body: some View {
        Form {
            Section("Food consumed") {
                TextField("Food or recipe name", text: $draft.foodName)
                    .accessibilityIdentifier("nutritionDiary.foodName")
                Picker("Meal", selection: $draft.meal) {
                    ForEach(NutritionMeal.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("nutritionDiary.meal")
                TextField("Quantity", text: $draft.quantity).keyboardType(.decimalPad)
                    .accessibilityIdentifier("nutritionDiary.quantity")
                TextField("Quantity unit", text: $draft.quantityUnit)
                    .accessibilityIdentifier("nutritionDiary.quantityUnit")
                TextField("Servings consumed", text: $draft.servings).keyboardType(.decimalPad)
                    .accessibilityIdentifier("nutritionDiary.servings")
                DatePicker("Day", selection: dayBinding, displayedComponents: .date)
                    .accessibilityIdentifier("nutritionDiary.form.day")
                if existing != nil {
                    Text("Changing the day moves this entry to that day. The original time is kept.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
            }
            Section {
                Picker("Nutrition source", selection: $draft.source) {
                    ForEach(NutritionEntrySource.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("nutritionDiary.source")
                TextField("Source name", text: $draft.sourceName)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("nutritionDiary.sourceName")
                TextField("Source record ID (optional)", text: $draft.sourceIdentifier)
                    .accessibilityIdentifier("nutritionDiary.sourceIdentifier")
                TextField("Preparation or source-match note (optional)", text: $draft.verificationNote, axis: .vertical)
                    .accessibilityIdentifier("nutritionDiary.verificationNote")
            } header: { Text("Source and provenance") } footer: {
                Text("Record where these values came from. Ate does not independently verify external values. Blank nutrients stay unavailable; Ate does not estimate them.")
            }
            Section {
                ForEach(NutritionGoalField.allCases) { field in
                    HStack {
                        TextField("\(field.title) per serving", text: valueBinding(field))
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("nutritionDiary.nutrient.\(field.rawValue)")
                        Text(field.unit).foregroundStyle(Theme.mutedForeground)
                    }
                }
            } header: { Text("Nutrients per serving (optional)") } footer: {
                Text("Enter only values you can verify from the source. Each logged entry keeps this snapshot if the source changes later.")
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("nutritionDiary.formError") } }
        }
        .navigationTitle(existing == nil ? "Log food" : "Edit food")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.source) { _, newSource in
            draft.sourceName = newSource.suggestedSourceName
            errorMessage = nil
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.accessibilityIdentifier("nutritionDiary.save")
            }
        }
    }

    private func valueBinding(_ field: NutritionGoalField) -> Binding<String> {
        Binding(get: { draft.nutrientText[field] ?? "" }, set: { draft.nutrientText[field] = $0 })
    }

    private func save() {
        switch draft.parsedEntry(existing: existing, calendar: calendar) {
        case .failure(let error):
            errorMessage = error.message
        case .success(let entry):
            do {
                try onSave(entry)
                dismiss()
            } catch {
                // The draft stays exactly as typed; only a fully saved change dismisses the editor.
                errorMessage = "The change wasn't saved: \(error.localizedDescription)"
            }
        }
    }
}
