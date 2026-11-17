import Foundation

/// Remote diagnostics are a separate opt-in from the always-local diagnostic history.
/// Shipping stays fail-closed until privacy copy, receiver controls and retention are reviewed.
final class TelemetryClient {
    static let shared = TelemetryClient()
    static let consentKey = "ate.telemetry.consent.v1"
    static let remoteReleaseReady = false

    struct Configuration {
        var releaseReady = TelemetryClient.remoteReleaseReady
        var channel = AppConfig.channel
        var isUITesting = AppConfig.isUITesting
        var baseURL = AppConfig.supabaseURL
        var publicKey = AppConfig.supabasePublishableKey
        var appVersion = AppConfig.appVersion
        var buildNumber = AppConfig.buildNumber
        var gitSHA = AppConfig.gitSHA

        var permitsOptIn: Bool {
            releaseReady && !isUITesting && AppConfig.isBetaChannel(channel)
                && baseURL?.scheme == "https" && !publicKey.isEmpty
        }
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let configuration: Configuration
    private let session: URLSession
    private var tasks: [UUID: URLSessionDataTask] = [:]
    private var minuteStart = Date.distantPast
    private var sentThisMinute = 0

    init(defaults: UserDefaults = .standard, configuration: Configuration = Configuration(), session: URLSession? = nil) {
        self.defaults = defaults
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        self.session = session ?? URLSession(configuration: settings)
    }

    var canEnable: Bool { configuration.permitsOptIn }
    var hasConsent: Bool {
        lock.lock(); defer { lock.unlock() }
        return defaults.object(forKey: Self.consentKey) as? Bool == true
    }
    var status: String {
        if !canEnable { return "Remote diagnostics unavailable in this build. No events are uploaded." }
        return hasConsent ? "Remote diagnostics on. New category-only events may be sent." : "Remote diagnostics off. No events are uploaded."
    }

    /// Never infer consent from channel, account, old diagnostic history or a remote setting.
    /// Revocation stops new starts and cancels in-flight work; it cannot recall received bytes.
    func setConsent(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        if enabled && canEnable {
            defaults.set(true, forKey: Self.consentKey)
        } else {
            defaults.removeObject(forKey: Self.consentKey)
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
        }
    }

    func record(_ kind: DiagnosticEvent.Kind, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        guard canEnable, defaults.object(forKey: Self.consentKey) as? Bool == true else { return }
        let now = Date()
        guard date.timeIntervalSince1970.isFinite,
              date >= now.addingTimeInterval(-7 * 24 * 60 * 60), date <= now.addingTimeInterval(5 * 60) else { return }
        if now.timeIntervalSince(minuteStart) >= 60 {
            minuteStart = now; sentThisMinute = 0
        }
        guard sentThisMinute < 30, let base = configuration.baseURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("functions/v1/telemetry"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        let payload: [String: Any] = [
            "channel": configuration.channel,
            "appVersion": String(configuration.appVersion.prefix(32)),
            "buildNumber": String(configuration.buildNumber.prefix(32)),
            "gitSHA": String(configuration.gitSHA.prefix(16)),
            "events": [["kind": kind.rawValue, "timestamp": date.timeIntervalSince1970 * 1000]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = data
        let id = UUID() // Local task bookkeeping only. Never transmitted or persisted.
        let task = session.dataTask(with: request) { [weak self] _, _, _ in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.tasks.removeValue(forKey: id)
        }
        tasks[id] = task
        sentThisMinute += 1
        // Start under the same lock as revocation so no detached task can start after opt-out.
        // No Net.data retry: ambiguous delivery cannot be retried safely before receiver dedup exists.
        task.resume()
    }
}
