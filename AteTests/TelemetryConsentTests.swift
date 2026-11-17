import XCTest
@testable import Ate

private final class TelemetryIntercept: URLProtocol {
    static var receive: ((URLRequest) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.receive?(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TelemetryConsentTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var session: URLSession!
    override func setUp() {
        suite = "ate.telemetry-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [TelemetryIntercept.self]
        session = URLSession(configuration: settings)
    }
    override func tearDown() {
        session.invalidateAndCancel()
        TelemetryIntercept.receive = nil
        defaults.removePersistentDomain(forName: suite)
    }
    private func config() -> TelemetryClient.Configuration {
        var c = TelemetryClient.Configuration()
        c.releaseReady = true; c.channel = "Beta"; c.isUITesting = false
        c.baseURL = URL(string: "https://telemetry.invalid")
        c.publicKey = "test-public-key"; c.appVersion = "1"; c.buildNumber = "2"; c.gitSHA = "abc123"
        return c
    }
    private func client(_ c: TelemetryClient.Configuration? = nil) -> TelemetryClient {
        TelemetryClient(defaults: defaults, configuration: c ?? config(), session: session)
    }
    private func expectNoRequest(_ action: () -> Void) {
        let sent = expectation(description: "No telemetry request")
        sent.isInverted = true
        TelemetryIntercept.receive = { _ in sent.fulfill() }
        action()
        wait(for: [sent], timeout: 0.15)
    }
    func testBetaChannelIsNotConsentAndDefaultDoesNotUpload() {
        let c = client()
        XCTAssertTrue(c.canEnable); XCTAssertFalse(c.hasConsent)
        expectNoRequest { c.record(.recipeSaved, at: Date()) }
    }
    func testShippingReadinessGateOverridesEvenStoredConsent() {
        XCTAssertFalse(TelemetryClient.remoteReleaseReady)
        defaults.set(true, forKey: TelemetryClient.consentKey)
        var configuration = config(); configuration.releaseReady = false
        let c = client(configuration)
        XCTAssertFalse(c.canEnable)
        expectNoRequest { c.record(.appLaunched, at: Date()) }
        c.setConsent(true)
        XCTAssertFalse(c.hasConsent)
    }
    func testProductionUnknownUITestingAndMissingCredentialsFailClosed() {
        var variants: [TelemetryClient.Configuration] = []
        var c = config(); c.channel = "Production"; variants.append(c)
        c = config(); c.channel = ""; variants.append(c)
        c = config(); c.channel = "unrecognized"; variants.append(c)
        c = config(); c.isUITesting = true; variants.append(c)
        c = config(); c.publicKey = ""; variants.append(c)
        c = config(); c.baseURL = nil; variants.append(c)
        c = config(); c.baseURL = URL(string: "http://telemetry.invalid"); variants.append(c)
        defaults.set(true, forKey: TelemetryClient.consentKey)
        expectNoRequest {
            for configuration in variants {
                let service = client(configuration)
                XCTAssertFalse(service.canEnable)
                service.record(.recipeSaved, at: Date())
            }
        }
    }
    func testExplicitConsentPersistsAndRevocationStopsNewRequests() {
        let c = client()
        c.setConsent(true)
        XCTAssertTrue(client().hasConsent)
        let sent = expectation(description: "Opted-in category sent")
        TelemetryIntercept.receive = { _ in sent.fulfill() }
        c.record(.recipeSaved, at: Date())
        wait(for: [sent], timeout: 2)
        c.setConsent(false)
        XCTAssertFalse(c.hasConsent); XCTAssertFalse(client().hasConsent)
        expectNoRequest { c.record(.recipeSaved, at: Date()) }
    }
    func testOnlyAllowlistedCategoryEnvelopeIsSentWithoutIdentifiers() {
        let c = client(); c.setConsent(true)
        let sent = expectation(description: "Inspect payload")
        TelemetryIntercept.receive = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(Set(body.keys), Set(["channel", "appVersion", "buildNumber", "gitSHA", "events"]))
            let events = body["events"] as! [[String: Any]]
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(Set(events[0].keys), Set(["kind", "timestamp"]))
            XCTAssertEqual(events[0]["kind"] as? String, "recipeSaved")
            sent.fulfill()
        }
        c.record(.recipeSaved, at: Date())
        wait(for: [sent], timeout: 2)
    }
    func testOldLocalHistoryIsNotReplayedOnConsent() {
        let c = client()
        c.record(.recipeSaved, at: Date())
        expectNoRequest { c.setConsent(true) }
    }
    func testInvalidOrExpiredEventDoesNotStartRequest() {
        let c = client(); c.setConsent(true)
        expectNoRequest {
            c.record(.recipeSaved, at: Date(timeIntervalSince1970: .nan))
            c.record(.recipeSaved, at: Date().addingTimeInterval(-8 * 24 * 60 * 60))
            c.record(.recipeSaved, at: Date().addingTimeInterval(600))
        }
    }
}
