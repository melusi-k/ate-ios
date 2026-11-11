import SwiftUI

/// A deliberately narrow prototype: Library list/grid cards use a native, resizable sheet for a quick
/// recipe glance, then reuse the existing recipe-detail screen at medium/large detents.
struct ExpandableRecipeDetailSheet: View {
    let recipe: RecipeCard
    @Binding var detent: PresentationDetent
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var detailLoaded = false

    private var isCompact: Bool { detent == .height(260) }

    private func select(_ next: PresentationDetent) {
        if next != .height(260) { detailLoaded = true }
        withAnimation(Motion.anim(.snappy)) { detent = next }
    }

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
        VStack(spacing: 0) {
            HStack {
                Text(isCompact ? "Recipe preview" : "Recipe details")
                    .font(AteFont.body(13, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
                if !isCompact {
                    if detent != .large {
                        Button { select(.large) } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Expand recipe fully")
                        .accessibilityIdentifier("recipeSheet.expandFully")
                    }
                    Button { select(.height(260)) } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Collapse recipe preview")
                    .accessibilityIdentifier("recipeSheet.collapse")
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                    .accessibilityLabel("Close recipe")
                    .accessibilityIdentifier("recipeSheet.close")
            }
            .buttonStyle(.plain)
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(minHeight: 44)

            // Keep the detail's identity alive across detent changes. Replacing its
            // NavigationStack when collapsing discarded servings, scroll and editor state.
            // Only the active surface participates in hit testing or accessibility.
            ZStack(alignment: .top) {
                if detailLoaded {
                    NavigationStack {
                        RecipeDetailView(recipeID: recipe.id)
                    }
                    .opacity(isCompact ? 0 : 1)
                    .allowsHitTesting(!isCompact)
                    .accessibilityHidden(isCompact)
                }

                compactPreview
                    .opacity(isCompact ? 1 : 0)
                    .allowsHitTesting(isCompact)
                    .accessibilityHidden(!isCompact)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .presentationDetents(availableDetents, selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .onAppear { if !isCompact { detailLoaded = true } }
        .onChange(of: detent) { _, next in
            // Native dragging can expand without using the explicit button.
            if next != .height(260) { detailLoaded = true }
        }
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
                select(expandedDetent)
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
