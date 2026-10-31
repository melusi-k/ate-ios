import SwiftUI

struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: [NutritionGoalField: Bool] = [:]
    @State private var values: [NutritionGoalField: String] = [:]
    @State private var errors: [NutritionGoalField: String] = [:]
    @State private var saveError: String?
    @State private var loadError: String?
    @State private var canRecoverCorruptData = false
    @State private var showingRecoveryConfirmation = false
    @State private var recoveryError: String?
    @State private var recoveryNotice: String?
    @State private var didLoad = false

    private let repository: NutritionGoalsRepository

    init(repository: NutritionGoalsRepository = NutritionGoalsRepository()) {
        self.repository = repository
    }

    var body: some View {
        Form {
            Section {
                Text("Set targets for a typical day. Every goal is optional; these are your personal targets, not recommendations.")
                    .font(AteFont.body(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutritionGoals.intro")
            }

            Section("Daily targets") {
                ForEach(NutritionGoalField.allCases) { field in
                    goalRow(field)
                }
            }
            .disabled(!didLoad)

            Section {
                Button("Clear all goals", role: .destructive) { clearAll() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!didLoad)
                    .accessibilityIdentifier("nutritionGoals.clearAll")
                    .accessibilityHint("Turns off every goal in this form. Tap Save goals to confirm the change.")
            } footer: {
                Text("Clearing goals changes this draft only until you tap Save goals.")
                    // Explicit scalable font and free vertical growth for every Dynamic
                    // Type size (accessibility audit, #179).
                    .font(AteFont.body(12))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutritionGoals.clearAllHint")
            }

            Section {
                Button("Save goals") { save() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!didLoad)
                    .accessibilityIdentifier("nutritionGoals.save")
                Button("Cancel", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("nutritionGoals.cancel")
            }

            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutritionGoals.loadError")
                    Button("Retry loading goals") { loadDraftIfNeeded() }
                        .accessibilityIdentifier("nutritionGoals.retryLoad")
                    if canRecoverCorruptData {
                        Button("Back up and reset goals…", role: .destructive) {
                            showingRecoveryConfirmation = true
                        }
                        .accessibilityIdentifier("nutritionGoals.recoverCorruptData")
                    }
                }
            }

            if let recoveryNotice {
                Section {
                    Label(recoveryNotice, systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutritionGoals.recoveryNotice")
                }
            }

            if let recoveryError {
                Section {
                    Label(recoveryError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutritionGoals.recoveryError")
                }
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("nutritionGoals.saveError")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Nutrition goals")
        // Pushed screen: hide the tab bar so the Save/Cancel actions never rest behind it
        // (Cancel was rendered faded behind the bar at ~818pt; the bar spans y791-874).
        // safeAreaPadding(.bottom, 96) provably did not inset pushed-screen content
        // (diary A/B pixel diff, #179); RecipeDetailView already hides the bar instead.
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Back up and reset unreadable goals?", isPresented: $showingRecoveryConfirmation, titleVisibility: .visible) {
            Button("Back up and reset", role: .destructive) { recoverCorruptData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A private local copy of the unreadable data will be saved before the broken configuration is removed. If the backup cannot be saved, no data will be reset.")
        }
        .task {
            // UI-test-only hook (#179 state coverage), gated on -UITesting like the diary
            // hooks: reset leftover goal state before loading the draft so suites are isolated.
            if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-resetNutritionGoals") {
                UserDefaults.standard.removeObject(forKey: DailyNutritionGoals.defaultsKey)
                try? NutritionGoalsRepository().storage.remove()
            }
            loadDraftIfNeeded()
        }
    }

    @ViewBuilder
    private func goalRow(_ field: NutritionGoalField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: binding(for: field)) {
                Text(field.title)
                    .font(AteFont.body(16, .medium))
            }
            .tint(Theme.primary)
            .accessibilityLabel("Set \(field.accessibilityName)")
            .accessibilityHint("Turn on to enter an optional daily target.")
            .accessibilityIdentifier("nutritionGoals.enabled.\(field.rawValue)")

            if enabled[field] == true {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Enter target", text: valueBinding(for: field))
                        .keyboardType(.decimalPad)
                        .textContentType(.none)
                        .accessibilityLabel(field.accessibilityName)
                        .accessibilityHint(field == .energy ? "Enter a whole number of kilocalories." : "Enter a number of grams, with up to one decimal place.")
                        .accessibilityIdentifier("nutritionGoals.value.\(field.rawValue)")
                    Text(field.unit)
                        .foregroundStyle(Theme.mutedForeground)
                        .accessibilityHidden(true)
                }
                if let message = errors[field] {
                    Text(message)
                        .font(AteFont.body(12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(field.title): \(message)")
                        .accessibilityIdentifier("nutritionGoals.error.\(field.rawValue)")
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: enabled[field]) { _, isEnabled in
            if isEnabled != true { errors[field] = nil }
        }
    }

    private func binding(for field: NutritionGoalField) -> Binding<Bool> {
        Binding(
            get: { enabled[field] ?? false },
            set: { enabled[field] = $0 }
        )
    }

    private func valueBinding(for field: NutritionGoalField) -> Binding<String> {
        Binding(
            get: { values[field] ?? "" },
            set: {
                values[field] = $0
                errors[field] = nil
                saveError = nil
            }
        )
    }

    private func clearAll() {
        for field in NutritionGoalField.allCases {
            enabled[field] = false
            values[field] = ""
            errors[field] = nil
        }
        saveError = nil
    }

    private func loadDraftIfNeeded() {
        guard !didLoad else { return }
        loadError = nil
        recoveryError = nil
        do {
            applyDraft(try repository.load())
            didLoad = true
            canRecoverCorruptData = false
        } catch let error as NutritionGoalsLoadError {
            if let fallback = error.fallbackGoals {
                applyDraft(fallback)
            }
            // Keep didLoad false so Save/Clear remain disabled until storage loads successfully.
            canRecoverCorruptData = error.canRecoverCorruptData
            loadError = error.localizedDescription
        } catch {
            loadError = "Existing nutrition goals couldn't be loaded safely. Saving is disabled to protect existing data. Retry loading or cancel."
        }
    }

    private func recoverCorruptData() {
        recoveryError = nil
        recoveryNotice = nil
        do {
            try repository.recoverCorruptData()
            didLoad = false
            loadDraftIfNeeded()
            recoveryNotice = "Unreadable nutrition-goals data was backed up locally before reset."
        } catch {
            recoveryError = "The unreadable data couldn't be backed up safely, so nothing was reset. Check available storage and try again."
        }
    }

    private func applyDraft(_ saved: DailyNutritionGoals) {
        for field in NutritionGoalField.allCases {
            if let value = saved[field] {
                enabled[field] = true
                values[field] = Self.displayValue(value, field: field)
            } else {
                enabled[field] = false
                values[field] = ""
            }
        }
    }

    private func save() {
        errors = [:]
        saveError = nil

        var goals = DailyNutritionGoals(
            energyKcal: nil,
            proteinGrams: nil,
            carbohydratesGrams: nil,
            fatGrams: nil,
            fibreGrams: nil
        )
        for field in NutritionGoalField.allCases where enabled[field] == true {
            let text = values[field] ?? ""
            if let error = NutritionGoalValidation.error(for: field, text: text) {
                errors[field] = error
            } else {
                goals[field] = NutritionGoalValidation.number(from: text)
            }
        }
        guard errors.isEmpty else { return }

        do {
            try repository.save(goals)
            dismiss()
        } catch {
            saveError = "Your goals couldn't be saved. Your previous saved goals are unchanged. Please try again."
        }
    }

    private static func displayValue(_ value: Double, field: NutritionGoalField) -> String {
        if field == .energy { return String(Int(value)) }
        return value.formatted(.number.locale(Locale.current).precision(.fractionLength(0...1)))
    }
}

#Preview {
    NavigationStack {
        NutritionGoalsView(repository: NutritionGoalsRepository(defaults: UserDefaults(suiteName: "nutrition-goals-preview")!))
    }
}
