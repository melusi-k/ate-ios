import Foundation
import Sentry

/// Owns the single Sentry bootstrap point for the iOS app.
///
/// Sentry remains inert when no DSN is injected or when running UI tests.
/// DSNs are public ingestion endpoints, not credentials, but are still supplied
/// through build configuration rather than committed to the repository.
enum SentryBootstrap {
    static func start() {
        guard !AppConfig.isUITesting else { return }
        let dsn = AppConfig.string("AteSentryDSN")
        guard !dsn.isEmpty, URL(string: dsn)?.scheme == "https" else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.releaseName = "com.melusik.ate@\(AppConfig.appVersion)+\(AppConfig.buildNumber)"
            options.dist = AppConfig.buildNumber
            options.sendDefaultPii = false
            options.enableAutoSessionTracking = true
            // Do not collect performance spans until the privacy-reviewed
            // instrumentation and sampling policy is implemented.
            options.tracesSampleRate = 0.0
            // Automatic breadcrumbs can contain URLs, request metadata or
            // user-entered text. Start with no breadcrumbs; add only typed,
            // allowlisted breadcrumbs in a later, tested change.
            options.beforeBreadcrumb = { _ in nil }
            options.beforeSend = { event in
                event.user = nil
                event.message = nil
                event.extra = [:]
                event.breadcrumbs = []
                return event
            }
        }
    }

    private static var environment: String {
        let channel = AppConfig.channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return channel.isEmpty ? "production" : channel
    }
}
