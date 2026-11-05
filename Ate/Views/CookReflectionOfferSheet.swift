import SwiftUI

/// Small, dismissible invitation shown after the user explicitly finishes cooking. Writing is optional: the cook is
/// already recorded, and every way out of this sheet (Not now, swipe down) just leaves. It scrolls and can expand
/// so both buttons stay reachable at the largest accessibility text sizes.
struct CookReflectionOfferSheet: View {
    let event: CookCompletionEvent
    let onShown: () -> Void
    let onWrite: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cooked \(event.recipeTitle)")
                    .font(AteFont.display(22))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("cookReflection.title")
                Text("Want to jot down how it went? What worked, what you changed, whether you would cook it again.")
                    .font(AteFont.body(15))
                    .foregroundStyle(Theme.mutedForeground)
                Button("Write a note", action: onWrite)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("cookReflection.write")
                Button("Not now", action: onNotNow)
                    .controlSize(.large)
                    .accessibilityIdentifier("cookReflection.notNow")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: onShown)
    }
}
