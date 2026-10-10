import Foundation
import Security
import CryptoKit

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double      // epoch seconds
    var userID: String
    var email: String
}

enum AuthCallback: Equatable {
    case signedIn(AuthSession)
    case recovery(AuthSession)      // password-reset link: user must set a new password
    case confirmedNeedsSignIn       // email confirmed on another device / no PKCE verifier
}

protocol AuthService {
    func signUp(email: String, password: String) async throws -> AuthSession?   // nil = confirmation email sent
    func signIn(email: String, password: String) async throws -> AuthSession
    func sendMagicLink(email: String) async throws
    func resendConfirmation(email: String) async throws
    func recoverPassword(email: String) async throws
    func updatePassword(_ session: AuthSession, to password: String) async throws
    func refresh(_ session: AuthSession) async throws -> AuthSession
    func session(fromCallback url: URL) async throws -> AuthCallback?
    func signOut(_ session: AuthSession) async
    func deleteAccount(_ session: AuthSession) async throws
}

struct AuthError: LocalizedError, Equatable {
    enum Kind: Equatable { case invalidCredentials, emailNotConfirmed, rateLimited, offline, userExists, weakPassword, expiredLink, unauthorized, other }
    let kind: Kind
    let message: String
    init(_ kind: Kind = .other, _ message: String) { self.kind = kind; self.message = message }
    init(message: String) { self.init(.other, message) }
    var errorDescription: String? { message }

    /// Maps Supabase Auth (GoTrue) responses to friendly copy.
    static func from(status: Int, json: [String: Any]) -> AuthError {
        let code = (json["error_code"] as? String) ?? (json["error"] as? String) ?? ""
        let raw = (json["msg"] ?? json["error_description"] ?? json["message"]) as? String
        switch code {
        case "invalid_credentials":
            return AuthError(.invalidCredentials, "Wrong email or password.")
        case "email_not_confirmed":
            return AuthError(.emailNotConfirmed, "Confirm your email first. Check your inbox, or resend the link.")
        case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit":
            return AuthError(.rateLimited, "Too many attempts. Wait a minute and try again.")
        case "user_already_exists", "email_exists":
            return AuthError(.userExists, "There's already an account with this email. Sign in instead.")
        case "weak_password":
            return AuthError(.weakPassword, raw ?? "Choose a stronger password (at least 6 characters).")
        case "otp_expired", "flow_state_expired", "flow_state_not_found", "bad_code_verifier":
            return AuthError(.expiredLink, "This link has expired or was opened on another device. Request a new one.")
        case "signup_disabled":
            return AuthError(.other, "New sign-ups are turned off right now.")
        case "email_address_invalid", "validation_failed":
            return AuthError(.other, raw ?? "Check the email address and try again.")
        default: break
        }
        if status == 429 { return AuthError(.rateLimited, "Too many attempts. Wait a minute and try again.") }
        if status == 401 || status == 403 { return AuthError(.unauthorized, "Your session expired. Sign in again.") }
        if raw?.lowercased().contains("invalid login") == true { return AuthError(.invalidCredentials, "Wrong email or password.") }
        if status >= 500 { return AuthError(.other, "ate's server had a problem. Try again in a moment.") }
        return AuthError(.other, raw ?? "Sign-in failed (HTTP \(status)).")
    }

    static func network(_ error: Error) -> AuthError {
        if let a = error as? AuthError { return a }
        if let u = error as? URLError {
            let offline: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff]
            return AuthError(offline.contains(u.code) ? .offline : .other, Net.friendly(u))
        }
        return AuthError(.other, error.localizedDescription)
    }
}

/// Supabase Auth over REST (no SDK). Uses only the public publishable key; email links use PKCE.
final class SupabaseAuth: AuthService {
    let baseURL: URL
    let key: String
    static let redirect = "ate://auth-callback"
    init(baseURL: URL, key: String) { self.baseURL = baseURL; self.key = key }

    @discardableResult
    private func call(_ path: String, query: [URLQueryItem] = [], body: [String: Any]?, token: String? = nil,
                      method: String = "POST", base: String = "auth/v1/") async throws -> [String: Any] {
        var comps = URLComponents(url: baseURL.appendingPathComponent(base + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Net.authorize(&r, key: key, bearer: token)
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await Net.data(for: r) } catch { throw AuthError.network(error) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else { throw AuthError.from(status: code, json: json) }
        return json
    }

    private func parse(_ j: [String: Any]) -> AuthSession? {
        guard let at = j["access_token"] as? String, let rt = j["refresh_token"] as? String,
              let user = j["user"] as? [String: Any], let id = user["id"] as? String else { return nil }
        let exp = (j["expires_at"] as? Double) ?? Date().timeIntervalSince1970 + ((j["expires_in"] as? Double) ?? 3600)
        return AuthSession(accessToken: at, refreshToken: rt, expiresAt: exp, userID: id, email: (user["email"] as? String) ?? "")
    }

    // MARK: PKCE (verifier kept in the Keychain until the email link comes back)
    private func pkce(flow: String) -> [String: Any] {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        Keychain.save(Data("\(flow)|\(verifier)".utf8), account: "pkce")
        return ["code_challenge": challenge, "code_challenge_method": "s256"]
    }
    private var redirectQuery: [URLQueryItem] { [URLQueryItem(name: "redirect_to", value: Self.redirect)] }

    func signUp(email: String, password: String) async throws -> AuthSession? {
        var body: [String: Any] = ["email": email, "password": password]
        body.merge(pkce(flow: "signup")) { $1 }
        return parse(try await call("signup", query: redirectQuery, body: body))
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard let s = parse(try await call("token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                           body: ["email": email, "password": password])) else { throw AuthError(message: "Unexpected sign-in response.") }
        return s
    }

    func sendMagicLink(email: String) async throws {
        var body: [String: Any] = ["email": email, "create_user": true]
        body.merge(pkce(flow: "magiclink")) { $1 }
        try await call("otp", query: redirectQuery, body: body)
    }

    func resendConfirmation(email: String) async throws {
        try await call("resend", query: redirectQuery, body: ["type": "signup", "email": email])
    }

    func recoverPassword(email: String) async throws {
        var body: [String: Any] = ["email": email]
        body.merge(pkce(flow: "recovery")) { $1 }
        try await call("recover", query: redirectQuery, body: body)
    }

    func updatePassword(_ session: AuthSession, to password: String) async throws {
        try await call("user", body: ["password": password], token: session.accessToken, method: "PUT")
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let s = parse(try await call("token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                           body: ["refresh_token": session.refreshToken])) else { throw AuthError(.unauthorized, "Session expired. Sign in again.") }
        return s
    }

    /// Parses `ate://auth-callback` in all shapes Supabase sends:
    /// `?code=…` (PKCE), `#access_token=…&refresh_token=…&type=…` (implicit), and `#error=…&error_description=…`.
    func session(fromCallback url: URL) async throws -> AuthCallback? {
        let p = Self.params(url)
        if let err = p["error_description"] ?? p["error"] {
            if p["error_code"] == "otp_expired" { throw AuthError(.expiredLink, "This link has expired. Request a new one.") }
            throw AuthError(.other, err)
        }
        let stored = Keychain.load(account: "pkce").map { String(decoding: $0, as: UTF8.self) }
        let flow = stored?.split(separator: "|").first.map(String.init)
        if let code = p["code"] {
            guard let verifier = stored?.split(separator: "|").last.map(String.init) else { return .confirmedNeedsSignIn }
            let j = try await call("token", query: [URLQueryItem(name: "grant_type", value: "pkce")],
                                   body: ["auth_code": code, "code_verifier": verifier])
            Keychain.save(nil, account: "pkce")
            guard let s = parse(j) else { return nil }
            return flow == "recovery" ? .recovery(s) : .signedIn(s)
        }
        guard let at = p["access_token"], let rt = p["refresh_token"] else { return nil }
        let user = try await call("user", body: nil, token: at, method: "GET")
        guard let id = user["id"] as? String else { return nil }
        let exp = Double(p["expires_at"] ?? "") ?? Date().timeIntervalSince1970 + (Double(p["expires_in"] ?? "") ?? 3600)
        let s = AuthSession(accessToken: at, refreshToken: rt, expiresAt: exp, userID: id, email: (user["email"] as? String) ?? "")
        return p["type"] == "recovery" ? .recovery(s) : .signedIn(s)
    }

    static func params(_ url: URL) -> [String: String] {
        var p: [String: String] = [:]
        for part in [url.query, url.fragment].compactMap({ $0 }) {
            for pair in part.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map {
                    String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
                }
                if kv.count == 2 { p[kv[0]] = kv[1] }
            }
        }
        return p
    }

    func signOut(_ session: AuthSession) async {
        _ = try? await call("logout", body: nil, token: session.accessToken)
    }

    func deleteAccount(_ session: AuthSession) async throws {
        try await call("delete-account", body: [:], token: session.accessToken, base: "functions/v1/")
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// UI tests / offline demo. Magic emails: `unconfirmed@…` (not confirmed), `offline@…` (no network),
/// `pending@…` on sign-up (confirmation email). Password `password123` signs in.
final class MockAuth: AuthService {
    func make(_ email: String) -> AuthSession {
        AuthSession(accessToken: "mock", refreshToken: "mock", expiresAt: Date().timeIntervalSince1970 + 3600,
                    userID: "00000000-0000-0000-0000-000000000001", email: email)
    }
    private func check(_ email: String) throws {
        if email.hasPrefix("offline@") { throw AuthError.network(URLError(.notConnectedToInternet)) }
    }
    func signUp(email: String, password: String) async throws -> AuthSession? {
        try check(email)
        guard password.count >= 6 else { throw AuthError(.weakPassword, "Password should be at least 6 characters.") }
        return email.hasPrefix("pending@") ? nil : make(email)
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        try check(email)
        if email.hasPrefix("unconfirmed@") { throw AuthError.from(status: 400, json: ["error_code": "email_not_confirmed"]) }
        guard password == "password123" else { throw AuthError.from(status: 400, json: ["error_code": "invalid_credentials"]) }
        return make(email)
    }
    func sendMagicLink(email: String) async throws { try check(email) }
    func resendConfirmation(email: String) async throws { try check(email) }
    func recoverPassword(email: String) async throws { try check(email) }
    func updatePassword(_ session: AuthSession, to password: String) async throws {
        guard password.count >= 6 else { throw AuthError(.weakPassword, "Password should be at least 6 characters.") }
    }
    func refresh(_ session: AuthSession) async throws -> AuthSession { session }
    func session(fromCallback url: URL) async throws -> AuthCallback? {
        SupabaseAuth.params(url)["type"] == "recovery" ? .recovery(make("reset@example.com")) : .signedIn(make("magic@example.com"))
    }
    func signOut(_ session: AuthSession) async {}
    func deleteAccount(_ session: AuthSession) async throws {}
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
