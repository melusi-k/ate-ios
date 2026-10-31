import SwiftUI

/// A deliberately narrow prototype: Library grid cards use a native, resizable sheet for a quick
/// recipe glance, then reuse the existing recipe-detail screen at medium/large detents.
struct ExpandableRecipeDetailSheet: View {
    let recipe: RecipeCard
    @Binding var detent: PresentationDetent
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The system medium detent is inactive in compact-height environments (for example,
    /// landscape iPhone). Use large as the expanded state there so the explicit expand action works.
    private var expandedDetent: PresentationDetent {
        verticalSizeClass == .compact ? .large : .medium
    }

    private var availableDetents: Set<PresentationDetent> {
        verticalSizeClass == .compact
            ? [.height(260), .large]
            : [.height(260), .medium, .large]
    }

    var body: some View {
        Group {
            if detent == .height(260) {
                compactPreview
            } else {
                NavigationStack {
                    RecipeDetailView(recipeID: recipe.id)
                }
            }
        }
        .presentationDetents(availableDetents, selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .onChange(of: verticalSizeClass) { _, newSizeClass in
            // Keep the selected detent valid if the device rotates while this sheet is open.
            if newSizeClass == .compact && detent == .medium {
                detent = .large
            }
        }
    }

    private var compactPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RecipeThumb(recipe: recipe, width: 68, height: 68, emojiSize: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.title)
                        .font(AteFont.body(17, .semibold))
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
                withAnimation(Motion.anim(.snappy)) { detent = expandedDetent }
            } label: {
                Label("Expand recipe details", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.ate(.primary, height: 42))
            .accessibilityIdentifier("expandRecipeDetails")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        // .contain keeps this identifier on the container only: a bare
        // .accessibilityIdentifier on a container absorbs all descendant identifiers
        // (CI: expandRecipeDetails button reported as recipeQuickLook, #179).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipeQuickLook")
    }
}
