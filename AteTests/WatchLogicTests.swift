import XCTest
@testable import Ate

final class WatchLogicTests: XCTestCase {
    private func row(_ kind: String, _ id: String, _ data: String?, _ t: Int64, deleted: Bool = false) throws -> WatchRow {
        let d = try data.map { try JSONDecoder().decode(WatchJSON.self, from: Data($0.utf8)) }
        return WatchRow(kind: kind, id: id, data: d, updated_at: t, deleted: deleted)
    }

    func testDecodesRecipesAndShoppingFromRows() throws {
        let rows = [
            try row("recipe", "r1", #"{"title":"Pasta","timeMinutes":20,"ingredients":[{"name":"spaghetti","quantity":200,"unit":"g"}],"steps":[{"order":2,"instruction":"Drain"},{"order":1,"instruction":"Boil","timeSeconds":600}]}"#, 1),
            try row("shopping", "s1", #"{"name":"Milk","quantity":1,"unit":"l","done":false,"aisle":"dairy"}"#, 1),
        ]
        let out = WatchRows.decode(rows)
        XCTAssertEqual(out.recipes.count, 1)
        XCTAssertEqual(out.recipes[0].steps.map(\.instruction), ["Boil", "Drain"])
        XCTAssertEqual(out.recipes[0].steps[0].timeSeconds, 600)
        XCTAssertEqual(out.recipes[0].ingredientLines, ["200 g spaghetti"])
        XCTAssertEqual(out.shopping.first?.name, "Milk")
    }

    func testTombstonesAndNewestWin() throws {
        let rows = [
            try row("recipe", "r1", #"{"title":"Old"}"#, 1),
            try row("recipe", "r1", #"{"title":"New"}"#, 5),
            try row("recipe", "r2", nil, 3, deleted: true),
        ]
        let out = WatchRows.decode(rows)
        XCTAssertEqual(out.recipes.map(\.title), ["New"])
    }

    func testToggleKeepsRawFieldsAndBumpsClock() throws {
        let out = WatchRows.decode([try row("shopping", "s1", #"{"id":"s1","name":"Eggs","quantity":6,"unit":"","done":false,"aisle":"dairy"}"#, 100)])
        let (item, r) = WatchRows.toggled(out.shopping[0], nowMs: 50)
        XCTAssertTrue(item.done)
        XCTAssertEqual(r.updated_at, 101)
        XCTAssertEqual(r.data?.object?["aisle"]?.string, "dairy")
        XCTAssertEqual(r.data?.object?["done"]?.bool, true)
    }

    func testStepperClampsAndCrownMapping() {
        var s = CookStepper(count: 3)
        s.back(); XCTAssertEqual(s.index, 0)
        s.next(); s.next(); s.next(); XCTAssertEqual(s.index, 2); XCTAssertTrue(s.isLast)
        XCTAssertEqual(s.progressLabel, "Step 3 of 3")
        XCTAssertEqual(CookStepper.index(forCrown: 1.4, count: 3), 1)
        XCTAssertEqual(CookStepper.index(forCrown: 9, count: 3), 2)
        XCTAssertEqual(CookStepper.index(forCrown: -2, count: 3), 0)
    }

    func testStepTimerPauseResume() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var t = WatchStepTimer.start(title: "Pasta", step: 0, seconds: 60, now: t0)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(10)), 50)
        t.pause(at: t0.addingTimeInterval(10)); XCTAssertNil(t.endDate)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(100)), 50)
        t.resume(at: t0.addingTimeInterval(100))
        XCTAssertTrue(t.isFinished(at: t0.addingTimeInterval(150)))
        XCTAssertFalse(t.isFinished(at: t0.addingTimeInterval(149)))
    }

    func testBridgePayloadRoundTrip() {
        let p = WatchBridgePayload(session: .init(accessToken: "a", refreshToken: "r", expiresAt: 1, userID: "u", email: "e@x.com"),
                                   cook: [.init(recipeID: "r1", recipeTitle: "Pasta", stepIndex: 1, stepCount: 3, stepText: "Boil", timerEnd: nil, timerRemaining: 30)])
        XCTAssertEqual(WatchBridgePayload.from(p.dictionary()), p)
        XCTAssertNil(WatchBridgePayload.from([:]))
    }

    func testAuthRequestsAndValidation() {
        let base = URL(string: "https://x.supabase.co")!
        let (u, b) = WatchAuthRequests.verify(base: base, email: " Me@X.com ", code: "12 34 56")
        XCTAssertEqual(u.absoluteString, "https://x.supabase.co/auth/v1/verify")
        XCTAssertEqual(b["email"] as? String, "me@x.com"); XCTAssertEqual(b["token"] as? String, "123456")
        XCTAssertTrue(WatchAuthRequests.isValidCode("123456")); XCTAssertFalse(WatchAuthRequests.isValidCode("12"))
        XCTAssertTrue(WatchAuthRequests.isPlausibleEmail("a@b.co")); XCTAssertFalse(WatchAuthRequests.isPlausibleEmail("ab"))
        XCTAssertTrue(WatchAuthRequests.needsRefresh(expiresAt: 100, now: Date(timeIntervalSince1970: 50)))
        XCTAssertTrue(WatchAuthRequests.rowsURL(base: base).absoluteString.contains("rest/v1/user_recipes?select="))
    }

    func testFormat() {
        XCTAssertEqual(WatchFormat.quantity(1.5), "1½")
        XCTAssertEqual(WatchFormat.quantity(0.25), "¼")
        XCTAssertEqual(WatchFormat.mmss(125), "2:05")
    }
}
