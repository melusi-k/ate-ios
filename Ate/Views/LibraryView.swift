import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var showAdd = false

    var body: some View {
        let filtered = store.recipes.filter { RecipeLogic.matches($0, query: query) }
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "fork.knife.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.primary)
                                Text("ate").font(AteFont.body(14, .bold)).tracking(2.8).foregroundStyle(Theme.primary)
                            }
                            Text("Your kitchen library").font(AteFont.display(36))
                            Text("\(store.recipes.count) recipe\(store.recipes.count == 1 ? "" : "s") saved on this device.")
                                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                        }
                        Spacer()
                        IconButton(symbol: "basket", label: "Shopping list") { store.path.append(.shopping) }
                        IconButton(symbol: "gearshape", label: "Settings") { store.path.append(.settings) }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                        TextField("Search chicken, pasta, vegan…", text: $query).font(AteFont.body(15))
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 18).frame(height: 48)
                    .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.input))

                    if store.recipes.isEmpty {
                        EmptyStateCard(symbol: "fork.knife", title: "Nothing saved yet",
                                       message: "Paste a link or a screenshot and get a clean recipe card in seconds.")
                    } else if filtered.isEmpty {
                        EmptyStateCard(symbol: "fork.knife", title: "No matches", message: "Try another ingredient or tag.")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { r in
                                Button { store.path.append(.recipe(r.id)) } label: { RecipeRowView(recipe: r) }
                                    .buttonStyle(PressScale())
                            }
                        }
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 32).padding(.bottom, 112)
                .pageWidth()
            }
            Button { showAdd = true } label: { Label("Add recipe", systemImage: "plus").padding(.horizontal, 10) }
                .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.bottom, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAdd) {
            AddRecipeSheet { card in
                store.add(card)
                store.show("Saved to your library")
                showAdd = false
                store.path.append(.recipe(card.id))
            }
            .environment(store)
            .presentationDetents([.large])
        }
    }
}
