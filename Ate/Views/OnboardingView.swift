import SwiftUI

/// First-run flow: 3 feature pages, then Sign in / Create account / Continue without account.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var page = 0
    @State private var auth: AuthMode?

    private struct Page { let icon: String; let title: String; let body: String }
    private let pages = [
        Page(icon: "wand.and.stars", title: "Any recipe, one clean card",
             body: "Paste a link, pick a screenshot or just describe a dish. ate turns it into a tidy card with ingredients and steps, right on your iPhone."),
        Page(icon: "timer", title: "Cook mode with timers",
             body: "Big, step-by-step instructions with built-in timers that follow you to the Dynamic Island and Lock Screen."),
        Page(icon: "arrow.triangle.2.circlepath", title: "Sync and share",
             body: "Sign in to keep your library and shopping list in sync across devices, and share any recipe with a clean link."),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < pages.count {
                        Button("Skip") { withAnimation { page = pages.count } }
                            .font(AteFont.body(15, .medium)).tint(Theme.mutedForeground).accessibilityIdentifier("onboardingSkip")
                    }
                }.frame(height: 44).padding(.horizontal, 20)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in feature(pages[i]).tag(i) }
                    choice.tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0...pages.count, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.primary : Theme.border).frame(width: i == page ? 22 : 8, height: 8)
                    }
                }.animation(.snappy, value: page).padding(.bottom, 16)

                if page < pages.count {
                    Button("Next") { withAnimation { page += 1 } }
                        .buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("onboardingNext")
                        .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
            .foregroundStyle(Theme.foreground)
            .pageWidth()
        }
        .sheet(item: $auth) { m in
            AuthSheet(mode: m) { store.finishOnboarding() }.environment(store)
        }
    }

    private func feature(_ p: Page) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: p.icon).font(.system(size: 64, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 128, height: 128).background(Theme.secondary, in: Circle())
            Text(p.title).font(AteFont.display(30)).multilineTextAlignment(.center)
            Text(p.body).font(AteFont.body(16)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
            Spacer(); Spacer()
        }.padding(.horizontal, 32)
    }

    private var choice: some View {
        VStack(spacing: 14) {
            Spacer()
            Image("AteLogo").resizable().scaledToFit().frame(width: 96, height: 96).accessibilityLabel("ate")
            Text("Ready to cook?").font(AteFont.display(28)).accessibilityIdentifier("onboardingChoice")
            Text("An account is optional. Everything works offline on this iPhone.")
                .font(AteFont.body(15)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
            Spacer()
            if store.accountAvailable {
                Button("Create account") { auth = .signUp }.buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("onboardingSignUp")
                Button("Sign in") { auth = .signIn }.buttonStyle(.ate(.secondary, full: true)).accessibilityIdentifier("onboardingSignIn")
            }
            Button("Continue without account") { store.finishOnboarding() }
                .buttonStyle(.ate(.ghost, full: true)).accessibilityIdentifier("onboardingContinue")
            LegalLinks().padding(.top, 4)
            Text("Version \(AppConfig.appVersion) (build \(AppConfig.buildNumber))")
                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("onboardingVersion")
        }.padding(.horizontal, 24).padding(.bottom, 24)
    }
}
