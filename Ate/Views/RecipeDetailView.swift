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
    @Environment(\.dismiss) private var dismiss
    /// Pops whichever stack (or sheet) presented this screen. Never touches store.path directly: the recipe may have been
    /// pushed from More/Settings/Insights while Library has its own path, which made the old custom Back a dead tap.
    private func goBack() { dismiss() }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            if let recipe = store.recipe(recipeID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if editing {
                            VStack(spacing: 16) {
                                RecipeEditor(recipe: Binding(get: { store.recipe(recipeID) ?? recipe },
                                                             set: { store.update($0) }))
                                Button("Done") { editing = false }.buttonStyle(.ate(.primary, full: true))
                            }.cardSurface(padding: 20)
                        } else {
                            Picker("Servings", selection: $factor) {
                                ForEach([1.0, 2.0, 3.0], id: \.self) { f in Text("\(Int(f))×").tag(f) }
                            }
                            .pickerStyle(.segmented).controlSize(.large)
                            .accessibilityIdentifier("servingsPicker")
                            .accessibilityHint("Scales ingredient amounts. Cooking times stay the same.")
                            RecipeHero(recipe: recipe)
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
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                    .pageWidth()
                }
            } else {
                RecipeNotFoundView(title: "Recipe not found")
            }
        }
        .toolbar(.hidden, for: .tabBar)   // full-height detail; Cook mode pinned at the bottom, never under the tab bar
        .navigationTitle(store.recipe(recipeID)?.title ?? "Recipe")
        .navigationBarTitleDisplayMode(.inline)
        // Bottom area, one system: this inset (Cook mode) sits directly above the stack's timer bar inset.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !editing, store.recipe(recipeID) != nil {
                Button { store.cookTarget = CookTarget(id: recipeID) } label: { Label("Cook mode", systemImage: "frying.pan").padding(.horizontal, 10) }
                    .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            if let recipe = store.recipe(recipeID) {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.toggleFavourite(recipe.id) } label: {
                        Image(systemName: recipe.favorite ? "star.fill" : "star")
                    }
                    .accessibilityLabel(recipe.favorite ? "Remove from Favourites" : "Add to Favourites")
                    .accessibilityIdentifier("favouriteButton")
                    Button { shareChoice = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share recipe")
                    Menu {
                        Button { editing.toggle() } label: { Label(editing ? "Done editing" : "Edit", systemImage: "pencil") }
                            .accessibilityIdentifier("editButton")
                        if CoverStore.playgroundAvailable && !ProcessInfo.processInfo.arguments.contains("-qaNoPlayground") {
                            Button { Task { await generateCover(recipe) } } label: { Label("Generate cover", systemImage: "wand.and.sparkles") }
                                .disabled(CoverStore.shared.isLoading(recipe.id))
                                .accessibilityIdentifier("generateCoverMenu")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                            .accessibilityIdentifier("deleteButton")
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More actions").accessibilityIdentifier("recipeMenu")
            .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete recipe", role: .destructive) {
                    store.timers.stopAll(recipeID: recipeID)
                    store.delete(recipeID)
                    store.show("Recipe deleted")
                    goBack()
                }
            }

                }
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

    /// Image Playground cover on demand (replaces a web image or tile, never a user photo without asking: the menu is explicit).
    private func generateCover(_ recipe: RecipeCard) async {
        guard let name = await CoverStore.shared.generate(for: recipe) else {
            store.show("Couldn't generate a cover right now.", error: true); return
        }
        store.setCover(recipe.id, file: name, imageURL: nil)
        store.show("New cover made with Image Playground")
        BetaQA.shared.pass("A-COVER-01", note: "Generated a cover for “\(recipe.title)”")
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
            let link = AppConfig.shareURL(slug: slug)
            guard let url = URL(string: link) else { throw BackendError(message: "bad url") }
            BetaQA.shared.pass("A-SHARE-01", note: "Published \(link)")
            if asText {
                share = ShareItems(items: [RecipeLogic.text(for: recipe, factor: factor, units: units, shareURL: link)])
            } else {
                share = ShareItems(items: [LinkShareSource(url: url, title: recipe.title, image: thumbnailImage(for: recipe))])
            }
        } catch {
            store.show("Could not create a share link. Sharing the text instead.", error: true)
            BetaQA.shared.fail("A-SHARE-01", error: "Publish failed: \(Net.friendly(error))")
            BetaQA.shared.pass("A-SHARE-05", note: "Backend unavailable → fell back to text share")
            share = ShareItems(items: [RecipeLogic.text(for: recipe, factor: factor, units: units)])
        }
    }
}
