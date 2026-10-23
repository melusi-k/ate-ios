import Foundation

/// Best-effort category-only telemetry. It is intentionally disabled for production/unknown channels.
final class TelemetryClient {
    static let shared = TelemetryClient()
    private let lock = NSLock()
    private var lastSentAt: Date = .distantPast
    private var sentThisMinute = 0

    private init() {}

    func record(_ kind: DiagnosticEvent.Kind, at date: Date) {
        guard !AppConfig.isUITesting,
              AppConfig.isBetaChannel(AppConfig.channel),
              let baseURL = AppConfig.supabaseURL,
              !AppConfig.supabasePublishableKey.isEmpty else { return }

        // Local guardrail against accidental event storms; this is not a security boundary.
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(lastSentAt) >= 60 {
            lastSentAt = now
            sentThisMinute = 0
        }
        guard sentThisMinute < 30 else { lock.unlock(); return }
        sentThisMinute += 1
        lock.unlock()

        let endpoint = baseURL.appendingPathComponent("functions/v1/telemetry")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        let payload: [String: Any] = [
            "channel": AppConfig.channel,
            "appVersion": String(AppConfig.appVersion.prefix(32)),
            "buildNumber": String(AppConfig.buildNumber.prefix(32)),
            "gitSHA": String(AppConfig.gitSHA.prefix(16)),
            "events": [[
                "kind": kind.rawValue,
                "timestamp": date.timeIntervalSince1970 * 1000
            ]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = data
        Task.detached(priority: .utility) {
            do {
                let (_, response) = try await Net.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            } catch {
                // Telemetry is best-effort and must never affect app behaviour. Never log payloads or errors.
            }
        }
    }
}
