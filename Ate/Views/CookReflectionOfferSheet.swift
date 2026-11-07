import SwiftUI

/// Completion confirmation shown after every explicit successful Finish. Writing is optional: the cook is
/// already recorded, and every way out of this sheet (Done, swipe down) just leaves. It scrolls and can expand
/// so both buttons stay reachable at the largest accessibility text sizes.
struct CookReflectionOfferSheet: View {
    let event: CookCompletionEvent
    var showReflectionNudge = true
    let onShown: () -> Void
    let onWrite: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cooking complete")
                    .font(AteFont.display(22))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("cookReflection.title")
                Text(event.recipeTitle)
                    .font(AteFont.body(18))
                    .accessibilityIdentifier("cookCompletion.recipe")
                Label("Added to cooking history", systemImage: "checkmark.circle")
                    .font(AteFont.body(15))
                    .accessibilityIdentifier("cookCompletion.recorded")
                Text(event.completedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.footnote).foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("cookCompletion.date")
                if showReflectionNudge {
                    Text("How did it go?").font(.headline)
                        .accessibilityIdentifier("cookCompletion.dailyNudge")
                    Text("Keep what worked or what you would change next time.")
                        .font(AteFont.body(15)).foregroundStyle(Theme.mutedForeground)
                }
                Button("Add a note", action: onWrite)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("cookReflection.write")
                Button("Done", action: onNotNow)
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
