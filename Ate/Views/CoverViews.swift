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
        .animation(Motion.anim(.easeOut(duration: 0.25)), value: img != nil)
        .accessibilityHidden(true)
        .onAppear { if autoBackfill, let store { covers.ensure(recipe, store: store) } }
    }
}

/// Branded fallback (last resort after web image and Image Playground): a cuisine-tinted gradient with a soft
/// "plate" of the dish's food symbol, the cuisine as a small overline and the dish name set in Fraunces. No lone
/// initial letter or watermark.
struct BrandTile: View {
    let recipe: RecipeCard
    var symbolSize: CGFloat = 26
    var body: some View {
        let t = CoverLogic.tile(title: recipe.title, cuisine: recipe.cuisine, ingredients: recipe.ingredients.map(\.name))
        let p = CoverLogic.palettes[t.palette]
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let large = side > 120
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(UIColor(hex: p.0)), Color(UIColor(hex: p.1))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.22), .clear], center: .init(x: 0.72, y: 0.32),
                               startRadius: 0, endRadius: side * 0.6)
                // The "plate": a ringed disc with the food symbol, top-trailing.
                ZStack {
                    Circle().fill(.white.opacity(0.16))
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: max(1, side * 0.012))
                        .padding(side * 0.05)
                    Image(systemName: t.symbol).resizable().scaledToFit()
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(side * 0.14)
                }
                .frame(width: side * (large ? 0.46 : 0.62), height: side * (large ? 0.46 : 0.62))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: large ? .topTrailing : .center)
                .padding(large ? side * 0.08 : 0)
                if large {
                    VStack(alignment: .leading, spacing: 4) {
                        if let c = recipe.cuisine, !c.isEmpty {
                            Text(c.uppercased()).font(AteFont.body(12, .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.85))
                        }
                        Text(recipe.title).font(AteFont.display(min(30, side * 0.11), .semibold))
                            .foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    }
                    .padding(side * 0.07)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .accessibilityIdentifier("brandTile")
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
        .onAppear { withAnimation(Motion.anim(.linear(duration: 1.2).repeatForever(autoreverses: false))) { phase = 1 } }
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recipe cover")
            .accessibilityValue(kind)
            .accessibilityIdentifier("recipeHero")
    }
    /// "photo" when a local cover or remote image exists, otherwise "tile" (branded fallback). Used by UI tests.
    private var kind: String {
        if let f = recipe.coverImage, f != CoverStore.removed { return "photo" }
        if recipe.coverImage == nil, recipe.imageURL != nil { return "photo" }
        return "tile"
    }
}
