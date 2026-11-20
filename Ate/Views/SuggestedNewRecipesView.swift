import SwiftUI

struct SuggestedNewRecipesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var session = RecipeDiscoverySession()
    @State private var review: RecipeCard?
    @State private var editing = false
    @State private var requestedInitialSuggestions = false

    var body: some View {
        List {
            Section {
                Text("New recipe ideas inspired by your saved dishes. Nothing is saved until you choose Save.")
                if let message = session.message { Text(message).accessibilityIdentifier("discovery.status") }
                if session.loading { ProgressView("Creating a new recipe…").accessibilityIdentifier("discovery.loading") }
            }
            if let preview = session.preview { StreamPreviewCard(preview: preview) }
            ForEach(session.suggestions) { card in
                Section {
                    Text(card.title).font(AteFont.body(20, .bold)).foregroundStyle(Theme.foreground)
                    if let description = card.description { Text(description) }
                    if let minutes = card.timeMinutes {
                        Text("\(minutes) min" + (card.servings > 0 ? " · \(card.servings) servings" : ""))
                    }
                    Button("Review recipe") { editing = false; review = card }
                    Button(session.savedIDs.contains(card.id) ? "Saved" : "Save") { save(card) }
                        .disabled(session.loading || session.savedIDs.contains(card.id))
                        .accessibilityIdentifier("discovery.save.\(card.id)")
                }
            }
            Button(session.suggestions.isEmpty ? (session.message == nil ? "Suggest new recipes" : "Try again") : "Suggest another recipe", action: generate)
                .disabled(session.loading)
                .accessibilityIdentifier("discovery.generate")
        }
        .navigationTitle("Suggested new recipes")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .sheet(item: $review, onDismiss: { session.cancel() }) { card in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let preview = session.preview { StreamPreviewCard(preview: preview) }
                        if session.loading { ProgressView("Rerunning recipe…") }
                        if RecipeQuality.needsInput(card) {
                            Text("Check this draft and fill in anything missing before saving.")
                            ForEach(RecipeQuality.issues(card), id: \.self) { Text($0).font(AteFont.body(13)) }
                        }
                        if editing {
                            RecipeEditor(recipe: Binding(get: { review ?? card }, set: { review = $0 })).disabled(session.loading)
                        } else { RecipeCardView(recipe: review ?? card, units: store.settings.units) }
                        Button(editing ? "Preview" : "Edit") { editing.toggle() }.disabled(session.loading)
                        Button("Rerun") { rerun(review ?? card) }
                            .disabled(session.loading || session.savedIDs.contains(card.id))
                            .accessibilityIdentifier("discovery.rerun")
                        Button(session.savedIDs.contains(card.id) ? "Saved" : "Save") { if save(review ?? card) { review = nil } }
                            .disabled(session.loading || session.savedIDs.contains(card.id))
                        if let message = session.message { Text(message) }
                    }.padding()
                }.navigationTitle("Suggested recipe")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { session.cancel(); review = nil } } }
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
        session.requestStreaming(available: store.backend is OnDeviceBackend && OnDeviceBackend.isModelAvailable,
            context: { try RecipeDiscovery.context(store: store) },
            generate: { generation, preview in
                guard let backend = store.backend as? OnDeviceBackend else {
                    throw BackendError(message: "On-device AI is not available right now. Try again when it is ready.")
                }
                return try await backend.suggestRecipe(generation, onPreview: preview)
            })
    }

    private func rerun(_ card: RecipeCard) {
        session.requestStreaming(available: store.backend is OnDeviceBackend && OnDeviceBackend.isModelAvailable,
            context: { try RecipeDiscovery.context(store: store) }, replacing: card,
            completed: { review = $0; editing = false }, generate: { _, preview in
                guard let backend = store.backend as? OnDeviceBackend else {
                    throw BackendError(message: "Apple Intelligence is not available. Your original card is kept.")
                }
                return try await backend.rerunRecipe(card, onPreview: preview)
            })
    }

    @discardableResult private func save(_ card: RecipeCard) -> Bool {
        session.save(card, context: { try RecipeDiscovery.context(store: store) }) { recipe in
            // Discovery does not own the user's unrelated Add Recipe recovery draft.
            store.add(recipe, clearPendingDraft: false)
            return store.recipe(recipe.id) == RecipeLogic.normalize(recipe)
        }
    }
}
