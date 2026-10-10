import Foundation
import Security

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double      // epoch seconds
    var userID: String
    var email: String
}

protocol AuthService {
    func signUp(email: String, password: String) async throws -> AuthSession?   // nil = confirmation email sent
    func signIn(email: String, password: String) async throws -> AuthSession
    func sendMagicLink(email: String) async throws
    func refresh(_ session: AuthSession) async throws -> AuthSession
    func session(fromCallback url: URL) async throws -> AuthSession?
    func signOut(_ session: AuthSession) async
}

struct AuthError: LocalizedError { let message: String; var errorDescription: String? { message } }

/// Supabase Auth over REST (no SDK dependency). Uses only the public publishable key.
final class SupabaseAuth: AuthService {
    let baseURL: URL
    let key: String
    static let redirect = "ate://auth-callback"
    init(baseURL: URL, key: String) { self.baseURL = baseURL; self.key = key }

    private func call(_ path: String, query: [URLQueryItem] = [], body: [String: Any]?, token: String? = nil, method: String = "POST") async throws -> [String: Any] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("auth/v1/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(token ?? key)", forHTTPHeaderField: "Authorization")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else {
            let msg = (json["msg"] ?? json["error_description"] ?? json["message"] ?? json["error"]) as? String
            throw AuthError(message: msg ?? "Sign-in failed (HTTP \(code)).")
        }
        return json
    }

    private func parse(_ j: [String: Any]) -> AuthSession? {
        guard let at = j["access_token"] as? String, let rt = j["refresh_token"] as? String,
              let user = j["user"] as? [String: Any], let id = user["id"] as? String else { return nil }
        let exp = (j["expires_at"] as? Double) ?? Date().timeIntervalSince1970 + ((j["expires_in"] as? Double) ?? 3600)
        return AuthSession(accessToken: at, refreshToken: rt, expiresAt: exp, userID: id, email: (user["email"] as? String) ?? "")
    }

    func signUp(email: String, password: String) async throws -> AuthSession? {
        parse(try await call("signup", query: [URLQueryItem(name: "redirect_to", value: Self.redirect)],
                             body: ["email": email, "password": password]))
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard let s = parse(try await call("token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                           body: ["email": email, "password": password])) else { throw AuthError(message: "Unexpected sign-in response.") }
        return s
    }

    func sendMagicLink(email: String) async throws {
        _ = try await call("otp", query: [URLQueryItem(name: "redirect_to", value: Self.redirect)],
                           body: ["email": email, "create_user": true])
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let s = parse(try await call("token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                           body: ["refresh_token": session.refreshToken])) else { throw AuthError(message: "Session expired. Sign in again.") }
        return s
    }

    /// Magic-link / confirmation redirect: ate://auth-callback#access_token=…&refresh_token=…
    func session(fromCallback url: URL) async throws -> AuthSession? {
        let frag = url.fragment ?? url.query ?? ""
        var p: [String: String] = [:]
        for pair in frag.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if kv.count == 2 { p[kv[0]] = kv[1] }
        }
        if let err = p["error_description"] { throw AuthError(message: err.replacingOccurrences(of: "+", with: " ")) }
        guard let at = p["access_token"], let rt = p["refresh_token"] else { return nil }
        let user = try await call("user", body: nil, token: at, method: "GET")
        guard let id = user["id"] as? String else { return nil }
        let exp = Double(p["expires_at"] ?? "") ?? Date().timeIntervalSince1970 + (Double(p["expires_in"] ?? "") ?? 3600)
        return AuthSession(accessToken: at, refreshToken: rt, expiresAt: exp, userID: id, email: (user["email"] as? String) ?? "")
    }

    func signOut(_ session: AuthSession) async {
        _ = try? await call("logout", body: nil, token: session.accessToken)
    }
}

/// UI tests / offline demo.
final class MockAuth: AuthService {
    func make(_ email: String) -> AuthSession {
        AuthSession(accessToken: "mock", refreshToken: "mock", expiresAt: Date().timeIntervalSince1970 + 3600,
                    userID: "00000000-0000-0000-0000-000000000001", email: email)
    }
    func signUp(email: String, password: String) async throws -> AuthSession? {
        guard password.count >= 6 else { throw AuthError(message: "Password should be at least 6 characters.") }
        return make(email)
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        guard password == "password123" else { throw AuthError(message: "Invalid login credentials") }
        return make(email)
    }
    func sendMagicLink(email: String) async throws {}
    func refresh(_ session: AuthSession) async throws -> AuthSession { session }
    func session(fromCallback url: URL) async throws -> AuthSession? { make("magic@example.com") }
    func signOut(_ session: AuthSession) async {}
}

enum Keychain {
    static let service = "com.melusik.ate.auth"
    static func save(_ data: Data?, account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let data else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static func load(account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
}
