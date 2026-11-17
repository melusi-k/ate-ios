import SwiftUI

/// Chooses only an existing saved recipe. Planning and reminders stay in CookPlanSheet.
private struct CookPlanRecipePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let select: (String) -> Void

    private var recipes: [RecipeCard] { CookPlanRecipeChoices.matches(store.recipes, query: query) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a saved recipe, then pick its cooking day. This does not record a finished cook.")
                        .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                }
                if store.recipes.isEmpty {
                    ContentUnavailableView("No saved recipes", systemImage: "books.vertical",
                        description: Text("Save a recipe in your Library before planning a cook."))
                } else if recipes.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(recipes) { recipe in
                        Button { select(recipe.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title).font(AteFont.body(16, .semibold))
                                Text("Choose cooking day").font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityLabel("Plan \(recipe.title)")
                        .accessibilityIdentifier("cookPlan.pick.\(recipe.id)")
                    }
                }
            }
            .searchable(text: $query, prompt: "Find a saved recipe")
            .navigationTitle("Cook this on...").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.accessibilityIdentifier("cookPlan.pickerCancel")
            } }
        }
    }
}

/// Two existing presentation stages sequenced by real dismissal, never a delay or
/// overlapping sheets. A deleted selection is handled by CookPlanSheet's existing guard.
private struct CookPlanPickerFlow: ViewModifier {
    @Binding var presented: Bool
    @State private var pendingID: String?
    @State private var plan: PlanTarget?
    private struct PlanTarget: Identifiable { let id: String }
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presented, onDismiss: {
                guard let id = pendingID else { return }
                pendingID = nil
                plan = PlanTarget(id: id)
            }) {
                CookPlanRecipePicker { id in pendingID = id; presented = false }
            }
            .sheet(item: $plan) { target in CookPlanSheet(recipeID: target.id) }
    }
}

extension View {
    func cookPlanRecipePicker(isPresented: Binding<Bool>) -> some View {
        modifier(CookPlanPickerFlow(presented: isPresented))
    }
}
