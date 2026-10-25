import SwiftUI

struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: [NutritionGoalField: Bool] = [:]
    @State private var values: [NutritionGoalField: String] = [:]
    @State private var errors: [NutritionGoalField: String] = [:]
    @State private var saveError: String?
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

            Section {
                Button("Clear all goals", role: .destructive) { clearAll() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("nutritionGoals.clearAll")
                    .accessibilityHint("Turns off every goal in this form. Tap Save goals to confirm the change.")
            } footer: {
                Text("Clearing goals changes this draft only until you tap Save goals.")
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
        .navigationBarTitleDisplayMode(.inline)
        .task { loadDraftIfNeeded() }
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
        let saved = repository.load()
        for field in NutritionGoalField.allCases {
            if let value = saved[field] {
                enabled[field] = true
                values[field] = Self.displayValue(value, field: field)
            } else {
                enabled[field] = false
                values[field] = ""
            }
        }
        didLoad = true
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
