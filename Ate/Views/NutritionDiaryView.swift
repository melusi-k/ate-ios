import SwiftUI

struct NutritionDiaryView: View {
    @Environment(AppStore.self) private var store
    @State private var entries: [NutritionDiaryEntry] = []
    @State private var selectedDayKey = NutritionDiaryDayKey.make(.now)
    @State private var errorMessage: String?
    @State private var diaryDataCorrupt = false
    @State private var showingRecoveryConfirmation = false
    @State private var recoveryNotice: String?
    @State private var recoveryFailure: String?
    /// Goals drive the daily-totals rows and the configure prompt. Keep them in state:
    /// reading storage during body evaluation goes stale when a reset or a goals-screen
    /// edit does not change any other state on this screen (#179).
    @State private var dailyGoals: DailyNutritionGoals?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let repository: NutritionDiaryRepository
    private let goalsRepository: NutritionGoalsRepository

    init(repository: NutritionDiaryRepository = NutritionDiaryRepository(), goalsRepository: NutritionGoalsRepository = NutritionGoalsRepository()) {
        self.repository = repository
        self.goalsRepository = goalsRepository
        _dailyGoals = State(initialValue: try? goalsRepository.load())
    }

    private var dayEntries: [NutritionDiaryEntry] {
        entries.filter { $0.dayKey == selectedDayKey }
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { NutritionDiaryDayKey.date(for: selectedDayKey) ?? Calendar.autoupdatingCurrent.startOfDay(for: .now) },
            set: { selectedDayKey = NutritionDiaryDayKey.make($0) }
        )
    }

    private var selectedDate: Date {
        selectedDateBinding.wrappedValue
    }

    var body: some View {
        @Bindable var store = store
        List {
            if diaryDataCorrupt {
                Section {
                    Label("Food diary data couldn't be read safely. Logging and saving are disabled until the data is backed up and reset.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutritionDiary.corruptDataError")
                    Button("Back up and reset diary…", role: .destructive) {
                        showingRecoveryConfirmation = true
                    }
                    .accessibilityIdentifier("nutritionDiary.recoverCorruptData")
                }
            }
            if let recoveryNotice {
                Section {
                    Label(recoveryNotice, systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutritionDiary.recoveryNotice")
                }
            }
            if let recoveryFailure {
                Section {
                    Label(recoveryFailure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutritionDiary.recoveryError")
                }
            }
            Section {
                DatePicker("Diary date", selection: selectedDateBinding, displayedComponents: .date)
                    .accessibilityIdentifier("nutritionDiary.date")
            }
            Section("Daily totals") {
                let totals = NutritionDayTotals.calculate(entries: dayEntries)
                let goals = dailyGoals
                ForEach(NutritionGoalField.allCases) { field in
                    // At accessibility sizes a squeezed value wraps mid-word beside the
                    // label (CI AX5 pixel evidence: "Un-avail-able", #179), so stack the
                    // label over the value instead of one squeezed HStack.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.title)
                            totalsValue(field, totals: totals, goals: goals)
                        }
                        .accessibilityIdentifier("nutritionDiary.total.\(field.rawValue)")
                    } else {
                        HStack {
                            Text(field.title)
                            Spacer()
                            totalsValue(field, totals: totals, goals: goals)
                        }
                        .accessibilityIdentifier("nutritionDiary.total.\(field.rawValue)")
                    }
                }
                if goals?.isEmpty == true {
                    NavigationLink(value: Route.nutritionGoals) {
                        // A Label with an SF symbol stays compact instead of supporting
                        // every Dynamic Type step (audit: DT partially unsupported + text
                        // clipped, #179); separate Image + Text scale fully.
                        HStack {
                            Image(systemName: "target")
                                .foregroundStyle(.tint)
                            Text("Set optional daily goals")
                                // Wrap with no line cap: a 2-line limit still clipped at
                                // the largest Dynamic Type sizes (accessibility audit, #179).
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("nutritionDiary.configureGoals")
                } else if goals == nil {
                    Label("Daily goals couldn't be loaded safely. Open Nutrition goals to retry.", systemImage: "exclamationmark.triangle")
                        .font(AteFont.body(12))
                        .foregroundStyle(Theme.mutedForeground)
                        .accessibilityIdentifier("nutritionDiary.goalsLoadError")
                    NavigationLink(value: Route.nutritionGoals) {
                        Label("Retry loading daily goals", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("nutritionDiary.retryGoals")
                }
            }
            if dayEntries.isEmpty {
                ContentUnavailableView("Nothing logged", systemImage: "fork.knife", description: Text("Add food when you’ve eaten it. Cooking a recipe never logs it automatically."))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("nutritionDiary.empty")
            } else {
                ForEach(NutritionMeal.allCases) { meal in
                    let mealEntries = dayEntries.filter { $0.meal == meal }
                    if !mealEntries.isEmpty {
                        Section(meal.title) {
                            ForEach(mealEntries) { entry in
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
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("nutritionDiary.error") }
            }
            // The pushed-screen bottom chrome (cook mini-player / timer bar) is a
            // safe-area inset this List measurably ignores (CI pixel evidence: the
            // capsule overlays rows at AX5, #179), so reserve real scrollable space
            // while it is up. Height: capsule measured ~94pt tall at AX5 before the
            // two-line wrap, ~52pt at default; 130/72 covers the wrap with margin and
            // is pixel-verified against the next run's screenshots.
            if store.cookTarget == nil && (store.cookSession != nil || !store.timers.timers.isEmpty) {
                Section {
                    Color.clear
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 130 : 72)
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                }
            }
        }
        // Pushed screen: hide the tab bar so list content never rests behind it.
        // safeAreaPadding/contentMargins measurably did NOT inset this list (A/B pixel
        // diff of runs with and without the modifier: only the status-bar clock changed;
        // the list's UICollectionView frame stayed {0,0,402,874} in the AX hierarchy).
        // RecipeDetailView already hides the bar for the same reason (#179).
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Food diary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.showNutritionDiaryEntry = true } label: { Label("Log food", systemImage: "plus") }
                    .accessibilityIdentifier("nutritionDiary.add")
                    .disabled(diaryDataCorrupt)
            }
        }
        .sheet(isPresented: $store.showNutritionDiaryEntry) {
            NavigationStack {
                NutritionDiaryEntryForm(date: selectedDate, dayKey: selectedDayKey) { entry in
                    entries.append(entry)
                    persist()
                    store.showNutritionDiaryEntry = false
                }
            }
        }
        .onAppear {
            store.bottomAddContext = .food
            if ProcessInfo.processInfo.arguments.contains("-resetNutritionDiary") {
                UserDefaults.standard.removeObject(forKey: NutritionDiaryRepository.storageKey)
            }
            // UI-test-only hooks (#179 state coverage). Every new argument is gated on -UITesting so a
            // normal launch can never reset, seed or fail user data.
            if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-resetNutritionGoals") {
                UserDefaults.standard.removeObject(forKey: DailyNutritionGoals.defaultsKey)
                try? NutritionGoalsRepository().storage.remove()
            }
            if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-seedCorruptNutritionDiary") {
                UserDefaults.standard.set(Data("qa-corrupt-diary".utf8), forKey: NutritionDiaryRepository.storageKey)
            }
            if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-seedCorruptNutritionGoals") {
                try? NutritionGoalsRepository().storage.write(Data("qa-corrupt-goals".utf8))
            }
            reloadDiary()
        }
        .alert("Back up and reset diary?", isPresented: $showingRecoveryConfirmation) {
            Button("Back up and reset", role: .destructive) { recoverDiary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The unreadable diary data is saved to a backup file on this device, then removed from the diary. The backup file is kept for support.")
        }
    }

    private func reloadDiary() {
        dailyGoals = try? goalsRepository.load()
        switch repository.loadState() {
        case .loaded(let loaded):
            entries = loaded
            diaryDataCorrupt = false
        case .absent:
            entries = []
            diaryDataCorrupt = false
        case .corrupt:
            entries = []
            diaryDataCorrupt = true
        }
    }

    private func recoverDiary() {
        do {
            try repository.recoverCorruptData()
            recoveryNotice = "The unreadable diary was backed up to a file on this device and reset."
            recoveryFailure = nil
            reloadDiary()
        } catch {
            recoveryFailure = "The diary couldn't be reset safely. Please try again."
        }
    }

    @ViewBuilder private func totalsValue(_ field: NutritionGoalField, totals: NutritionDayTotals, goals: DailyNutritionGoals?) -> some View {
        if let amount = totals.value(for: field) {
            HStack(spacing: 4) {
                Text("\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(field.unit)")
                    .monospacedDigit()
                if let goal = goals?[field] {
                    Text("/ \(goal.formatted(.number.precision(.fractionLength(0...1))))")
                        .foregroundStyle(Theme.mutedForeground).monospacedDigit()
                }
            }
        } else {
            Text("Unavailable").foregroundStyle(Theme.mutedForeground)
        }
    }

    private func delete(_ entry: NutritionDiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        // UI-test-only fault injection (#179 save-failure state); gated on -UITesting.
        // Every save fails while the argument is present; remove the argument to recover.
        if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-failDiarySaves") {
            errorMessage = "Your diary couldn’t be saved. Please try again."
            return
        }
        do { try repository.save(entries); errorMessage = nil }
        catch let error as NutritionDiaryLoadError {
            diaryDataCorrupt = true
            errorMessage = error.errorDescription
        } catch { errorMessage = "Your diary couldn’t be saved. Please try again." }
    }
}

private struct NutritionDiaryEntryForm: View {
    let date: Date
    let dayKey: String
    let onSave: (NutritionDiaryEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var foodName = ""
    @State private var meal: NutritionMeal = .lunch
    @State private var quantity = "1"
    @State private var quantityUnit = "serving"
    @State private var servings = "1"
    @State private var source: NutritionEntrySource = .userProvided
    @State private var sourceName = "You"
    @State private var sourceIdentifier = ""
    @State private var verificationNote = ""
    @State private var nutrientText: [NutritionGoalField: String] = [:]
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // Validation errors belong at the top: with the keyboard up, a message rendered
            // at the bottom of this long form is hidden exactly when the user needs it.
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("nutritionDiary.formError") } }
            Section("Food consumed") {
                TextField("Food or recipe name", text: $foodName)
                    .accessibilityIdentifier("nutritionDiary.foodName")
                Picker("Meal", selection: $meal) {
                    ForEach(NutritionMeal.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("nutritionDiary.meal")
                TextField("Quantity", text: $quantity).keyboardType(.decimalPad)
                    .accessibilityIdentifier("nutritionDiary.quantity")
                TextField("Quantity unit", text: $quantityUnit)
                    .accessibilityIdentifier("nutritionDiary.quantityUnit")
                TextField("Servings consumed", text: $servings).keyboardType(.decimalPad)
                    .accessibilityIdentifier("nutritionDiary.servings")
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
            }
            Section {
                Picker("Nutrition source", selection: $source) {
                    ForEach(NutritionEntrySource.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("nutritionDiary.source")
                TextField("Source name", text: $sourceName)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("nutritionDiary.sourceName")
                TextField("Source record ID (optional)", text: $sourceIdentifier)
                    .accessibilityIdentifier("nutritionDiary.sourceIdentifier")
                TextField("Preparation or source-match note (optional)", text: $verificationNote, axis: .vertical)
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
        }
        // The decimal-pad fields have no return key; let a scroll dismiss the keyboard so
        // it cannot trap itself over the lower form.
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log food")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: source) { _, newSource in
            sourceName = newSource.suggestedSourceName
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
        Binding(get: { nutrientText[field] ?? "" }, set: { nutrientText[field] = $0 })
    }

    private func save() {
        let normalized = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let servingValue = servings.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quantityValue = NutritionDiaryNumber.parse(normalized),
              let servingCount = NutritionDiaryNumber.parse(servingValue),
              quantityValue.isFinite, quantityValue > 0, servingCount.isFinite, servingCount > 0 else {
            errorMessage = "Enter a quantity and servings greater than zero."
            return
        }
        var values: [NutritionGoalField: Double] = [:]
        for field in NutritionGoalField.allCases {
            let text = (nutrientText[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let value = NutritionDiaryNumber.parse(text), value >= 0 else {
                errorMessage = "Enter a valid non-negative value for each nutrient, or leave it blank."
                return
            }
            values[field] = value
        }
        let snapshot = NutritionSnapshot(energyKcal: values[.energy], proteinGrams: values[.protein],
                                         carbohydratesGrams: values[.carbohydrates], fatGrams: values[.fat],
                                         fibreGrams: values[.fibre])
        let entry = NutritionDiaryEntry(
            foodName: foodName, date: date, meal: meal, quantity: quantityValue, quantityUnit: quantityUnit,
            servings: servingCount, source: source, sourceName: sourceName, sourceIdentifier: sourceIdentifier,
            verificationNote: verificationNote, nutrientsPerServing: snapshot, dayKey: dayKey
        )
        guard NutritionDiaryValidation.isValid(entry) else {
            errorMessage = source.accepts(sourceName: sourceName)
                ? "Enter a food name and quantity unit."
                : "Enter a source name that matches the selected nutrition source."
            return
        }
        onSave(entry)
    }
}
