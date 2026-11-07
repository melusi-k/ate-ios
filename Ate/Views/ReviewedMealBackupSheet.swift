import SwiftUI

/// Explicit review of one selected backup. A failed/uncertain attempt cannot be
/// submitted again from this sheet; the user first reviews the Journal's state.
struct ReviewedMealBackupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let backup: ReviewedMealBackup
    let restore: () throws -> Int
    @State private var attempted = false
    @State private var result: String?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This imports meals only, not reflections, photos or nutrition goals. Existing identical records are skipped. A conflicting record stops the import. An exact copy of this backup is kept on this iPhone before import.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Review these \(backup.entries.count) meal summaries. Expand a meal for its recorded details.")
                }
                Section("Meal records") {
                    ForEach(backup.entries) { entry in
                        DisclosureGroup {
                            Text("Recorded at: \(entry.date.formatted(.iso8601))")
                            Text("Quantity: \(entry.quantity.formatted()) \(entry.quantityUnit)")
                            Text("Servings: \(entry.servings.formatted())")
                            Text("Source: \(entry.sourceName)")
                            if let sourceID = entry.sourceIdentifier { Text("Source identifier: \(sourceID)") }
                            if let note = entry.verificationNote { Text("Verification note: \(note)") }
                            ForEach(NutritionGoalField.allCases) { field in
                                if let amount = entry.nutrientsPerServing[field] {
                                    Text("\(field.title) per serving: \(amount.formatted()) \(field.unit)")
                                } else { Text("\(field.title) per serving: unknown") }
                            }
                            Text("Record ID: \(entry.id.uuidString)").font(.caption)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.foodName)
                                Text("\(entry.dayKey) · \(entry.meal.rawValue) · \(entry.servings.formatted()) servings")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let result { Section { Text(result).accessibilityIdentifier("mealBackup.result") } }
                if let failure { Section { Text(failure).foregroundStyle(.red).accessibilityIdentifier("mealBackup.failure") } }
            }
            .navigationTitle("Review meal backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(attempted ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import meals") {
                        attempted = true
                        do { result = "Imported \(try restore()) new meal records. Review the Journal to confirm the result." }
                        catch { failure = error.localizedDescription }
                    }
                    .disabled(attempted)
                    .accessibilityIdentifier("mealBackup.confirmImport")
                }
            }
        }
    }
}
