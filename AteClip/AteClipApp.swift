import SwiftUI

@main
struct AteClipApp: App {
    @State private var incomingURL: URL?
    var body: some Scene {
        WindowGroup {
            ClipRootView(url: incomingURL)
                .onOpenURL { incomingURL = $0 }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { incomingURL = $0.webpageURL }
        }
    }
}

private struct ClipRootView: View {
    let url: URL?
    @State private var recipe: ClipRecipe?
    @State private var errorMessage: String?
    @State private var loading = false
    @State private var attemptedSlug: String?
    private let ink = Color(red: 0.16, green: 0.18, blue: 0.15)
    private let paper = Color(red: 0.98, green: 0.97, blue: 0.93)

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            Group {
                if loading { ProgressView("Opening shared recipe…").accessibilityIdentifier("clip.loading") }
                else if let recipe { recipeContent(recipe) }
                else { emptyState }
            }.foregroundStyle(ink)
        }
        .task(id: url?.absoluteString) { await load() }
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "fork.knife.circle").font(.system(size: 42)).accessibilityHidden(true)
            Text(errorMessage == nil ? "A recipe to share" : "Couldn't open this recipe")
                .font(.system(.title2, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
            Text(errorMessage ?? "Open a valid Ate shared-recipe link to see the ingredients and method.")
                .font(.body).multilineTextAlignment(.center).foregroundStyle(ink.opacity(0.72))
            if errorMessage != nil {
                Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent).tint(ink)
                    .accessibilityIdentifier("clip.retry")
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func recipeContent(_ recipe: ClipRecipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("SHARED RECIPE").font(.caption.weight(.bold)).tracking(1.8).foregroundStyle(ink.opacity(0.62))
                Text(recipe.title).font(.system(size: 34, weight: .semibold, design: .serif))
                    .accessibilityIdentifier("clip.recipe.title")
                if let description = recipe.description, !description.isEmpty {
                    Text(description).font(.body).foregroundStyle(ink.opacity(0.78))
                }
                HStack(spacing: 16) {
                    if let servings = recipe.servings { Label("\(servings) servings", systemImage: "person.2") }
                    if let minutes = recipe.timeMinutes { Label("\(minutes) min", systemImage: "clock") }
                }.font(.subheadline)
                if !recipe.ingredients.isEmpty {
                    sectionTitle("Ingredients")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(recipe.ingredients) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(ink.opacity(0.55)).frame(width: 5, height: 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredientLine(item))
                                    if let notes = item.notes, !notes.isEmpty {
                                        Text(notes).font(.footnote).foregroundStyle(ink.opacity(0.65))
                                    }
                                }
                            }
                        }
                    }
                }
                if !recipe.steps.isEmpty {
                    sectionTitle("Method")
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(recipe.steps.sorted { $0.order < $1.order }) { step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(step.order)").font(.system(.headline, design: .serif))
                                    .frame(width: 28, height: 28).background(ink.opacity(0.08), in: Circle())
                                Text(step.instruction).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text("Shared via Ate").font(.footnote).foregroundStyle(ink.opacity(0.55)).padding(.top, 6)
            }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
        }.accessibilityIdentifier("clip.recipe.content")
    }
    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(.system(.title2, design: .serif, weight: .semibold)).padding(.top, 4)
    }
    private func ingredientLine(_ item: ClipIngredient) -> String {
        let amount = item.quantity.map { $0.rounded() == $0 ? String(Int($0)) : String($0) }
        return ([amount, item.unit].compactMap { $0 }.filter { !$0.isEmpty } + [item.name]).joined(separator: " ")
    }
    @MainActor
    private func load() async {
        guard let url else { recipe = nil; errorMessage = nil; loading = false; return }
        guard let slug = ClipRecipeLink.slug(from: url) else {
            recipe = nil; errorMessage = ClipLoadError.invalidURL.localizedDescription; loading = false; return
        }
        guard attemptedSlug != slug || recipe == nil else { return }
        attemptedSlug = slug
        loading = true; errorMessage = nil
        do {
            let info = Bundle.main
            guard let endpoint = info.object(forInfoDictionaryKey: "AteSupabaseURL") as? String,
                  let baseURL = URL(string: endpoint),
                  let key = info.object(forInfoDictionaryKey: "AteSupabasePublishableKey") as? String, !key.isEmpty else {
                throw ClipLoadError.invalidURL
            }
            recipe = try await SharedRecipeClient(baseURL: baseURL, publishableKey: key).fetch(slug: slug)
        } catch is CancellationError {
            // SwiftUI cancels a request when a new invocation URL arrives.
        } catch {
            recipe = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Check your connection and try again."
        }
        loading = false
    }
}
