import XCTest
@testable import Ate

final class AuthHardeningTests: XCTestCase {
    func testPasswordPolicy() {
        XCTAssertFalse(PasswordPolicy.evaluate("abc").ok)
        XCTAssertFalse(PasswordPolicy.evaluate("abcdefgh").ok, "needs a digit")
        XCTAssertFalse(PasswordPolicy.evaluate("12345678").ok, "needs a letter")
        XCTAssertFalse(PasswordPolicy.evaluate("password123").ok, "common")
        XCTAssertTrue(PasswordPolicy.evaluate("Kitchen2026").ok)
        XCTAssertGreaterThan(PasswordPolicy.evaluate("Braai-Night-2026!").strength, PasswordPolicy.evaluate("kitchen26").strength)
    }

    func testObfuscatedExistingUserDetected() {
        XCTAssertTrue(SupabaseAuth.isObfuscatedExistingUser(["id": "u1", "email": "a@b.co", "identities": []]))
        XCTAssertTrue(SupabaseAuth.isObfuscatedExistingUser(["user": ["id": "u1", "identities": []]]))
        XCTAssertFalse(SupabaseAuth.isObfuscatedExistingUser(["id": "u1", "identities": [["provider": "email"]]]))
    }

    func testEmailRateLimitMessage() {
        let e = AuthError.from(status: 429, json: ["error_code": "over_email_send_rate_limit"])
        XCTAssertEqual(e.kind, .rateLimited); XCTAssertTrue(e.message.hasPrefix("Email limit reached — try again in about an hour"))
        XCTAssertTrue(AuthError.from(status: 429, json: ["msg": "email rate limit exceeded"]).message.hasPrefix("Email limit"))
        XCTAssertTrue(AuthError.from(status: 429, json: ["error_code": "over_request_rate_limit"]).message.contains("Wait a minute"))
    }

    func testCooldown() throws {
        let suite = "cooldown-test-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(EmailCooldown.remaining(.reset, now: t0, defaults: d), 0)
        EmailCooldown.record(.reset, rateLimited: true, now: t0, defaults: d)
        XCTAssertEqual(EmailCooldown.remaining(.reset, now: t0.addingTimeInterval(600), defaults: d), 3000)
        XCTAssertEqual(EmailCooldown.label(3000), "in about 50 min")
        XCTAssertEqual(EmailCooldown.label(42), "in 42 s")
    }

    func testServerWeakPasswordAndDuplicateMapping() {
        let w = AuthError.from(status: 422, json: ["error_code": "weak_password", "msg": "Password should contain at least one character of each: abc..., 012..."])
        XCTAssertEqual(w.kind, .weakPassword); XCTAssertFalse(w.message.isEmpty)
        XCTAssertEqual(AuthError.from(status: 422, json: ["error_code": "user_already_exists"]).kind, .userExists)
        XCTAssertFalse(SupabaseAuth.isObfuscatedExistingUser(["id": "u1"]), "no identities key is not a duplicate")
    }

    func testMockSignUpOutcomes() async {
        let m = MockAuth()
        do { _ = try await m.signUp(email: "new@example.com", password: "abc"); XCTFail("weak accepted") }
        catch { XCTAssertEqual((error as? AuthError)?.kind, .weakPassword) }
        do { _ = try await m.signUp(email: "exists@example.com", password: "Cooking2026"); XCTFail() }
        catch { XCTAssertEqual((error as? AuthError)?.kind, .userExists) }
        do { _ = try await m.signUp(email: "ratelimit@example.com", password: "Cooking2026"); XCTFail() }
        catch { XCTAssertEqual((error as? AuthError)?.kind, .rateLimited) }
    }
}
