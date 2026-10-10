import Foundation

/// Shared HTTP plumbing for Supabase calls.
/// - Dedicated session (not `URLSession.shared`) so stale pooled connections from other work aren't reused.
/// - HTTP/3 is not assumed: Supabase advertises `alt-svc: h3`, and QUIC connections that iOS suspended in the
///   background often come back dead, which surfaces as NSURLErrorNetworkConnectionLost (-1005).
/// - One automatic retry for -1005 (the request never reached a usable connection, so it is safe to resend).
enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 40
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 4
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var r = request
        r.assumesHTTP3Capable = false
        do {
            return try await session.data(for: r)
        } catch let e as URLError where e.code == .networkConnectionLost {
            try? await Task.sleep(nanoseconds: 400_000_000)
            return try await session.data(for: r)
        }
    }

    /// Adds `apikey`, and `Authorization` only when it is a real JWT. `sb_publishable_…` keys are not JWTs and
    /// must never be sent as a Bearer token (the gateway accepts it for some routes today, but it isn't valid).
    static func authorize(_ r: inout URLRequest, key: String, bearer: String? = nil) {
        r.setValue(key, forHTTPHeaderField: "apikey")
        let token = bearer ?? (key.hasPrefix("sb_") ? nil : key)
        if let token, !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    static func friendly(_ error: Error) -> String {
        if let e = error as? LocalizedError, !(error is URLError), let d = e.errorDescription { return d }
        guard let u = error as? URLError else { return error.localizedDescription }
        switch u.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return "You're offline. Check your connection and try again."
        case .timedOut: return "ate's server took too long to answer. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
            return "Couldn't reach ate's server. Check your connection and try again."
        default: return "Network problem (\(u.code.rawValue)). Try again."
        }
    }
}
