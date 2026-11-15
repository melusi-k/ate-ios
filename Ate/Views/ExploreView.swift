import SwiftUI

/// A local recipe-discovery sheet, separate from the Library's query/filter stack.
struct ExploreView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void
    let onAdd: () -> Void

    var body: some View {
        List {
            Section {
                Text("Find something to cook from your saved recipes. Explore works offline and doesn't fetch an online recipe feed.")
                    .font(AteFont.body(15))
                    .accessibilityIdentifier("explore.source")
            }
            if store.recipes.isEmpty {
                Section {
                    Text("Nothing saved yet").font(.headline)
                    Text("Add a recipe first, then come back to find something to cook.")
                    Button("Add recipe", action: onAdd)
                        .accessibilityIdentifier("explore.add")
                }
            } else {
                ForEach(ExploreRecipes.groups(recipes: store.recipes, completed: store.journalCookingHistory.events)) { group in
                    Section {
                        if group.recipes.isEmpty {
                            Text(emptyMessage(group.id)).foregroundStyle(Theme.mutedForeground)
                                .accessibilityIdentifier("explore.empty.\(group.id)")
                        } else {
                            ForEach(group.recipes) { recipe in
                                Button { onSelect(recipe.id) } label: { RecipeRowView(recipe: recipe) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("explore.recipe.\(group.id).\(recipe.id)")
                            }
                        }
                    } header: { Text(group.title) } footer: { Text(group.explanation) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Explore")
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("explore.done")
        } }
    }

    private func emptyMessage(_ id: String) -> String {
        switch id {
        case "quick": return "No saved recipes with a time of 30 minutes or less. You can add or edit a recipe's cooking time."
        case "favourites": return "Mark a saved recipe as a favourite to find it here."
        default: return "Finish a cook to find the saved recipe here. Opening Cook Mode alone doesn't count."
        }
    }
}
