import SwiftUI

struct SharedRecipeView: View {
    let slug: String
    @Environment(AppStore.self) private var store
    @State private var recipe: RecipeCard?
    @State private var loading = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let r = recipe {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackBar(title: "Open ate") { store.path.removeAll() }
                        RecipeCardView(recipe: r, units: store.settings.units)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 112).pageWidth()
                }
                Button {
                    var copy = r
                    copy.id = UUID().uuidString
                    copy.createdAt = Date().timeIntervalSince1970 * 1000
                    store.add(copy)
                    store.show("Saved to your library")
                    store.path = [.recipe(copy.id)]
                } label: { Label("Save to my library", systemImage: "bookmark").padding(.horizontal, 10) }
                    .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.bottom, 20)
            } else {
                MessageStateView(title: "This recipe link has expired", message: "The shared recipe could not be found.",
                                 buttons: [("Open ate", { store.path.removeAll() })])
            }
        }
        .foregroundStyle(Theme.foreground)
        .task {
            recipe = try? await store.backend.fetchShared(slug: slug)
            loading = false
        }
    }
}

struct MessageStateView: View {
    var big: String? = nil
    let title: String
    let message: String
    let buttons: [(String, () -> Void)]
    var body: some View {
        VStack(spacing: 12) {
            if let big { Text(big).font(AteFont.display(72)) }
            Text(title).font(AteFont.display(24)).multilineTextAlignment(.center)
            Text(message).font(AteFont.body(15)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
            HStack {
                ForEach(Array(buttons.enumerated()), id: \.offset) { i, b in
                    Button(b.0, action: b.1).buttonStyle(.ate(i == 0 ? .primary : .secondary))
                }
            }.padding(.top, 8)
        }
        .foregroundStyle(Theme.foreground)
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

struct RecipeNotFoundView: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    var body: some View {
        MessageStateView(title: title, message: "", buttons: [("Back to library", { if let onBack { onBack() } else { store.path.removeAll() } })])
    }
}

struct NotFoundView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        MessageStateView(big: "404", title: "Page not found",
                         message: "The page you're looking for doesn't exist or has been moved.",
                         buttons: [("Go home", { store.path.removeAll() })])
    }
}

struct ErrorStateView: View {
    let retry: () -> Void
    @Environment(AppStore.self) private var store
    var body: some View {
        MessageStateView(title: "This page didn't load",
                         message: "Something went wrong on our end. You can try refreshing or head back home.",
                         buttons: [("Try again", retry), ("Go home", { store.path.removeAll() })])
    }
}
