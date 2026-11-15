import XCTest
import Security
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

private actor AuthRefreshTestLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    func wait() async {
        calls += 1
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

extension AuthHardeningTests {
    func testConcurrentRefreshSharesRequestEvenWhenOneWaiterIsCancelled() async throws {
        let gate = AuthRefreshFlight()
        let latch = AuthRefreshTestLatch()
        let original = MockAuth().make("fixture@example.test")
        var rotated = original; rotated.accessToken = "rotated-access"; rotated.refreshToken = "rotated-refresh"
        let result = rotated
        let operation: () async throws -> AuthSession = { await latch.wait(); return result }
        let first = Task { try await gate.refresh(original, operation: operation) }
        let second = Task { try await gate.refresh(original, operation: operation) }
        for _ in 0..<10000 {
            let count = await gate.waitingCallCount
            if count == 2 { break }
            await Task.yield()
        }
        let waiting = await gate.waitingCallCount
        XCTAssertEqual(waiting, 2, "both callers must overlap before release")
        second.cancel()
        await latch.release()
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, result)
        XCTAssertEqual(secondValue, result)
        let calls = await latch.calls
        XCTAssertEqual(calls, 1, "rotation must use only one network operation")
    }

    func testFailedRefreshFlightIsRemovedAndDoesNotCacheFailure() async throws {
        let gate = AuthRefreshFlight()
        let original = MockAuth().make("fixture@example.test")
        do {
            _ = try await gate.refresh(original) { throw AuthError(.unauthorized, "fixture") }
            XCTFail("rejection swallowed")
        } catch { XCTAssertEqual((error as? AuthError)?.kind, .unauthorized) }
        let recovered = try await gate.refresh(original) { original }
        XCTAssertEqual(recovered, original)
        let waiting = await gate.waitingCallCount
        XCTAssertEqual(waiting, 0)
    }

    func testDifferentSessionsDoNotShareRefreshResults() async throws {
        let gate = AuthRefreshFlight()
        let a = MockAuth().make("a@example.test")
        var b = a; b.refreshToken = "other-refresh"; b.userID = "other-user"
        let first = try await gate.refresh(a) { a }
        let other = b
        let second = try await gate.refresh(other) { other }
        XCTAssertEqual(first, a)
        XCTAssertEqual(second, b)
    }
}

extension AuthHardeningTests {
    func testCredentialUpdateNeverDeletesAndPreservesQueryScope() {
        var calls: [String] = []
        let bytes = Data("fixture".utf8)
        let operations = Keychain.Operations(update: { query, values in
            calls.append("update")
            XCTAssertEqual(query[kSecAttrService as String] as? String, Keychain.service)
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "fixture")
            XCTAssertEqual(values[kSecValueData as String] as? Data, bytes)
            return errSecSuccess
        }, add: { _ in calls.append("add"); return errSecSuccess },
           delete: { _ in calls.append("delete"); return errSecSuccess })
        XCTAssertTrue(Keychain.save(bytes, account: "fixture", operations: operations))
        XCTAssertEqual(calls, ["update"])
    }

    func testCredentialMissingAddsButOtherUpdateFailuresDoNotMutateAgain() {
        for status in [errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed] {
            var calls: [String] = []
            let operations = Keychain.Operations(update: { _, _ in calls.append("update"); return status },
                add: { _ in calls.append("add"); return errSecSuccess },
                delete: { _ in calls.append("delete"); return errSecSuccess })
            XCTAssertEqual(Keychain.save(Data("fixture".utf8), account: "fixture", operations: operations),
                           status == errSecItemNotFound)
            XCTAssertEqual(calls, status == errSecItemNotFound ? ["update", "add"] : ["update"])
        }
    }

    func testCredentialAddFailureIsFalseWithoutDeleteOrRetry() {
        var calls: [String] = []
        let operations = Keychain.Operations(update: { _, _ in calls.append("update"); return errSecItemNotFound },
            add: { _ in calls.append("add"); return errSecDuplicateItem },
            delete: { _ in calls.append("delete"); return errSecSuccess })
        XCTAssertFalse(Keychain.save(Data("fixture".utf8), account: "fixture", operations: operations))
        XCTAssertEqual(calls, ["update", "add"])
    }

    func testCredentialRemovalChecksStatusAndMissingIsAlreadyRemoved() {
        for status in [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed] {
            var calls: [String] = []
            let operations = Keychain.Operations(update: { _, _ in calls.append("update"); return errSecSuccess },
                add: { _ in calls.append("add"); return errSecSuccess },
                delete: { _ in calls.append("delete"); return status })
            XCTAssertEqual(Keychain.save(nil, account: "fixture", operations: operations),
                           status == errSecSuccess || status == errSecItemNotFound)
            XCTAssertEqual(calls, ["delete"])
        }
    }
}
