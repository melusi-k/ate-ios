import SwiftUI

struct AccountCard: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account & sync").font(AteFont.display(18))
            if !store.accountAvailable {
                Text("Cloud sync isn't configured in this build.").font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            } else if let s = store.session {
                Label(s.email.isEmpty ? "Signed in" : s.email, systemImage: "person.crop.circle.fill")
                    .font(AteFont.body(15, .semibold)).accessibilityIdentifier("accountEmail")
                HStack(spacing: 6) {
                    if store.syncState == .syncing { ProgressView().controlSize(.small) }
                    Text(store.syncState.label).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                        .accessibilityIdentifier("syncStatus")
                }
                HStack(spacing: 8) {
                    Button { Task { await store.syncNow() } } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.ate(.secondary, height: 40)).disabled(store.syncState == .syncing)
                    Button("Sign out") { Task { await store.signOut() } }.buttonStyle(.ate(.destructiveGhost, height: 40))
                }
            } else {
                Text("Sign in to sync your recipes and shopping list across devices. Everything keeps working offline without an account.")
                    .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().ateField().accessibilityIdentifier("accountEmailField")
                SecureField("Password (min 6 characters)", text: $password).textContentType(.password)
                    .ateField().accessibilityIdentifier("accountPasswordField")
                WrapLayout(spacing: 8) {
                    Button("Sign in") { run { await store.signIn(email: email, password: password) } }
                        .buttonStyle(.ate(.primary, height: 40)).disabled(!valid(needsPassword: true))
                    Button("Create account") { run { await store.signUp(email: email, password: password) } }
                        .buttonStyle(.ate(.secondary, height: 40)).disabled(!valid(needsPassword: true))
                    Button { run { await store.sendMagicLink(email: email) } } label: { Label("Email me a magic link", systemImage: "envelope") }
                        .buttonStyle(.ate(.ghost, height: 40)).disabled(!valid(needsPassword: false))
                }
                if busy { ProgressView() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 20)
    }

    private func valid(needsPassword: Bool) -> Bool {
        !busy && email.contains("@") && email.contains(".") && (!needsPassword || password.count >= 6)
    }

    private func run(_ op: @escaping () async -> Void) {
        busy = true
        Task { await op(); busy = false; password = "" }
    }
}
