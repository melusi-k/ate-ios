import SwiftUI

/// Presented only after migration failure; not a permanent second diary or fallback logger.
struct LegacyDiaryRepairView: View {
    let repair: LegacyDiaryRepair
    let retryMigration: () throws -> Void
    @State private var snapshot: LegacyDiaryRepairSnapshot?
    @State private var message: String?
    @State private var editingIndex: Int?
    @State private var removingIndex: Int?
    @State private var undecodable = false
    @State private var confirmRecovery = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("These older diary records have not migrated. Repair or remove a record, then retry. Before each change, Ate keeps a byte-for-byte backup on this iPhone.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot {
                ForEach(Array(snapshot.entries.enumerated()), id: \.offset) { index, entry in
                    VStack(alignment: .leading) {
                        Text(entry.foodName.isEmpty ? "Unnamed food" : entry.foodName)
                        Text(entry.dayKey).font(.caption)
                        if snapshot.invalidIndices.contains(index) { Text("Needs repair").foregroundStyle(.red) }
                        if snapshot.duplicateIndices.contains(index) { Text("Duplicate identity: remove the unwanted copy").foregroundStyle(.red) }
                        HStack {
                            Button("Edit") { editingIndex = index }
                            Button("Remove", role: .destructive) { removingIndex = index }
                        }.buttonStyle(.borderless)
                    }
                    .accessibilityIdentifier("legacyDiary.repair.row.\(index)")
                }
            }
            if undecodable {
                Button("Back up and reset unreadable older diary", role: .destructive) { confirmRecovery = true }
                    .accessibilityIdentifier("legacyDiary.repair.recover")
            }
            if let message { Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("legacyDiary.repair.error") } }
            Section {
                Button("Retry migration") {
                    do { try retryMigration(); dismiss() }
                    catch { message = "Migration is still blocked: \(error.localizedDescription)"; reload() }
                }.accessibilityIdentifier("legacyDiary.repair.retry")
            }
        }
        .navigationTitle("Repair older diary")
        .task { reload() }
        .confirmationDialog("Remove this older diary record? A backup will be kept.", isPresented: Binding(
            get: { removingIndex != nil }, set: { if !$0 { removingIndex = nil } })) {
            Button("Remove record", role: .destructive) {
                guard let index = removingIndex, let snapshot else { return }
                do { try repair.remove(index: index, from: snapshot); message = nil; reload() }
                catch { message = "The record wasn't removed: \(error.localizedDescription)" }
                removingIndex = nil
            }
        }
        .alert("Back up and reset the unreadable older diary?", isPresented: $confirmRecovery) {
            Button("Cancel", role: .cancel) { }
            Button("Back up and reset", role: .destructive) {
                do { try repair.backUpAndResetUndecodableData(); undecodable = false; message = nil; reload() }
                catch { message = "The older diary wasn't reset: \(error.localizedDescription)" }
            }
        } message: {
            Text("Ate will keep the exact unreadable bytes in a backup on this iPhone before removing the old diary. This cannot restore records from those unreadable bytes. Your existing Journal is not cleared. Retry migration afterward.")
        }
        .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
            if let index = editingIndex, let snapshot, snapshot.entries.indices.contains(index) {
                NavigationStack {
                    LegacyDiaryRepairEditor(original: snapshot.entries[index]) { replacement in
                        try repair.replace(index: index, with: replacement, in: snapshot)
                        message = nil
                        reload()
                    }
                }
            }
        }
    }
    private func reload() {
        do { snapshot = try repair.snapshot(); undecodable = false }
        catch LegacyDiaryRepairError.undecodable { snapshot = nil; undecodable = true; message = "These older records couldn't be decoded. Back up and reset only if you want to remove the unreadable old diary." }
        catch LegacyDiaryRepairError.unavailable { snapshot = nil; undecodable = false }
        catch { snapshot = nil; undecodable = false; message = "Older diary records couldn't be loaded: \(error.localizedDescription)" }
    }
}

private struct LegacyDiaryRepairEditor: View {
    let original: NutritionDiaryEntry
    let save: (NutritionDiaryEntry) throws -> Void
    @State private var draft: NutritionDiaryEntry
    @State private var nutrientText: [NutritionGoalField: String]
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    init(original: NutritionDiaryEntry, save: @escaping (NutritionDiaryEntry) throws -> Void) {
        self.original = original; self.save = save
        _draft = State(initialValue: original)
        _nutrientText = State(initialValue: Dictionary(uniqueKeysWithValues: NutritionGoalField.allCases.map {
            ($0, original.nutrientsPerServing[$0].map { String($0) } ?? "")
        }))
    }
    var body: some View {
        Form {
            TextField("Food name", text: $draft.foodName)
            TextField("Day (YYYY-MM-DD)", text: $draft.dayKey)
            Picker("Meal", selection: $draft.meal) { ForEach(NutritionMeal.allCases) { Text($0.title).tag($0) } }
            TextField("Quantity", value: $draft.quantity, format: .number).keyboardType(.decimalPad)
            TextField("Unit", text: $draft.quantityUnit)
            TextField("Servings", value: $draft.servings, format: .number).keyboardType(.decimalPad)
            Picker("Source", selection: $draft.source) { ForEach(NutritionEntrySource.allCases) { Text($0.title).tag($0) } }
            TextField("Source name", text: $draft.sourceName)
            TextField("Source record ID", text: $draft.sourceIdentifier)
            TextField("Source note", text: $draft.verificationNote)
            Section("Nutrients per serving") {
                ForEach(NutritionGoalField.allCases) { field in
                    TextField(field.title, text: Binding(get: { nutrientText[field] ?? "" }, set: { nutrientText[field] = $0 }))
                        .keyboardType(.decimalPad)
                }
                Text("Blank means unknown. Existing values and provenance are retained unless you change them.")
            }
            if let message { Text(message).foregroundStyle(.red) }
        }
        .navigationTitle("Repair record")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { commit() } }
        }
    }
    private func commit() {
        var values: [NutritionGoalField: Double] = [:]
        for field in NutritionGoalField.allCases {
            let text = (nutrientText[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let value = NutritionDiaryNumber.parse(text), value >= 0 else { message = "Enter a valid nonnegative nutrient value, or leave it blank."; return }
            values[field] = value
        }
        draft.nutrientsPerServing = NutritionSnapshot(energyKcal: values[.energy], proteinGrams: values[.protein],
            carbohydratesGrams: values[.carbohydrates], fatGrams: values[.fat], fibreGrams: values[.fibre])
        guard FoodJournalStore.validMeal(draft) else { message = "Check the food name, day, amount, servings and source name."; return }
        do { try save(draft); dismiss() }
        catch { message = "The change wasn't saved: \(error.localizedDescription)" }
    }
}
