import Foundation

/// Typed client for the candidate account-data reset RPC contract
/// (docs/implementation/clear-all/account_data_reset.sql). UNWIRED: no call sites yet;
/// central binds this into sync/reset composition and the rollout that ships
/// put_user_recipe clients before the direct-write revokes deploy.
///
/// Transport is INJECTED (`perform`) so fault fixtures can drive every failure mode
/// without Net; production uses Net.data. Every function maps the PostgREST error body
/// (`code` = the PL/pgSQL errcode) so no caller has to guess. For `clearAccount`, a lost
/// response is NEVER treated as failure-or-success: the server may have committed, so
/// callers get `.outcomeUnverified` and recover with the same request UUID (idempotent).
struct AccountSnapshot: Equatable {
    let generation: Int64
    let rows: [SyncRecord]
}

enum ResetRPCError: LocalizedError, Equatable {
    /// PT409: permanent caller generation conflict, not a retryable serialization error.
    /// The caller generation is not the account's current generation. Discard stale
    /// local data and fetch a fresh snapshot; for a reset retry, verify status first.
    case staleGeneration
    /// 401: credentials are not accepted. Auth lifecycle may refresh or expire.
    case unauthorized
    /// 403 / 42501: permission denial, not proof that the session expired.
    case permissionDenied
    /// 22023 or a client-side contract violation: a programming error, not a user state.
    case invalidRequest(String)
    /// 404 / PGRST202: the RPC contract is not deployed on this backend.
    case contractMissing
    /// Response lost or structurally untrustworthy: the server MAY have committed.
    /// Never retried with a fresh request UUID.
    case outcomeUnverified(String)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .staleGeneration: return "Account data was cleared elsewhere; fetch a fresh snapshot."
        case .unauthorized: return "Sign in again to continue."
        case .permissionDenied: return "The server denied permission. Your local data has not been cleared."
        case .invalidRequest(let d): return "Invalid reset request: \(d)"
        case .contractMissing: return "This build needs an app update before account data can be cleared."
        case .outcomeUnverified(let d): return "The result couldn't be verified: \(d)"
        case .http(let code, let d): return "Server error \(code): \(d ?? "")"
        }
    }
}

final class AccountDataResetService {
    typealias Perform = (URLRequest) async throws -> (Data, URLResponse)

    let baseURL: URL
    let key: String
    private let perform: Perform

    init(baseURL: URL, key: String, perform: @escaping Perform = { try await Net.data(for: $0) }) {
        self.baseURL = baseURL; self.key = key; self.perform = perform
    }

    private func rpc(_ name: String, session: AuthSession, body: [String: Any]) throws -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        r.httpMethod = "POST"
        r.timeoutInterval = 20
        Net.authorize(&r, key: key, bearer: session.accessToken)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    private func check(_ data: Data, _ resp: URLResponse) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code) { return }
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let pgcode = j?["code"] as? String ?? ""
        let message = j?["message"] as? String
        if code == 404 || pgcode == "PGRST202" { throw ResetRPCError.contractMissing }
        if code == 401 { throw ResetRPCError.unauthorized }
        if code == 403 || pgcode == "42501" { throw ResetRPCError.permissionDenied }
        if pgcode == "PT409" { throw ResetRPCError.staleGeneration }
        if pgcode == "22023" { throw ResetRPCError.invalidRequest(message ?? "") }
        if code >= 500 { throw ResetRPCError.outcomeUnverified(message ?? "HTTP \(code)") }
        throw ResetRPCError.http(code, message)
    }

    /// STRICT boundary row. The legacy SyncRecord decoder REPAIRS malformed fields
    /// (updated_at -> 0 via Double/String fallback, deleted -> false), which would
    /// fabricate account state at the reset boundary. This DTO accepts exact types
    /// only; conversion to SyncRecord happens after validation, and the legacy
    /// decoder is left unchanged for its existing callers.
    private struct StrictSnapshotRow: Decodable {
        let user_id: String
        let kind: String
        let id: String
        let data: AnyJSON?
        let updated_at: Int64
        let deleted: Bool

        enum CodingKeys: String, CodingKey { case user_id, kind, id, data, updated_at, deleted }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            user_id = try c.decode(String.self, forKey: .user_id)
            kind = try c.decode(String.self, forKey: .kind)
            id = try c.decode(String.self, forKey: .id)
            // The contract is full-shape: the data key must be present (null allowed).
            // decodeIfPresent alone would accept a missing key as a malformed row.
            guard c.contains(.data) else {
                throw DecodingError.keyNotFound(CodingKeys.data,
                    .init(codingPath: decoder.codingPath, debugDescription: "missing data key"))
            }
            data = try c.decodeIfPresent(AnyJSON.self, forKey: .data)
            updated_at = try c.decode(Int64.self, forKey: .updated_at)   // no Double/String repair
            deleted = try c.decode(Bool.self, forKey: .deleted)          // no default-to-false repair
        }

        var valid: Bool {
            !user_id.isEmpty && !kind.isEmpty && !id.isEmpty && updated_at >= 0
        }

        var record: SyncRecord {
            SyncRecord(user_id: user_id, kind: kind, id: id, data: data,
                       updated_at: updated_at, deleted: deleted)
        }
    }

    private struct SnapshotDTO: Decodable {
        let generation: Int64
        let rows: [StrictSnapshotRow]
    }

    /// Owner-scoped consistent snapshot: one RPC, generation and rows from the same lock.
    /// STRICT: JSONDecoder rejects bool/fractional generations and malformed rows; any
    /// structural doubt is `.outcomeUnverified`, never a fabricated empty account.
    func snapshot(session: AuthSession) async throws -> AccountSnapshot {
        let r = try rpc("account_data_snapshot", session: session, body: [:])
        let data: Data, resp: URLResponse
        do { (data, resp) = try await perform(r) }
        catch let e as ResetRPCError { throw e }
        catch { throw ResetRPCError.outcomeUnverified(Net.friendly(error)) }
        try check(data, resp)
        guard let dto = try? JSONDecoder().decode(SnapshotDTO.self, from: data),
              dto.generation >= 0,
              dto.rows.allSatisfy(\.valid) else {
            throw ResetRPCError.outcomeUnverified("unreadable snapshot")
        }
        return AccountSnapshot(generation: dto.generation, rows: dto.rows.map(\.record))
    }

    /// The ONLY client write path once the direct-write revokes deploy. The caller's
    /// generation is an explicit argument; a stale caller is rejected server-side.
    /// Tombstone: pass deleted=true (data may be nil). `data` MUST be valid JSON when
    /// present - an unparseable payload is refused BEFORE sending, never rewritten to null.
    func putRecipe(session: AuthSession, callerGeneration: Int64, kind: String, id: String,
                   data: Data?, updatedAt: Int64, deleted: Bool) async throws {
        let dataObject: Any
        if let data {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
                throw ResetRPCError.invalidRequest("payload for \(kind)/\(id) is not valid JSON; not sent")
            }
            dataObject = parsed
        } else {
            dataObject = NSNull()
        }
        let r = try rpc("put_user_recipe", session: session, body: [
            "p_caller_generation": callerGeneration, "p_kind": kind, "p_id": id,
            "p_data": dataObject, "p_updated_at": updatedAt, "p_deleted": deleted,
        ])
        let responseData: Data, resp: URLResponse
        do { (responseData, resp) = try await perform(r) }
        catch let e as ResetRPCError { throw e }
        catch { throw ResetRPCError.outcomeUnverified(Net.friendly(error)) }
        try check(responseData, resp)
    }

    /// Idempotent while requestID is the account's most recent reset request. Returns the
    /// NEW generation; the caller persists it as the cloud receipt before allowing writes.
    /// The receipt is validated: it must be exactly expectedGeneration + 1 (an idempotent
    /// replay of OUR committed request returns the same value), anything else means the
    /// account state is not what was requested and the outcome is unverified.
    func clearAccount(session: AuthSession, requestID: UUID, expectedGeneration: Int64) async throws -> Int64 {
        // Range guard BEFORE any request: expected+1 must not trap on Int64.max and a
        // negative expectation is a contract violation, never sent.
        guard expectedGeneration >= 0, expectedGeneration < Int64.max else {
            throw ResetRPCError.invalidRequest("expectedGeneration \(expectedGeneration) out of range")
        }
        let r = try rpc("clear_account_data", session: session, body: [
            "request_id": requestID.uuidString.lowercased(), "expected_generation": expectedGeneration,
        ])
        let data: Data, resp: URLResponse
        do { (data, resp) = try await perform(r) }
        catch let e as ResetRPCError { throw e }
        catch { throw ResetRPCError.outcomeUnverified(Net.friendly(error)) }
        try check(data, resp)
        guard let generation = try? JSONDecoder().decode(Int64.self, from: data), generation >= 0 else {
            throw ResetRPCError.outcomeUnverified("missing generation receipt")
        }
        guard generation == expectedGeneration + 1 else {
            throw ResetRPCError.outcomeUnverified(
                "receipt generation \(generation) does not follow expected \(expectedGeneration)")
        }
        return generation
    }
}
