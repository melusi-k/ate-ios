import SwiftUI

/// Completion confirmation after a successful Finish. The cook is already recorded; writing
/// is optional. Keep both actions at the top of the medium sheet while its centered content scrolls.
struct CookReflectionOfferSheet: View {
    let event: CookCompletionEvent
    var showReflectionNudge = true
    let onShown: () -> Void
    let onWrite: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Add a note", action: onWrite)
                    .buttonStyle(.ate(.primary))
                    .accessibilityIdentifier("cookReflection.write")
                Button("Done", action: onNotNow)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("cookReflection.notNow")
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .center, spacing: 12) {
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
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium])
        .onAppear(perform: onShown)
    }
}
