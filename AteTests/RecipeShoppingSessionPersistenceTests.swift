import XCTest
import Security
@testable import Ate

/// Native UNRUN. Injected Security calls only, no real Keychain secret reads.
@MainActor
final class RecipeShoppingSessionPersistenceTests: XCTestCase {
    private final class Storage {
        var bytes: Data?
        var readStatus: OSStatus?, updateStatus: OSStatus?, addStatus: OSStatus?, deleteStatus: OSStatus?
        var ignoreWrite = false
        var updates = 0, adds = 0, deletes = 0
        var operations: RecipeShoppingSessionPersistence.Operations {
            .init(read: { _ in (self.readStatus ?? (self.bytes == nil ? errSecItemNotFound : errSecSuccess), self.bytes) },
                  update: { _, values in
                    self.updates += 1
                    let status = self.updateStatus ?? (self.bytes == nil ? errSecItemNotFound : errSecSuccess)
                    if status == errSecSuccess && !self.ignoreWrite { self.bytes = values[kSecValueData as String] as? Data }
                    return status
                  }, add: { values in
                    self.adds += 1
                    let status = self.addStatus ?? errSecSuccess
                    if status == errSecSuccess && !self.ignoreWrite { self.bytes = values[kSecValueData as String] as? Data }
                    return status
                  }, delete: { _ in
                    self.deletes += 1
                    let status = self.deleteStatus ?? errSecSuccess
                    if status == errSecSuccess && !self.ignoreWrite { self.bytes = nil }
                    return status
                  })
        }
    }
    private func session(_ token: String = "fixture") -> AuthSession {
        .init(accessToken: token, refreshToken: "fixture", expiresAt: 4_000_000_000, userID: "owner", email: "fixture@example.test")
    }
    func testUpdateAndSignoutVerifyActualStoredSessionBeforeCachePublication() throws {
        let storage = Storage(); storage.bytes = try JSONEncoder().encode(session())
        let state = try RecipeShoppingSessionPersistence(operations: storage.operations)
        try state.persist(session("fresh"))
        XCTAssertEqual(try state.verifiedCurrent(), session("fresh"))
        XCTAssertEqual(storage.updates, 1); XCTAssertEqual(storage.adds, 0); XCTAssertEqual(storage.deletes, 0)
        try state.persist(nil)
        XCTAssertNil(try state.verifiedCurrent()); XCTAssertNil(storage.bytes); XCTAssertEqual(storage.deletes, 1)
    }
    func testMissingItemAddsOnlyAfterUpdateNotFoundAndVerifies() throws {
        let storage = Storage(); let state = try RecipeShoppingSessionPersistence(operations: storage.operations)
        try state.persist(session())
        XCTAssertEqual(state.current, session()); XCTAssertEqual(storage.updates, 1); XCTAssertEqual(storage.adds, 1)
    }
    func testFailedUpdateNeverDeletesOrPublishesNewSession() throws {
        let storage = Storage(); let original = try JSONEncoder().encode(session()); storage.bytes = original
        storage.updateStatus = errSecInteractionNotAllowed
        let state = try RecipeShoppingSessionPersistence(operations: storage.operations)
        XCTAssertThrowsError(try state.persist(session("fresh")))
        XCTAssertEqual(storage.bytes, original); XCTAssertEqual(state.current, session())
        XCTAssertEqual(storage.deletes, 0); XCTAssertEqual(storage.adds, 0)
    }
    func testFalseSuccessReadbackAndConcurrentReplacementRefuseCachePublication() throws {
        let storage = Storage(); storage.bytes = try JSONEncoder().encode(session()); storage.ignoreWrite = true
        let state = try RecipeShoppingSessionPersistence(operations: storage.operations)
        XCTAssertThrowsError(try state.persist(session("fresh")))
        XCTAssertEqual(state.current, session())
        storage.bytes = try JSONEncoder().encode(session("replaced-elsewhere"))
        XCTAssertThrowsError(try state.verifiedCurrent())
        XCTAssertThrowsError(try state.persist(nil))
        XCTAssertEqual(storage.deletes, 0)
    }
    func testLockedCorruptAndSuccessfulButNonDataReadsNeverBecomeSignedOut() throws {
        let locked = Storage(); locked.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try RecipeShoppingSessionPersistence(operations: locked.operations))
        let corrupt = Storage(); corrupt.bytes = Data("bad".utf8)
        XCTAssertThrowsError(try RecipeShoppingSessionPersistence(operations: corrupt.operations))
        let unreadable = Storage(); unreadable.readStatus = errSecSuccess
        XCTAssertThrowsError(try RecipeShoppingSessionPersistence(operations: unreadable.operations))
    }
    func testDeleteAndAddFailuresPropagateWithoutPublishing() throws {
        let existing = Storage(); existing.bytes = try JSONEncoder().encode(session()); existing.deleteStatus = errSecAuthFailed
        let state = try RecipeShoppingSessionPersistence(operations: existing.operations)
        XCTAssertThrowsError(try state.persist(nil)); XCTAssertNotNil(state.current)
        let missing = Storage(); missing.addStatus = errSecAuthFailed
        let empty = try RecipeShoppingSessionPersistence(operations: missing.operations)
        XCTAssertThrowsError(try empty.persist(session())); XCTAssertNil(empty.current)
    }
}
