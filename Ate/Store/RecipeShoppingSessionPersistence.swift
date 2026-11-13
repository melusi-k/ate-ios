import Foundation
import Security

/// Dormant checked Keychain binding for the standalone coordinator. Legacy
/// Keychain.save remains unchanged and is NOT an acceptable writer in this graph.
/// No secret is logged; native tests inject storage, never touch real credentials.
@MainActor
final class RecipeShoppingSessionPersistence {
    enum Failure: Error { case keychain(OSStatus), unreadableValue, malformedSession, changedSession, writeUnverified }
    struct Operations {
        var read: ([String: Any]) -> (OSStatus, Data?)
        var update: ([String: Any], [String: Any]) -> OSStatus
        var add: ([String: Any]) -> OSStatus
        var delete: ([String: Any]) -> OSStatus
        static let live = Operations(read: { query in
            var out: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &out)
            return (status, out as? Data)
        }, update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
           add: { SecItemAdd($0 as CFDictionary, nil) }, delete: { SecItemDelete($0 as CFDictionary) })
    }
    private let operations: Operations
    private let query: [String: Any]
    private(set) var current: AuthSession?

    init(account: String = "session", operations: Operations = .live) throws {
        self.operations = operations
        query = [kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: Keychain.service, kSecAttrAccount as String: account]
        current = nil
        current = try decode(readBytes())
    }
    private func readBytes() throws -> Data? {
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = operations.read(readQuery)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data else { throw Failure.unreadableValue }
        return data
    }
    private func decode(_ bytes: Data?) throws -> AuthSession? {
        guard let bytes else { return nil }
        guard let session = try? JSONDecoder().decode(AuthSession.self, from: bytes),
              !session.userID.isEmpty, !session.accessToken.isEmpty,
              !session.refreshToken.isEmpty, session.expiresAt.isFinite else { throw Failure.malformedSession }
        return session
    }
    /// Strict startup/post-await check. A locked/unreadable item is an error, not
    /// signed out. The host must surface it, not turn try? into a nil session.
    func verifiedCurrent() throws -> AuthSession? {
        let stored = try decode(readBytes())
        guard stored == current else { throw Failure.changedSession }
        return stored
    }
    /// Throws for Security status AND exact readback. Update-in-place preserves
    /// the prior item on update failure, unlike delete-then-add. No rollback claim:
    /// readback can fail after the actual write. Cache publishes only on success.
    func persist(_ session: AuthSession?) throws {
        _ = try verifiedCurrent()
        let bytes = try session.map { value -> Data in
            guard !value.userID.isEmpty, !value.accessToken.isEmpty, !value.refreshToken.isEmpty,
                  value.expiresAt.isFinite else { throw Failure.malformedSession }
            return try JSONEncoder().encode(value)
        }
        let status: OSStatus
        if let bytes {
            let update = operations.update(query, [kSecValueData as String: bytes])
            if update == errSecItemNotFound {
                var add = query; add[kSecValueData as String] = bytes
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                status = operations.add(add)
            } else { status = update }
            guard status == errSecSuccess else { throw Failure.keychain(status) }
        } else {
            status = operations.delete(query)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
        }
        let stored = try readBytes()
        guard stored == bytes, try decode(stored) == session else { throw Failure.writeUnverified }
        current = session
    }
}
