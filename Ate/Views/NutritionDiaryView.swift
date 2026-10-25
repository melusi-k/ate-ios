import SwiftUI

struct NutritionDiaryView: View {
    @State private var entries: [NutritionDiaryEntry] = []
    @State private var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: .now)
    @State private var showingAddEntry = false
    @State private var errorMessage: String?
    private let repository: NutritionDiaryRepository
    private let goalsRepository: NutritionGoalsRepository

    init(repository: NutritionDiaryRepository = NutritionDiaryRepository(), goalsRepository: NutritionGoalsRepository = NutritionGoalsRepository()) {
        self.repository = repository
        self.goalsRepository = goalsRepository
    }

    private var dayEntries: [NutritionDiaryEntry] {
        entries.filter { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        List {
            Section {
                DatePicker("Diary date", selection: $selectedDate, displayedComponents: .date)
                    .accessibilityIdentifier("nutritionDiary.date")
            }
            Section("Daily totals") {
                let totals = NutritionDayTotals.calculate(entries: dayEntries)
                let goals = goalsRepository.load()
                ForEach(NutritionGoalField.allCases) { field in
                    HStack {
                        Text(field.title)
                        Spacer()
                        if let amount = totals.value(for: field) {
                            Text("\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(field.unit)")
                                .monospacedDigit()
                            if let goal = goals[field] {
                                Text("/ \(goal.formatted(.number.precision(.fractionLength(0...1))))")
                                    .foregroundStyle(Theme.mutedForeground).monospacedDigit()
                            }
                        } else {
                            Text("Unavailable").foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .accessibilityIdentifier("nutritionDiary.total.\(field.rawValue)")
                }
                if goals.isEmpty {
                    NavigationLink {
                        NutritionGoalsView()
                    } label: {
                        Label("Set optional daily goals", systemImage: "target")
                    }
                    .accessibilityIdentifier("nutritionDiary.configureGoals")
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
        }
        .navigationTitle("Food diary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddEntry = true } label: { Label("Log food", systemImage: "plus") }
                    .accessibilityIdentifier("nutritionDiary.add")
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            NavigationStack {
                NutritionDiaryEntryForm(date: selectedDate) { entry in
                    entries.append(entry)
                    persist()
                    showingAddEntry = false
                }
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-resetNutritionDiary") {
                UserDefaults.standard.removeObject(forKey: NutritionDiaryRepository.storageKey)
            }
            entries = repository.load()
        }
    }

    private func delete(_ entry: NutritionDiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        do { try repository.save(entries); errorMessage = nil }
        catch { errorMessage = "Your diary couldn’t be saved. Please try again." }
    }
}

private struct NutritionDiaryEntryForm: View {
    let date: Date
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
        guard let quantityValue = Double(normalized), let servingCount = Double(servingValue),
              quantityValue.isFinite, quantityValue > 0, servingCount.isFinite, servingCount > 0 else {
            errorMessage = "Enter a quantity and servings greater than zero."
            return
        }
        var values: [NutritionGoalField: Double] = [:]
        for field in NutritionGoalField.allCases {
            let text = (nutrientText[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let value = Double(text), value.isFinite, value >= 0 else {
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
            verificationNote: verificationNote, nutrientsPerServing: snapshot
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
