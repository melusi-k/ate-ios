import SwiftUI

struct BetaFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: BetaFeedbackCategory = .general
    @State private var message = ""
    @State private var contactEmail = ""
    @State private var includeEmail = false
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var submitted = false

    private var canSubmit: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 &&
        message.trimmingCharacters(in: .whitespacesAndNewlines).count <= 5000 && !submitting
    }

    var body: some View {
        Form {
            Section {
                Text("Your feedback helps make ate better. Tell us what happened, what you expected, or what you'd like to see.")
                    .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                Picker("Category", selection: $category) {
                    ForEach(BetaFeedbackCategory.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .accessibilityIdentifier("feedback.category")
            }
            Section("Your feedback") {
                TextEditor(text: $message)
                    .frame(minHeight: 150)
                    .accessibilityIdentifier("feedback.message")
                HStack {
                    Text("At least 10 characters").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                    Spacer()
                    Text("\(message.count)/5000").font(AteFont.body(11, .medium)).foregroundStyle(Theme.mutedForeground)
                }
            }
            Section {
                Toggle("I'd like a reply", isOn: $includeEmail)
                if includeEmail {
                    TextField("Email address", text: $contactEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("feedback.email")
                }
            } header: { Text("Optional contact") } footer: {
                Text("Your email is only included if you choose to provide it. Feedback is stored securely in Ate's beta feedback system.")
            }
            Section("Build information") {
                LabeledContent("Version", value: AppConfig.appVersion)
                LabeledContent("Build", value: AppConfig.buildNumber)
                LabeledContent("Channel", value: AppConfig.channel)
            }
            if let errorMessage {
                Section { Text(errorMessage).font(AteFont.body(13)).foregroundStyle(Theme.destructive) }
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Spacer()
                        if submitting { ProgressView() } else { Label("Send feedback", systemImage: "paperplane.fill") }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("feedback.submit")
            } footer: {
                Text("Please don't include passwords, payment details, or other people's personal information.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Share Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thank you!", isPresented: $submitted) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your feedback has been sent to the ate team.")
        }
    }

    @MainActor private func send() async {
        guard canSubmit else { return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            try await BetaFeedbackService.submit(category: category, message: message,
                                                 contactEmail: includeEmail ? contactEmail : nil)
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
