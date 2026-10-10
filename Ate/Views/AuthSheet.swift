import SwiftUI

/// Sign in / create account / set new password. Presented as a sheet from Settings and onboarding.
struct AuthSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AuthMode
    private let onSignedIn: () -> Void
    init(mode: AuthMode, onSignedIn: @escaping () -> Void = {}) {
        _mode = State(initialValue: mode); self.onSignedIn = onSignedIn
    }

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var forgot = false
    @State private var pendingShown = false
    @FocusState private var focus: Field?
    enum Field { case email, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if mode == .newPassword { newPasswordForm }
                    else if pendingShown, let pending = store.pendingConfirmation {
                        pendingView(pending)
                    } else if forgot { forgotForm }
                    else { mainForm }
                    LegalLinks().padding(.top, 8)
                }
                .padding(20)
                .foregroundStyle(Theme.foreground)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("authClose") }
            }
        }
        .onAppear {
            if email.isEmpty { email = store.pendingConfirmation ?? "" }
            focus = mode == .newPassword ? .password : .email
        }
        .interactiveDismissDisabled(busy)
    }

    // MARK: forms
    private var mainForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode == .signIn ? "Welcome back" : "Create your account").font(AteFont.display(28))
                .accessibilityIdentifier("authTitle")
            Text(mode == .signIn ? "Sign in to sync your recipes and shopping list."
                                 : "An account syncs your library across devices. ate works fully without one.")
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            Picker("Mode", selection: $mode) {
                Text("Sign in").tag(AuthMode.signIn); Text("Create account").tag(AuthMode.signUp)
            }.pickerStyle(.segmented).accessibilityIdentifier("authModePicker")
            .onChange(of: mode) { _, _ in error = nil; info = nil }

            emailField
            passwordField(placeholder: mode == .signIn ? "Password" : "Password (min 6 characters)")

            messages

            Button { submit() } label: {
                HStack { if busy { ProgressView().tint(Theme.primaryForeground) }; Text(mode == .signIn ? "Sign in" : "Create account") }
            }
            .buttonStyle(.ate(.primary, full: true)).disabled(!valid(password: true))
            .accessibilityIdentifier("authSubmit")

            HStack {
                if mode == .signIn {
                    Button("Forgot password?") { forgot = true; error = nil; info = nil }
                        .font(AteFont.body(14, .medium)).accessibilityIdentifier("forgotPassword")
                }
                Spacer()
                Button { magic() } label: { Label("Email me a link", systemImage: "envelope") }
                    .font(AteFont.body(14, .medium)).disabled(!valid(password: false)).accessibilityIdentifier("magicLink")
            }.tint(Theme.primary)
        }
    }

    private var forgotForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reset your password").font(AteFont.display(28))
            Text("We'll email you a link. Open it on this iPhone to choose a new password.")
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            emailField
            messages
            Button { run { await store.recoverPassword(email: email) } success: { info = "Check your inbox for the reset link." } } label: {
                HStack { if busy { ProgressView() }; Text("Send reset link") }
            }.buttonStyle(.ate(.primary, full: true)).disabled(!valid(password: false)).accessibilityIdentifier("sendReset")
            Button("Back to sign in") { forgot = false; error = nil; info = nil }.font(AteFont.body(14, .medium)).tint(Theme.primary)
        }
    }

    private func pendingView(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "envelope.badge").font(.system(size: 40)).foregroundStyle(Theme.primary)
            Text("Confirm your email").font(AteFont.display(28)).accessibilityIdentifier("confirmPending")
            Text("We sent a link to \(address). Open it on this iPhone to finish signing in.")
                .font(AteFont.body(15)).foregroundStyle(Theme.mutedForeground)
            messages
            Button { run { await store.resendConfirmation() } success: { info = "Sent again. It can take a minute." } } label: {
                HStack { if busy { ProgressView() }; Text("Resend email") }
            }.buttonStyle(.ate(.secondary, full: true)).disabled(busy).accessibilityIdentifier("resendConfirmation")
            Button("I've confirmed, sign in") {
                pendingShown = false; mode = .signIn; error = nil; info = nil
                store.pendingConfirmation = nil; focus = .password
            }.buttonStyle(.ate(.ghost, full: true))
        }
    }

    private var newPasswordForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a new password").font(AteFont.display(28)).accessibilityIdentifier("newPasswordTitle")
            if let e = store.session?.email, !e.isEmpty {
                Text(e).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            }
            passwordField(placeholder: "New password (min 6 characters)")
            messages
            Button { run { await store.setNewPassword(password) } success: { dismiss() } } label: {
                HStack { if busy { ProgressView() }; Text("Save password") }
            }.buttonStyle(.ate(.primary, full: true)).disabled(busy || password.count < 6).accessibilityIdentifier("savePassword")
        }
    }

    // MARK: pieces
    private var emailField: some View {
        TextField("Email", text: $email)
            .keyboardType(.emailAddress).textContentType(.username)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(forgot ? .send : .next).focused($focus, equals: .email)
            .onSubmit { if forgot { if valid(password: false) { run { await store.recoverPassword(email: email) } success: { info = "Check your inbox for the reset link." } } } else { focus = .password } }
            .ateField().accessibilityIdentifier("authEmail")
    }

    private func passwordField(placeholder: String) -> some View {
        HStack {
            Group {
                if showPassword { TextField(placeholder, text: $password).accessibilityIdentifier("authPasswordVisible") }
                else { SecureField(placeholder, text: $password).accessibilityIdentifier("authPassword") }
            }
            .textContentType(mode == .signIn ? .password : .newPassword)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focus, equals: .password).submitLabel(.go)
            .onSubmit { if mode == .newPassword { if password.count >= 6 { run { await store.setNewPassword(password) } success: { dismiss() } } } else if valid(password: true) { submit() } }
            Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }.ateField()
    }

    @ViewBuilder private var messages: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill").font(AteFont.body(14)).foregroundStyle(Theme.destructive)
                .accessibilityIdentifier("authError")
        }
        if let info {
            Label(info, systemImage: "checkmark.circle.fill").font(AteFont.body(14)).foregroundStyle(Theme.primary)
                .accessibilityIdentifier("authInfo")
        }
    }

    // MARK: actions
    private func valid(password needs: Bool) -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return !busy && e.contains("@") && e.contains(".") && (!needs || password.count >= 6)
    }

    private func submit() {
        if mode == .signIn {
            run { await store.signIn(email: email, password: password) } success: { onSignedIn(); dismiss() }
            return
        }
        busy = true; error = nil; info = nil
        Task {
            switch await store.signUp(email: email, password: password) {
            case .signedIn: onSignedIn(); dismiss()
            case .confirmationSent: pendingShown = true; password = ""
            case .failed(let e):
                error = e.message
                if e.kind == .userExists { mode = .signIn }
            }
            busy = false
        }
    }

    private func magic() {
        run { await store.sendMagicLink(email: email) } success: { info = "Magic link sent. Open it on this iPhone." }
    }

    private func run(_ op: @escaping () async -> AuthError?, success: @escaping () -> Void = {}) {
        busy = true; error = nil; info = nil
        Task {
            if let e = await op() {
                error = e.message
                if e.kind == .emailNotConfirmed { pendingShown = true }
            } else { success() }
            busy = false
        }
    }
}

/// Privacy policy and terms links (URLs from Info.plist `AtePrivacyURL` / `AteTermsURL`).
struct LegalLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            if let u = AppConfig.privacyURL { Link("Privacy Policy", destination: u).accessibilityIdentifier("privacyLink") }
            if let u = AppConfig.termsURL { Link("Terms of Use", destination: u).accessibilityIdentifier("termsLink") }
        }
        .font(AteFont.body(13, .medium)).tint(Theme.mutedForeground)
        .frame(maxWidth: .infinity)
    }
}
