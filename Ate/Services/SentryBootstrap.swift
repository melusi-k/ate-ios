import Foundation
import Sentry

/// Owns the single Sentry bootstrap point for the iOS app.
///
/// Sentry starts only when ALL of these hold (docs/SENTRY.md):
/// - a valid https DSN was injected at project-generation time, and
/// - the launch is not a UI test, and
/// - the build runs in a recognized non-production channel, matching the
///   remote-telemetry channel policy in docs/TELEMETRY.md. Production and
///   unknown-channel builds never start Sentry in this slice.
/// DSNs are public ingestion endpoints, not credentials, but are still supplied
/// through build configuration rather than committed to the repository.
enum SentryBootstrap {
    /// Pure gating decision, deterministic and unit-testable without starting the SDK.
    static func shouldStart(dsn: String, isUITesting: Bool, channel: String) -> Bool {
        guard !isUITesting else { return false }
        guard isValidDSN(dsn) else { return false }
        guard AppConfig.isBetaChannel(channel) else { return false }
        return true
    }

    /// This slice uses the user-confirmed US Sentry SaaS endpoint only.
    /// A self-hosted migration needs an explicit host policy and matching CI URL first.
    static func isValidDSN(_ dsn: String) -> Bool {
        guard let parts = URLComponents(string: dsn),
              parts.scheme == "https",
              let host = parts.host?.lowercased(),
              host == "o4512371813842944.ingest.us.sentry.io",
              parts.port == nil,
              let key = parts.user,
              key.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              parts.path.range(of: "^/[0-9]+$", options: .regularExpression) != nil else { return false }
        return true
    }

    /// Ingestion-proof canary. A non-empty value is injected ONLY by the one-off
    /// proof build configuration; normal builds never carry it. When present, a
    /// single synthetic error embedding the canary as user-content is captured at
    /// startup: the stored event proves ingestion, and the canary's absence from
    /// the stored payload proves scrubbing. Never commit a real canary value.
    static func canaryMarker() -> String? {
        // Never under a test host: unit tests run inside the app and must stay synthetic-free.
        guard NSClassFromString("XCTestCase") == nil else { return nil }
        let marker = AppConfig.string("AteSentryCanary")
        return marker.isEmpty ? nil : marker
    }

    static func start() {
        // Never start under a test host: crash reporters interfere with XCTest's own
        // crash handling, and test runs must not emit events. UI-test launches are
        // separately excluded by the -UITesting launch argument in shouldStart.
        guard NSClassFromString("XCTestCase") == nil else { return }
        let dsn = AppConfig.string("AteSentryDSN")
        guard shouldStart(dsn: dsn, isUITesting: AppConfig.isUITesting, channel: AppConfig.channel) else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.releaseName = "com.melusik.ate@\(AppConfig.appVersion)+\(AppConfig.buildNumber)"
            options.dist = AppConfig.buildNumber
            options.sendDefaultPii = false
            // Crash, app-hang and watchdog-termination detection stay at SDK defaults (on).
            // Release-health sessions stay off until session payloads are verified
            // against the privacy contract (#289).
            options.enableAutoSessionTracking = false
            // Network tracking attaches request URLs and trace headers; URLs are on
            // the never-send list (docs/TELEMETRY.md). Failed-request capture and
            // network breadcrumbs default ON and install the network integration even
            // with tracking off, so both are disabled explicitly.
            options.enableNetworkTracking = false
            options.enableCaptureFailedRequests = false
            options.enableNetworkBreadcrumbs = false
            // Performance spans wait for the privacy-reviewed instrumentation slice.
            options.tracesSampleRate = 0.0
            // Automatic breadcrumbs can contain URLs, request metadata or
            // user-entered text. Start with no breadcrumbs; add only typed,
            // allowlisted breadcrumbs in a later, tested change.
            options.beforeBreadcrumb = { _ in nil }
            options.beforeSend = scrubEvent
        }

        #if targetEnvironment(simulator)
        switch fatalProofAction(arguments: ProcessInfo.processInfo.arguments,
                                canaryPresent: canaryMarker() != nil,
                                channel: AppConfig.channel) {
        case .crash:
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                captureSyntheticFatalProof()
            }
            return
        case .recover:
            // Preserve the container so the prior cached crash can be delivered.
            return
        case .none:
            break
        }
        #endif

        if let marker = canaryMarker() {
            let error = NSError(
                domain: "ate.sentry.ingestion-proof",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "synthetic canary: \(marker)"]
            )
            SentrySDK.capture(error: error)
        }
    }

    enum FatalProofAction: Equatable { case none, crash, recover }

    /// Pure decision only. Calling this never starts the SDK or crashes a process.
    /// Recovery wins if conflicting arguments are supplied.
    static func fatalProofAction(arguments: [String], canaryPresent: Bool,
                                 channel: String) -> FatalProofAction {
        guard canaryPresent, channel == "TierA" else { return .none }
        if arguments.contains("-SentryFatalRecovery") { return .recover }
        if arguments.contains("-SentryFatalProof") { return .crash }
        return .none
    }

    #if targetEnvironment(simulator)
    /// A named in-app frame for the separately reviewed fatal-symbolication proof.
    @inline(never)
    private static func captureSyntheticFatalProof() {
        SentrySDK.crash()
    }
    #endif

    /// Event scrubber, deterministic and unit-testable without starting the SDK.
    /// Drops identity, free text, URLs and SDK-set tags; keeps exception type,
    /// mechanism, stacktrace, threads, device/OS and release context needed for
    /// triage; stamps the exact build's Git SHA as a known-safe tag.
    static func scrubEvent(_ event: Event) -> Event? {
        event.user = nil
        event.message = nil
        event.extra = [:]
        event.breadcrumbs = []
        event.request = nil
        event.tags = ["git_sha": AppConfig.gitSHAFull]
        // Raw error/exception messages can embed interpolated user strings and are
        // on the telemetry never-send list; type + mechanism + stacktrace remain
        // for triage.
        if let exceptions = event.exceptions {
            for exception in exceptions {
                exception.value = "[Filtered]"
            }
        }
        return event
    }

    private static var environment: String {
        let channel = AppConfig.channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return channel.isEmpty ? "production" : channel
    }
}
