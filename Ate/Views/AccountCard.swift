import SwiftUI

struct AccountCard: View {
    @Environment(AppStore.self) private var store
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var typeDelete = false
    @State private var deleteText = ""
    @State private var deleting = false

    var body: some View {
        @Bindable var store = store
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
                // Equal-width, full-height 44pt rows (was a wrap layout that squeezed Sync into a tall narrow box).
                HStack(spacing: 8) {
                    Button { Task { await store.syncNow() } } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath").lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.ate(.secondary, height: 44, full: true)).disabled(store.syncState == .syncing)
                    .accessibilityIdentifier("syncNowButton")
                    Button { confirmSignOut = true } label: {
                        Text("Sign out").lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.ate(.outline, height: 44, full: true))
                    .accessibilityIdentifier("signOutButton")
                    .confirmationDialog("Sign out of ate?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Sign out, keep recipes on this iPhone") { Task { await store.signOut(removeLocalData: false) } }
                        Button("Sign out and remove local data", role: .destructive) { Task { await store.signOut(removeLocalData: true) } }
                        Button("Cancel", role: .cancel) {}
                    } message: { Text("Your synced recipes stay in your account either way.") }
                }
                .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 4)
                Text("Danger zone").font(AteFont.body(14, .semibold)).foregroundStyle(Theme.destructive)
                Text("Deleting your account permanently removes it and your synced recipes from ate's server and this iPhone.")
                    .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                Button { confirmDelete = true } label: {
                    HStack { if deleting { ProgressView() }; Label("Delete account", systemImage: "trash") }
                }.buttonStyle(.ate(.destructiveGhost, height: 40)).disabled(deleting).accessibilityIdentifier("deleteAccountButton")
            } else {
                Text("Sign in to sync your recipes and shopping list across devices. Everything keeps working offline without an account.")
                    .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                WrapLayout(spacing: 8) {
                    Button("Sign in") { store.authSheet = .signIn }.buttonStyle(.ate(.primary, height: 40))
                        .accessibilityIdentifier("openSignIn")
                    Button("Create account") { store.authSheet = .signUp }.buttonStyle(.ate(.secondary, height: 40))
                        .accessibilityIdentifier("openSignUp")
                }
                if let p = store.pendingConfirmation {
                    Text("Waiting for you to confirm \(p).").font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 20)
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Continue", role: .destructive) { deleteText = ""; typeDelete = true }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes your account and synced recipes. It can't be undone. Recipes you shared stay viewable at their links.") }
        .alert("Type DELETE to confirm", isPresented: $typeDelete) {
            TextField("DELETE", text: $deleteText).textInputAutocapitalization(.characters).accessibilityIdentifier("deleteConfirmField")
            Button("Delete account", role: .destructive) {
                guard deleteText == "DELETE" else { store.show("Account not deleted — you didn't type DELETE", error: true); return }
                deleting = true
                Task {
                    if let e = await store.deleteAccount() { store.show(e.message, error: true) }
                    deleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your recipes on this iPhone will be removed too.") }
    }
}
