import XCTest
@testable import Ate

final class CookSessionIdentityTests: XCTestCase {
    func testNewCooksOfSameRecipeHaveDifferentIdentity() {
        let first = CookSession(recipeID: "r1", stepIndex: 0)
        let next = CookSession(recipeID: "r1", stepIndex: 0)
        XCTAssertNotEqual(first.sessionID, next.sessionID)
        XCTAssertNotNil(UUID(uuidString: first.sessionID))
    }

    func testIdentitySurvivesCodableRoundTripAndSessionEdits() throws {
        var session = CookSession(recipeID: "r1", stepIndex: 1, factor: 2, checked: [0])
        let id = session.sessionID
        session.stepIndex = 3
        session.factor = 4
        session.toggleChecked(2)
        let reopened = try JSONDecoder().decode(CookSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(reopened, session)
        XCTAssertEqual(reopened.sessionID, id)
    }

    func testLegacySnapshotGainsIdentityAndRetainsEveryOldField() throws {
        let raw = Data(#"{"recipeID":"r1","stepIndex":2,"factor":3,"checked":[0,2],"ingredientSignature":"sig"}"#.utf8)
        let session = try JSONDecoder().decode(CookSession.self, from: raw)
        XCTAssertNotNil(UUID(uuidString: session.sessionID))
        XCTAssertEqual(session.recipeID, "r1")
        XCTAssertEqual(session.stepIndex, 2)
        XCTAssertEqual(session.factor, 3)
        XCTAssertEqual(session.checked, [0,2])
        XCTAssertEqual(session.ingredientSignature, "sig")
        let saved = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(CookSession.self, from: saved).sessionID, session.sessionID)
    }
}

@MainActor
final class CookSessionIdentityLifecycleTests: XCTestCase {
    private func withStore(_ body: (AppStore) throws -> Void) throws {
        let keys = ["ate.cookSession.v1", "ate.settings.v1", "ate.timerprefs.v1"]
        let before = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = before[key] ?? nil { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let store = AppStore(context: nil, backend: MockBackend())
        store.cookSession = nil
        try body(store)
    }

    func testResumeRetainsIdentityReplacementAndNewCookDoNot() throws {
        try withStore { store in
            store.beginCookSession(recipeID: "r1", factor: 2)
            let first = try XCTUnwrap(store.cookSession).sessionID
            store.updateCookSession(recipeID: "r1", stepIndex: 3)
            store.setCookFactor(4)
            store.beginCookSession(recipeID: "r1", factor: 1)
            XCTAssertEqual(store.cookSession?.sessionID, first)
            let prepared = try store.prepareCookCompletion(recipeID: "r1")
            let raw = try XCTUnwrap(UserDefaults.standard.data(forKey: "ate.cookSession.v1"))
            XCTAssertEqual(try JSONDecoder().decode(CookSession.self, from: raw), prepared)
            store.beginCookSession(recipeID: "r2", factor: 1)
            XCTAssertNotEqual(store.cookSession?.sessionID, first)
            XCTAssertThrowsError(try store.clearCompletedCookSession(sessionID: first))
            XCTAssertEqual(store.cookSession?.recipeID, "r2")
            store.clearCookSession()
            store.beginCookSession(recipeID: "r1", factor: 1)
            XCTAssertNotEqual(store.cookSession?.sessionID, first)
        }
    }

    func testMissingWrongRecipeAndInvalidIdentityFailBeforeAnySessionClear() throws {
        try withStore { store in
            XCTAssertThrowsError(try store.prepareCookCompletion(recipeID: "r1"))
            store.cookSession = CookSession(recipeID: "r1", stepIndex: 0, sessionID: "invalid")
            let raw = UserDefaults.standard.data(forKey: "ate.cookSession.v1")
            XCTAssertThrowsError(try store.prepareCookCompletion(recipeID: "r1"))
            XCTAssertThrowsError(try store.prepareCookCompletion(recipeID: "r2"))
            XCTAssertEqual(store.cookSession?.sessionID, "invalid")
            XCTAssertEqual(UserDefaults.standard.data(forKey: "ate.cookSession.v1"), raw)
        }
    }

    func testOldSameRecipeCompletionCannotClearNewCookAndSuccessfulClearVerifiesAbsent() throws {
        try withStore { store in
            store.beginCookSession(recipeID: "r1", factor: 1)
            let first = try store.prepareCookCompletion(recipeID: "r1")
            try store.clearCompletedCookSession(sessionID: first.sessionID)
            XCTAssertNil(store.cookSession)
            XCTAssertNil(UserDefaults.standard.object(forKey: "ate.cookSession.v1"))
            store.beginCookSession(recipeID: "r1", factor: 1)
            let second = try store.prepareCookCompletion(recipeID: "r1")
            XCTAssertNotEqual(second.sessionID, first.sessionID)
            XCTAssertThrowsError(try store.clearCompletedCookSession(sessionID: first.sessionID))
            XCTAssertEqual(store.cookSession, second)
        }
    }
}
