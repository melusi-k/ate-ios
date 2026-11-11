import SwiftUI

struct CookPlanSheet: View {
    let recipeID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var when = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var reminder = true
    @State private var zoneID = TimeZone.current.identifier
    @State private var existing: CookPlan?
    @State private var problem: String?
    @State private var loadingFailed = false
    @State private var reminderStatus: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                if let recipe = store.recipe(recipeID) {
                    Section {
                        Text(recipe.title).font(.headline)
                        DatePicker("Cook this on", selection: $when, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, TimeZone(identifier: zoneID) ?? .current)
                            .accessibilityIdentifier("cookPlan.date")
                        Toggle("Remind me", isOn: $reminder).accessibilityIdentifier("cookPlan.reminder")
                        Text("Time zone: \(zoneID). This cooking occasion keeps its chosen time zone when you travel.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } footer: {
                        Text("The plan stays saved even if notifications are off. This does not record a finished cook.")
                    }
                    if let existing {
                        Section("Saved plan") {
                            Text(savedTime(existing))
                                .accessibilityIdentifier("cookPlan.savedDate")
                            if let reminderStatus { Text(reminderStatus).font(.footnote) }
                            Button("Cancel cooking plan", role: .destructive) { cancel() }
                                .accessibilityIdentifier("cookPlan.cancelPlan")
                        }
                    }
                } else {
                    Text("This recipe is no longer in your library.")
                }
                if let problem {
                    Text(problem).foregroundStyle(.red).accessibilityIdentifier("cookPlan.message")
                }
            }
            .navigationTitle("Cook this on...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(busy || loadingFailed || store.recipe(recipeID) == nil || when <= Date())
                        .accessibilityIdentifier("cookPlan.save")
                }
            }
            .interactiveDismissDisabled(busy)
            .onAppear(perform: load)
        }
    }

    private func load() {
        do {
            existing = try store.cookPlanStore.plans().first { $0.recipeID == recipeID }
            if let existing {
                when = existing.scheduledAt; reminder = existing.reminderRequested; zoneID = existing.timeZoneID
                Task { @MainActor in
                    let permission = await store.cookPlanNotifications.permission(requestIfNeeded: false)
                    reminderStatus = !existing.reminderRequested ? "No reminder requested." :
                        permission == .allowed ? "Reminder requested for the saved time." : "Notifications are off. The plan is saved without an active reminder."
                }
            }
        } catch {
            loadingFailed = true
            problem = "Cooking plans could not be read. The saved data was kept."
        }
    }

    private func savedTime(_ plan: CookPlan) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: plan.timeZoneID) ?? .current
        return formatter.string(from: plan.scheduledAt) + " (" + plan.timeZoneID + ")"
    }

    private func save() {
        let plan = CookPlan(recipeID: recipeID, scheduledAt: when, timeZoneID: zoneID, reminderRequested: reminder)
        do {
            if !plan.reminderRequested {
                try store.cookPlanNotifications.saveWithoutReminder(plan, store: store.cookPlanStore) {
                    store.show("Cooking plan saved, but reminder removal could not be verified. Reopen the plan and try Save again.")
                }
                store.show("Cooking plan saved")
                dismiss()
                return
            }
            try store.cookPlanStore.save(plan)
            existing = plan
        } catch {
            problem = "The cooking plan could not be saved. Choose a future time and try again."
            return
        }
        busy = true; problem = nil
        Task { @MainActor in
            let permission = await store.cookPlanNotifications.permission(requestIfNeeded: reminder)
            do {
                try await store.cookPlanNotifications.reconcile(plans: store.cookPlanStore.plans(), recipes: store.recipes)
                busy = false
                if reminder && permission != .allowed {
                    problem = "Plan saved. Notifications are off, so no reminder will be sent. You can allow notifications in iPhone Settings."
                } else {
                    store.show(reminder ? "Cooking plan and reminder saved" : "Cooking plan saved without a reminder")
                    dismiss()
                }
            } catch {
                busy = false
                problem = "Plan saved, but its reminder could not be updated. Try Save again."
            }
        }
    }

    private func cancel() {
        busy = true
        Task { @MainActor in
            do {
                try store.cookPlanStore.cancel(recipeID: recipeID)
                try await store.cookPlanNotifications.cancel(recipeID: recipeID)
                busy = false
                store.show("Cooking plan cancelled")
                dismiss()
            } catch {
                busy = false
                problem = "Cancellation could not be verified. Try again to remove the reminder."
            }
        }
    }
}
