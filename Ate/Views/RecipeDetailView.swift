import SwiftUI

struct RecipeDetailView: View {
    let recipeID: String
    @Environment(AppStore.self) private var store
    @State private var factor: Double = 1
    @State private var editing = false
    @State private var ask = ""
    @State private var asking = false
    @State private var confirmDelete = false
    @State private var share: ShareItems?
    @State private var shareChoice = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            if let recipe = store.recipe(recipeID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackBar(title: "Recipes", action: { store.path.removeAll() }) {
                            IconButton(symbol: recipe.favorite ? "star.fill" : "star",
                                       label: recipe.favorite ? "Remove from Favourites" : "Add to Favourites") { store.toggleFavourite(recipe.id) }
                                .accessibilityIdentifier("favouriteButton")
                            IconButton(symbol: "square.and.arrow.up", label: "Share recipe") { shareChoice = true }
                            IconButton(symbol: "pencil", label: "Edit") { editing.toggle() }.accessibilityIdentifier("editButton")
                            IconButton(symbol: "trash", label: "Delete", tint: Theme.destructive) { confirmDelete = true }
                                .accessibilityIdentifier("deleteButton")
                        }
                        if editing {
                            VStack(spacing: 16) {
                                RecipeEditor(recipe: Binding(get: { store.recipe(recipeID) ?? recipe },
                                                             set: { store.update($0) }))
                                Button("Done") { editing = false }.buttonStyle(.ate(.primary, full: true))
                            }.cardSurface(padding: 20)
                        } else {
                            HStack(spacing: 8) {
                                ForEach([1.0, 2.0, 3.0], id: \.self) { f in
                                    Button("x\(Int(f)) servings") { factor = f }
                                        .buttonStyle(.ate(factor == f ? .primary : .secondary, height: 34))
                                }
                            }
                            SourceBadge(source: recipe.source)
                            RecipeCardView(recipe: recipe, factor: factor, units: store.settings.units)
                            Button {
                                store.addToShopping(recipe, factor: factor)
                                store.show("Added to your shopping list")
                            } label: { Label("Add to shopping list", systemImage: "text.badge.plus") }
                                .buttonStyle(.ate(.secondary, full: true))
                            askCard(recipe)
                        }
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 112)
                    .pageWidth()
                }
                if !editing {
                    Button { store.cookTarget = CookTarget(id: recipeID) } label: { Label("Cook mode", systemImage: "frying.pan").padding(.horizontal, 10) }
                        .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.bottom, 20)
                }
            } else {
                RecipeNotFoundView(title: "Recipe not found")
            }
        }
        .toolbar(.hidden, for: .tabBar)   // full-height detail; Cook mode pinned at the bottom, never under the tab bar
        .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                store.timers.stopAll(recipeID: recipeID)
                store.delete(recipeID)
                store.show("Recipe deleted")
                store.path.removeAll()
            }
        }
        .confirmationDialog("Share recipe", isPresented: $shareChoice, titleVisibility: .hidden) {
            if let r = store.recipe(recipeID) {
                Button("Share link") { Task { await doShare(r, asText: false) } }
                Button("Share as text") { Task { await doShare(r, asText: true) } }
            }
        }
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
    }

    private func askCard(_ recipe: RecipeCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask ate").overline()
            HStack(spacing: 8) {
                TextField("Make this vegan", text: $ask).ateField().accessibilityIdentifier("askField").onSubmit { Task { await rewrite(recipe) } }
                Button { Task { await rewrite(recipe) } } label: {
                    if asking { ProgressView().tint(Theme.primaryForeground) } else { Image(systemName: "sparkles") }
                }
                .buttonStyle(.ate(.primary, height: 40)).disabled(asking).accessibilityLabel("Ask ate")
            }
        }
        .cardSurface(padding: 16)
    }

    private func rewrite(_ recipe: RecipeCard) async {
        let q = ask.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if store.settings.onDeviceOnly { store.show("Private mode is on — turn it off in Settings to use AI.", error: true); return }
        asking = true
        defer { asking = false }
        do {
            var card = try await store.backend.parseRecipe(ParseRequest(mode: .rewrite, text: q, currentRecipe: recipe))
            card.id = recipe.id; card.createdAt = recipe.createdAt
            store.update(RecipeLogic.normalize(card))
            ask = ""
            store.show("Recipe updated")
        } catch { store.show(error.localizedDescription, error: true) }
    }

    /// "Share link" (default): one URL item with a rich preview. "Share as text": text with the link once at the end.
    private func doShare(_ recipe: RecipeCard, asText: Bool) async {
        let units = store.settings.units
        do {
            let slug = try await store.backend.publish(RecipeLogic.scaled(recipe, factor: factor))
            let link = "\(AppConfig.shareHost)/r/\(slug)"
            guard let url = URL(string: link) else { throw BackendError(message: "bad url") }
            if asText {
                share = ShareItems(items: [RecipeLogic.text(for: recipe, factor: factor, units: units, shareURL: link)])
            } else {
                share = ShareItems(items: [LinkShareSource(url: url, title: recipe.title, image: thumbnailImage(for: recipe))])
            }
        } catch {
            store.show("Could not create a share link. Sharing the text instead.", error: true)
            share = ShareItems(items: [RecipeLogic.text(for: recipe, factor: factor, units: units)])
        }
    }
}
