import XCTest
@testable import Ate

final class ProductUpdatesLaunchTests: XCTestCase {
    private func catalog(version: String = "0.1.0", slides: Bool = true) throws -> ProductUpdatesCatalog {
        let page = #"{"id":"intro","imageAsset":"local","imageAlt":"Alt","title":"Title","body":"Body","placeholder":false}"#
        return try ProductUpdatesCatalog.decode(Data("""
        {"schemaVersion":1,"releases":[{"id":"pilot","title":"Pilot candidate","version":"\(version)","minimumBuild":1,"channel":"all","summary":"Feature first","changes":[],"slides":[\(slides ? page : "")]}]}
        """.utf8))
    }
    func testUnseenOnlyAndSeenPersistenceAcrossNewStoreAndDefaultsInstance() throws {
        let suite = "product-updates-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ProductUpdatesSeenStore(defaults: defaults)
        let local = try catalog()
        XCTAssertNotNil(first.unseenRelease(in: local, version: "0.1.0", build: 1, channel: "release"))
        XCTAssertFalse(first.hasSeen("0.1.0"), "Selection is not dismissal")
        first.markSeen("0.1.0")
        let relaunched = ProductUpdatesSeenStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertTrue(relaunched.hasSeen("0.1.0"))
        XCTAssertNil(relaunched.unseenRelease(in: local, version: "0.1.0", build: 99, channel: "release"))
        XCTAssertNotNil(relaunched.unseenRelease(in: try catalog(version: "0.1.1"), version: "0.1.1", build: 1, channel: "release"))
        XCTAssertTrue(first.hasSeen("0.1.0"))
    }
    func testMissingUnknownFutureAndNoSlideCatalogsNeverInventLaunchRelease() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let seen = ProductUpdatesSeenStore(defaults: defaults)
        XCTAssertNil(seen.unseenRelease(in: nil, version: "0.1.0", build: 1, channel: "release"))
        XCTAssertNil(seen.unseenRelease(in: try catalog(), version: "0.1.1", build: 1, channel: "release"))
        XCTAssertNil(seen.unseenRelease(in: try catalog(), version: "0.1.0", build: 0, channel: "release"))
        XCTAssertNil(seen.unseenRelease(in: try catalog(slides: false), version: "0.1.0", build: 1, channel: "release"))
    }
    func testCatalogCodableRoundTripAndBundledOfflineSeed() throws {
        let local = try XCTUnwrap(ProductUpdatesCatalog.load())
        let decoded = try ProductUpdatesCatalog.decode(JSONEncoder().encode(local))
        XCTAssertEqual(decoded.releases.map(\.id), local.releases.map(\.id))
        XCTAssertEqual(decoded.releases.first?.version, "0.1.0")
        XCTAssertEqual(decoded.releases.first?.slides.count, 2)
        XCTAssertFalse(try XCTUnwrap(decoded.releases.first?.whatToTest).isEmpty)
        XCTAssertFalse(try XCTUnwrap(decoded.releases.first?.howToTest).isEmpty)
    }
}

extension ProductUpdatesLaunchTests {
    func testIncomingColdWarmAndOnboardingHandoffNeverMarksTourSeen() {
        let url = URL(string: "ate://shopping")!
        var cold = ProductUpdatesIncomingWork()
        XCTAssertTrue(cold.receive(url), "Cold callback may route before any tour starts")
        XCTAssertTrue(cold.received, "Launch selection stays suppressed for this session")
        var warm = ProductUpdatesIncomingWork()
        warm.tourPresented = true
        XCTAssertFalse(warm.receive(url), "Hold routing until the presented tour dismisses")
        XCTAssertEqual(warm.finishTour(), [url])
        XCTAssertFalse(warm.tourPresented)
        XCTAssertTrue(warm.received)
        XCTAssertTrue(warm.finishTour().isEmpty, "No duplicate route delivery")
        var onboarding = ProductUpdatesIncomingWork()
        XCTAssertTrue(onboarding.receive(url))
        XCTAssertTrue(onboarding.received, "Finishing onboarding must not discard incoming priority")
    }
}

@MainActor
final class ProductUpdatesIncomingRouteTests: XCTestCase {
    func testRealStoreHandlerBlocksWarmTourAndKeepsColdOnboardingPriority() {
        let store = AppStore(context: nil, backend: MockBackend())
        let url = URL(string: "ate://shopping")!
        store.showOnboarding = true
        store.handle(url: url)
        XCTAssertTrue(store.productUpdatesIncomingWork.received)
        XCTAssertEqual(store.tab, .shopping)
        store.finishOnboarding()
        XCTAssertFalse(store.showOnboarding)
        XCTAssertTrue(store.productUpdatesIncomingWork.received)
        store.select(.library)
        store.productUpdatesIncomingWork.tourPresented = true
        store.handle(url: url)
        XCTAssertEqual(store.tab, .library, "Do not route a competing presentation until tour dismissal")
        let pending = store.productUpdatesIncomingWork.finishTour()
        XCTAssertEqual(pending, [url])
        pending.forEach { store.handle(url: $0) }
        XCTAssertEqual(store.tab, .shopping)
    }
}
