import Foundation

enum BetaFeedbackCategory: String, CaseIterable, Identifiable {
    case bug, feature, ux, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bug: "Bug report"
        case .feature: "Feature request"
        case .ux: "UI / UX suggestion"
        case .general: "General feedback"
        }
    }
    var symbol: String {
        switch self {
        case .bug: "ladybug"
        case .feature: "lightbulb"
        case .ux: "paintbrush"
        case .general: "bubble.left"
        }
    }
}

enum BetaFeedbackError: LocalizedError {
    case unavailable, invalid, rateLimited, rejected
    var errorDescription: String? {
        switch self {
        case .unavailable: "Feedback isn't available in this build."
        case .invalid: "Please add a little more detail (at least 10 characters)."
        case .rateLimited: "You've sent several reports recently. Please try again later."
        case .rejected: "Feedback couldn't be submitted. Please try again."
        }
    }
}

enum BetaFeedbackService {
    static func submit(category: BetaFeedbackCategory, message: String, contactEmail: String?) async throws {
        guard AppConfig.isBetaBuild, !AppConfig.isUITesting,
              let base = AppConfig.supabaseURL, !AppConfig.supabasePublishableKey.isEmpty else {
            throw BetaFeedbackError.unavailable
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10, trimmed.count <= 5000 else { throw BetaFeedbackError.invalid }
        let email = contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailValue: Any = email?.isEmpty == false ? String(email!.prefix(254)) : NSNull()
        let payload: [String: Any] = [
            "category": category.rawValue,
            "message": trimmed,
            "contactEmail": emailValue,
            "appVersion": String(AppConfig.appVersion.prefix(32)),
            "buildNumber": String(AppConfig.buildNumber.prefix(32)),
            "channel": AppConfig.channel,
            "gitSHA": String(AppConfig.gitSHA.prefix(16))
        ]
        var request = URLRequest(url: base.appendingPathComponent("functions/v1/beta-feedback"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await Net.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { throw BetaFeedbackError.rateLimited }
            guard (200..<300).contains(status) else { throw BetaFeedbackError.rejected }
            _ = data
        } catch let error as BetaFeedbackError { throw error }
        catch { throw BetaFeedbackError.rejected }
    }
}
