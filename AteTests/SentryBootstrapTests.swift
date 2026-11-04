import XCTest
import Sentry
@testable import Ate

/// Deterministic gating and event-scrubbing coverage for SentryBootstrap (#289).
/// These tests never start the SDK and never emit network events.
final class SentryBootstrapTests: XCTestCase {

    // MARK: - Gating

    func testEmptyDSNDisablesStart() {
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: "", isUITesting: false, channel: "TierA"))
    }

    func testNonHTTPSDSNDisablesStart() {
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: "http://o123.ingest.sentry.io/456", isUITesting: false, channel: "TierA"))
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: "not-a-url", isUITesting: false, channel: "TierA"))
    }

    func testUITestLaunchDisablesStart() {
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: "https://0123456789abcdef0123456789abcdef@o4512371813842944.ingest.us.sentry.io/456", isUITesting: true, channel: "TierA"))
    }

    func testProductionAndUnknownChannelsDisableStart() {
        let dsn = "https://0123456789abcdef0123456789abcdef@o4512371813842944.ingest.us.sentry.io/456"
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: dsn, isUITesting: false, channel: ""))
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: dsn, isUITesting: false, channel: "Production"))
        XCTAssertFalse(SentryBootstrap.shouldStart(dsn: dsn, isUITesting: false, channel: "something-else"))
    }

    func testNonProductionChannelWithValidDSNEnablesStart() {
        let dsn = "https://0123456789abcdef0123456789abcdef@o4512371813842944.ingest.us.sentry.io/456"
        for channel in ["TierA", "TierB", "TierC", "Beta", "QA", "Internal", "Development"] {
            XCTAssertTrue(SentryBootstrap.shouldStart(dsn: dsn, isUITesting: false, channel: channel), "channel \(channel) should enable")
        }
    }

    func testMalformedAndUnexpectedDSNsDisableStart() {
        let key = "0123456789abcdef0123456789abcdef"
        let invalid = [
            "https://",                       // missing host and project
            "https://\(key)@/456",            // missing host
            "https://\(key)@o4512371813842944.ingest.us.sentry.io", // missing project
            "https://o4512371813842944.ingest.us.sentry.io/456", // missing key
            "https://bad-key@o4512371813842944.ingest.us.sentry.io/456",
            "https://\(key)@o4512371813842944.ingest.us.sentry.io/not-a-project",
            "https://\(key)@o4512371813842944.ingest.us.sentry.io/456/extra",
            "https://\(key)@o4512371813842944.ingest.us.sentry.io.evil.example/456",
            "https://\(key)@unapproved.example/456",
            "https://\(key):password@o4512371813842944.ingest.us.sentry.io/456",
            "https://\(key)@o4512371813842944.ingest.us.sentry.io:8443/456",
            "https://\(key)@o4512371813842944.ingest.us.sentry.io/456?data=value",
            "https://\(key)@o4512371813842944.ingest.us.sentry.io/456#fragment"
        ]
        for dsn in invalid {
            XCTAssertFalse(SentryBootstrap.shouldStart(dsn: dsn, isUITesting: false, channel: "TierA"))
        }
    }

    // MARK: - Canary proof configuration

    func testBuiltInfoPlistHasEmptyOrProofCanary() {
        // Reads the raw built Info.plist entry, NOT the XCTest-guarded canaryMarker().
        // Normal builds: key absent or empty. Proof builds: the per-run canary-run-*
        // marker. A marker with any other shape is a wiring bug and fails here.
        let raw = Bundle.main.object(forInfoDictionaryKey: "AteSentryCanary") as? String
        guard let raw else { return } // absent key is an acceptable normal-build state
        XCTAssertTrue(raw.isEmpty || raw.hasPrefix("canary-run-"),
                      "AteSentryCanary must be empty or a canary-run-* proof marker")
    }

    func testCanaryMarkerSuppressedUnderTestHost() {
        // Unit tests run inside the app; the guarded accessor must stay nil here so
        // test runs never fire the synthetic proof event, even in proof builds.
        XCTAssertNil(SentryBootstrap.canaryMarker())
    }

    // MARK: - Event scrubbing

    func testScrubRemovesIdentityFreeTextURLsAndSDKTags() {
        let event = Event()
        let user = User()
        user.email = "person@example.com"
        user.userId = "abc123"
        event.user = user
        event.message = SentryMessage(formatted: "a raw user-provided string")
        event.extra = ["recipeTitle": "secret-recipe", "prompt": "secret-prompt"]
        event.breadcrumbs = [Breadcrumb(level: .info, category: "navigation")]
        event.tags = ["sdk_tag": "value"]

        let scrubbed = SentryBootstrap.scrubEvent(event)

        XCTAssertNotNil(scrubbed)
        XCTAssertNil(event.user)
        XCTAssertNil(event.message)
        XCTAssertEqual(event.extra?.count ?? 0, 0)
        XCTAssertEqual(event.breadcrumbs?.count ?? 0, 0)
        XCTAssertNil(event.request)
        XCTAssertEqual(event.tags, ["git_sha": AppConfig.gitSHAFull])
    }

    func testScrubFiltersExceptionValuesButKeepsTypeMechanismAndStacktrace() {
        let event = Event()
        let exception = Exception(value: "fatal: user recipe text could leak here", type: "SyntheticCrash")
        exception.mechanism = Mechanism(type: "mach")
        exception.stacktrace = SentryStacktrace(frames: [], registers: [:])
        event.exceptions = [exception]

        _ = SentryBootstrap.scrubEvent(event)

        XCTAssertEqual(event.exceptions?.first?.value, "[Filtered]")
        XCTAssertEqual(event.exceptions?.first?.type, "SyntheticCrash")
        XCTAssertEqual(event.exceptions?.first?.mechanism?.type, "mach")
        XCTAssertNotNil(event.exceptions?.first?.stacktrace)
    }

    func testScrubNeverDropsTheEventItself() {
        XCTAssertNotNil(SentryBootstrap.scrubEvent(Event()))
    }
}
