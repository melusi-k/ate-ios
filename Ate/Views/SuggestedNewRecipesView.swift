import SwiftUI

struct SuggestedNewRecipesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var session = RecipeDiscoverySession()
    @State private var review: RecipeCard?
    @State private var requestedInitialSuggestions = false

    var body: some View {
        List {
            Section {
                Text("New recipe ideas inspired by your saved dishes. Nothing is saved until you choose Save.")
                if let message = session.message { Text(message).accessibilityIdentifier("discovery.status") }
                if session.loading { ProgressView("Creating a new recipe…").accessibilityIdentifier("discovery.loading") }
            }
            ForEach(session.suggestions) { card in
                Section {
                    Text(card.title).font(AteFont.body(20, .bold)).foregroundStyle(Theme.foreground)
                    if let description = card.description { Text(description) }
                    if let minutes = card.timeMinutes { Text("\(minutes) min · \(card.servings) servings") }
                    Button("Review recipe") { review = card }
                    Button(session.savedIDs.contains(card.id) ? "Saved" : "Save") { save(card) }
                        .disabled(session.savedIDs.contains(card.id))
                        .accessibilityIdentifier("discovery.save.\(card.id)")
                }
            }
            Button(session.suggestions.isEmpty ? "Suggest new recipes" : "Suggest another recipe", action: generate)
                .disabled(session.loading)
                .accessibilityIdentifier("discovery.generate")
        }
        .navigationTitle("Suggested new recipes")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .sheet(item: $review) { card in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        RecipeCardView(recipe: card, units: store.settings.units)
                        Button(session.savedIDs.contains(card.id) ? "Saved" : "Save") { if save(card) { review = nil } }
                            .disabled(session.savedIDs.contains(card.id))
                        if let message = session.message { Text(message) }
                    }.padding()
                }.navigationTitle("Suggested recipe")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { review = nil } } }
            }
        }
        .task {
            guard !requestedInitialSuggestions else { return }
            requestedInitialSuggestions = true
            generate()
        }
        .onDisappear { session.cancel() }
        .onChange(of: store.insightLifecycleAccountID) { _, _ in session.accountChanged(); review = nil }
    }

    private func generate() {
        // On-device only: never send a collection to another configured service,
        // and never surface the existing Demo fallback as a real suggestion.
        session.request(available: store.backend is OnDeviceBackend && OnDeviceBackend.isModelAvailable,
            context: { try RecipeDiscovery.context(store: store) },
            generate: { try await store.backend.parseRecipe($0) })
    }

    @discardableResult private func save(_ card: RecipeCard) -> Bool {
        session.save(card, context: { try RecipeDiscovery.context(store: store) }) { recipe in
            // Discovery does not own the user's unrelated Add Recipe recovery draft.
            store.add(recipe, clearPendingDraft: false)
            return store.recipe(recipe.id) == RecipeLogic.normalize(recipe)
        }
    }
}
