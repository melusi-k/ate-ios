import XCTest
@testable import Ate

/// Native UNRUN. Exact injected transport fixtures, no live backend requests.
final class AccountRPCErrorSemanticsTests: XCTestCase {
    private let session = AuthSession(accessToken: "fixture", refreshToken: "fixture",
        expiresAt: 4_000_000_000, userID: "owner", email: "fixture@example.test")

    func test40140342501AndPT409StayDistinctAcrossAllRPCOperations() async throws {
        let fixtures: [(Int, String, ResetRPCError)] = [
            (401, #"{"code":"PGRST301"}"#, .unauthorized),
            (403, #"{"code":"42501"}"#, .permissionDenied),
            (400, #"{"code":"42501"}"#, .permissionDenied),
            (409, #"{"code":"PT409"}"#, .staleGeneration),
            (404, #"{"code":"PGRST202"}"#, .contractMissing)
        ]
        for operation in ["snapshot", "put", "clear"] {
            for (status, body, expected) in fixtures {
                var requests: [URLRequest] = []
                let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
                    requests.append(request)
                    return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!)
                })
                do {
                    if operation == "snapshot" { _ = try await rpc.snapshot(session: session) }
                    else if operation == "put" {
                        try await rpc.putRecipe(session: session, callerGeneration: 3, kind: "shopping", id: "s",
                            data: nil, updatedAt: 1, deleted: true)
                    } else { _ = try await rpc.clearAccount(session: session, requestID: UUID(), expectedGeneration: 3) }
                    XCTFail("API error treated as success")
                } catch let error as ResetRPCError { XCTAssertEqual(error, expected) }
                XCTAssertEqual(requests.count, 1, "no auth retry or new reset request hidden in transport")
                XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            }
        }
        XCTAssertFalse(ResetRPCError.permissionDenied.localizedDescription.lowercased().contains("sign in"))
        XCTAssertFalse(ResetRPCError.permissionDenied.localizedDescription.lowercased().contains("expired"))
    }
}
