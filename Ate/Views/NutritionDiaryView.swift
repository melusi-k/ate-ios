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
    @State private var editingEntry: NutritionDiaryEntry?
    private let repository: NutritionDiaryRepository
    private let goalsRepository: NutritionGoalsRepository

    init(repository: NutritionDiaryRepository = NutritionDiaryRepository(), goalsRepository: NutritionGoalsRepository = NutritionGoalsRepository()) {
        self.repository = repository
        self.goalsRepository = goalsRepository
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
                let goals = try? goalsRepository.load()
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
                                    Button("Edit") { editingEntry = entry }
                                        .accessibilityIdentifier("nutritionDiary.edit.\(entry.id.uuidString)")
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
        }
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
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                NutritionDiaryEntryForm(date: entry.date, dayKey: entry.dayKey, existing: entry) { updated in
                    if let index = entries.firstIndex(where: { $0.id == updated.id }) {
                        entries[index] = updated
                    }
                    persist()
                    editingEntry = nil
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
    let existing: NutritionDiaryEntry?
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

    /// Seeds a new form, or every field from an entry being edited (#179 edit behaviour).
    init(date: Date, dayKey: String, existing: NutritionDiaryEntry? = nil,
         onSave: @escaping (NutritionDiaryEntry) -> Void) {
        self.date = existing?.date ?? date
        self.dayKey = existing?.dayKey ?? dayKey
        self.existing = existing
        self.onSave = onSave
        _foodName = State(initialValue: existing?.foodName ?? "")
        _meal = State(initialValue: existing?.meal ?? .lunch)
        _quantity = State(initialValue: existing.map { Self.numberText($0.quantity) } ?? "1")
        _quantityUnit = State(initialValue: existing?.quantityUnit ?? "serving")
        _servings = State(initialValue: existing.map { Self.numberText($0.servings) } ?? "1")
        _source = State(initialValue: existing?.source ?? .userProvided)
        _sourceName = State(initialValue: existing?.sourceName ?? "You")
        _sourceIdentifier = State(initialValue: existing?.sourceIdentifier ?? "")
        _verificationNote = State(initialValue: existing?.verificationNote ?? "")
        var nutrients: [NutritionGoalField: String] = [:]
        if let existing {
            for field in NutritionGoalField.allCases {
                if let value = existing.nutrientsPerServing[field] {
                    nutrients[field] = Self.numberText(value)
                }
            }
        }
        _nutrientText = State(initialValue: nutrients)
        _errorMessage = State(initialValue: nil)
    }

    /// Shortest round-trippable form: editing and saving without touching a field must
    /// never lose precision, and no grouping separator may enter the decimal pad.
    /// NutritionDiaryNumber.parse accepts the period separator in any locale.
    private static func numberText(_ value: Double) -> String {
        String(value)
    }

    var body: some View {
        Form {
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
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("nutritionDiary.formError") } }
        }
        .navigationTitle(existing == nil ? "Log food" : "Edit food")
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
            id: existing?.id ?? UUID(),
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
