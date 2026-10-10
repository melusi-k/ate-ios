import SwiftUI

/// A recipe's cover: user photo / page image / generated image, else the branded tile.
/// Aspect-fill; the caller sets size and clipping. Kicks off lazy backfill on appear.
struct RecipeCover: View {
    let recipe: RecipeCard
    var symbolSize: CGFloat = 26
    var autoBackfill = true
    @Environment(AppStore.self) private var store: AppStore?
    private var covers: CoverStore { .shared }

    var body: some View {
        let img = covers.image(for: recipe)
        ZStack {
            BrandTile(recipe: recipe, symbolSize: symbolSize)
            if let img {
                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }.clipped()
                    .transition(.opacity)
            } else if covers.isLoading(recipe.id) {
                Shimmer()
            }
        }
        .animation(.easeOut(duration: 0.25), value: img != nil)
        .accessibilityHidden(true)
        .onAppear { if autoBackfill, let store { covers.ensure(recipe, store: store) } }
    }
}

/// Branded fallback: warm gradient tinted by cuisine/main ingredient, dish initial in Fraunces, a faint food symbol.
struct BrandTile: View {
    let recipe: RecipeCard
    var symbolSize: CGFloat = 26
    var body: some View {
        let t = CoverLogic.tile(title: recipe.title, cuisine: recipe.cuisine, ingredients: recipe.ingredients.map(\.name))
        let p = CoverLogic.palettes[t.palette]
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            ZStack {
                LinearGradient(colors: [Color(UIColor(hex: p.0)), Color(UIColor(hex: p.1))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: t.symbol)
                    .font(.system(size: side * 0.42, weight: .regular))
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: side * 0.22, y: side * 0.18)
                Text(t.initial)
                    .font(AteFont.display(side * 0.5, .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

struct Shimmer: View {
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { g in
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.6)
                .offset(x: phase * g.size.width * 1.4)
        }
        .clipped()
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

/// 4:3 hero on recipe detail.
struct RecipeHero: View {
    let recipe: RecipeCard
    var autoBackfill = true
    var body: some View {
        RecipeCover(recipe: recipe, symbolSize: 64, autoBackfill: autoBackfill)
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .accessibilityIdentifier("recipeHero")
    }
}
