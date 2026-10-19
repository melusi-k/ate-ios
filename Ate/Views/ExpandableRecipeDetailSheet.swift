import SwiftUI

/// A deliberately narrow prototype: Library grid cards use a native, resizable sheet for a quick
/// recipe glance, then reuse the existing recipe-detail screen at medium/large detents.
struct ExpandableRecipeDetailSheet: View {
    let recipe: RecipeCard
    @Binding var detent: PresentationDetent

    var body: some View {
        Group {
            if detent == .height(220) {
                compactPreview
            } else {
                NavigationStack {
                    RecipeDetailView(recipeID: recipe.id)
                }
            }
        }
        .presentationDetents([.height(220), .medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
    }

    private var compactPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                RecipeThumb(recipe: recipe, width: 84, height: 84, emojiSize: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(recipe.title)
                        .font(AteFont.body(18, .semibold))
                        .lineLimit(2)
                        .accessibilityIdentifier("recipeQuickLookTitle")

                    HStack(spacing: 12) {
                        Label("\(recipe.ingredients.count) ingredients", systemImage: "list.bullet")
                        Label("\(recipe.steps.count) steps", systemImage: "checklist")
                    }
                    .font(AteFont.body(12))
                    .foregroundStyle(Theme.mutedForeground)

                    if let minutes = recipe.timeMinutes, minutes > 0 {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(AteFont.body(12, .medium))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                withAnimation(Motion.anim(.snappy)) { detent = .medium }
            } label: {
                Label("Expand recipe details", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.ate(.primary, height: 44))
            .accessibilityIdentifier("expandRecipeDetails")
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        .accessibilityIdentifier("recipeQuickLook")
    }
}
