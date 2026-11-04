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
        guard !dsn.isEmpty, URL(string: dsn)?.scheme == "https" else { return false }
        guard AppConfig.isBetaChannel(channel) else { return false }
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

        if let marker = canaryMarker() {
            let error = NSError(
                domain: "ate.sentry.ingestion-proof",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "synthetic canary: \(marker)"]
            )
            SentrySDK.capture(error: error)
        }
    }

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
