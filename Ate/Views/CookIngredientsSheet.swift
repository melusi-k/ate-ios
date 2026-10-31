import SwiftUI

/// Pull-up ingredient checklist for Cook Mode: the recipe's ingredients scaled to the
/// session's servings factor, checkable while cooking. Checks live in the cook session,
/// so leaving and resuming Cook Mode keeps them; finishing or ending the session clears them.
struct CookIngredientsSheet: View {
    let recipe: RecipeCard
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Same factor choices as the recipe detail servings picker.
    private static let factors: [Double] = [1, 2, 3]

    /// The row's amount text, converted to the user's unit system (shared by tests).
    static func checklistAmount(for ing: Ingredient, to system: UnitSystem) -> String {
        let (q, u) = Units.convert(quantity: ing.quantity, unit: ing.unit, to: system)
        return Units.formatAmount(q, u)
    }

    /// Read through the live session so rescaling and checking update in place. A session for
    /// another recipe (or none, e.g. previews) falls back to an unchecked 1x list.
    private var factor: Double { store.cookSession?.recipeID == recipe.id ? (store.cookSession?.factor ?? 1) : 1 }
    /// Positional checks are only shown while the session's ingredient fingerprint matches the
    /// recipe; a stale session (edited or legacy) reads as unchecked, and the first toggle resets it.
    private var checked: Set<Int> {
        guard let s = store.cookSession, s.recipeID == recipe.id,
              s.ingredientSignature == RecipeLogic.ingredientSignature(recipe) else { return [] }
        return Set(s.checked)
    }

    var body: some View {
        let scaled = RecipeLogic.scaled(recipe, factor: factor)
        NavigationStack {
            Group {
                if scaled.ingredients.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet").font(.largeTitle).foregroundStyle(Theme.mutedForeground)
                        Text("No ingredients listed").font(AteFont.body(16, .semibold))
                        Text("This recipe has no ingredient list to check off.")
                            .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cookIngredientsEmpty")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Servings", selection: Binding(get: { factor }, set: { store.setCookFactor($0) })) {
                                    ForEach(Self.factors, id: \.self) { f in Text("\(Int(f))×").tag(f) }
                                }
                                .pickerStyle(.segmented).controlSize(.large)
                                .accessibilityIdentifier("cookServingsPicker")
                                .accessibilityHint("Scales ingredient amounts. Cooking times stay the same.")
                                Text("\(scaled.servings) servings · tap an ingredient once you have it ready")
                                    .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(scaled.ingredients.enumerated()), id: \.offset) { idx, ing in
                                    row(idx, ing)
                                }
                            }
                            .cardSurface(padding: 16)
                            Text("\(checked.count) of \(scaled.ingredients.count) gathered")
                                .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityIdentifier("cookIngredientsProgress")
                        }
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("cookIngredientsDone")
                }
            }
        }
        // Room to read: the reference pattern of a cramped mini-sheet is deliberately avoided.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .cookSheetUITestDynamicType()
    }

    private func row(_ idx: Int, _ ing: Ingredient) -> some View {
        let isChecked = checked.contains(idx)
        let amount = Self.checklistAmount(for: ing, to: store.settings.units)
        let notes = (ing.notes ?? "").isEmpty ? "" : " — \(ing.notes ?? "")"
        return Button {
            store.toggleCookIngredientChecked(idx)
            Haptics.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? Theme.primary : Theme.mutedForeground)
                    .frame(width: 28)
                if !amount.isEmpty {
                    Text(amount).font(AteFont.body(15, .medium)).monospacedDigit()
                        .frame(width: 84, alignment: .leading)
                        .minimumScaleFactor(0.7)
                }
                (Text(ing.name) + Text(notes).foregroundColor(Theme.mutedForeground))
                    .font(AteFont.body(15))
                    .strikethrough(isChecked, color: Theme.mutedForeground)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isChecked ? Theme.mutedForeground : Theme.foreground)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cookIngredient.\(idx)")
        .accessibilityLabel(([amount, ing.name].filter { !$0.isEmpty }.joined(separator: " ")) + notes)
        .accessibilityValue(isChecked ? "Gathered" : "Not gathered")
        .accessibilityHint("Double-tap to toggle")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
    }
}

extension View {
    /// UI-test-only: launching with "-UITestLargeText" renders the sheet at an accessibility
    /// text size so tests exercise the real layout (clipping, tap targets, scrolling) under
    /// large Dynamic Type. No effect in any other launch.
    @ViewBuilder func cookSheetUITestDynamicType() -> some View {
        if AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-UITestLargeText") {
            self.dynamicTypeSize(.accessibility3)
        } else { self }
    }
}
