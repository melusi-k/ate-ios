import XCTest
@testable import Ate

/// Native UNRUN. Raw inventory is injected; real gate/receipt/preservation files.
@MainActor
final class RecipeShoppingLegacyAdmissionTests: XCTestCase {
    private var current: AuthSession? = .init(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
        userID: "owner", email: "fixture@example.test")
    private enum Injected: Error { case failure }
    private func directory() throws -> URL {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        return requested.resolvingSymlinksInPath().standardizedFileURL
    }
    private func raw(owner: String? = "owner") throws -> RecipeShoppingRawInventory {
        let card = RecipeCard(id: "r", title: "Keep exact"), item = ShoppingItem(id: "s", name: "Keep", quantity: 1, unit: "g")
        let encoder = JSONEncoder()
        var meta = RecipeShoppingSyncStage.Metadata(); meta.userID = owner
        meta.recipeStamps = ["r": 1]; meta.shopStamps = ["s": 2]
        meta.recipeTombs = ["r-deleted": 3]; meta.shopTombs = ["s-deleted": 4]
        return RecipeShoppingRawInventory(image: .init(recipes: [.init(id: "r", createdAt: card.createdAt, position: 0,
            json: try encoder.encode(card))], shopping: [.init(id: "s", position: 0, json: try encoder.encode(item))]),
            metadataBytes: try encoder.encode(meta))
    }
    private func make(_ dir: URL, raw: @escaping () throws -> RecipeShoppingRawInventory,
                      transport: @escaping AccountDataResetService.Perform) throws -> RecipeShoppingLegacyAdmission {
        let gate = try AccountWriterGate(directory: dir, resetControlExists: { false })
        let lease = try gate.captureWriter()
        let preservation = dir.appendingPathComponent("preservation")
        try FileManager.default.createDirectory(at: preservation, withIntermediateDirectories: false)
        return RecipeShoppingLegacyAdmission(gate: gate, lease: lease,
            receiptStore: try AccountGenerationReceiptStore(directory: dir),
            rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: transport),
            preservationDirectory: preservation, currentSession: { self.current }, captureRaw: raw)
    }
    private func response(_ generation: Int) -> (Data, URLResponse) {
        (Data("{\"generation\":\(generation),\"rows\":[]}".utf8), HTTPURLResponse(url: URL(string: "https://fixture.invalid")!,
            statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func testKnownOwnerGenerationZeroPreservesExactRawBytesAndTombsBeforeReceipt() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try raw()
        var paths: [String] = []
        let admission = try make(dir, raw: { original }, transport: { request in
            paths.append(request.url!.lastPathComponent)
            XCTAssertNil(try AccountGenerationReceiptStore(directory: dir).read())
            return self.response(0)
        })
        let receipt = try await admission.adoptKnownLegacyOwner(session: current!)
        XCTAssertEqual(receipt, .init(ownerID: "owner", generation: 0))
        XCTAssertEqual(paths, ["account_data_snapshot"])
        let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("preservation/legacy-recipe-shopping-v1.json"))) as! [String: Any]
        let encoded = try XCTUnwrap(envelope["payload"] as? String)
        let record = try JSONDecoder().decode(RecipeShoppingLegacyAdmission.Preservation.self, from: XCTUnwrap(Data(base64Encoded: encoded)))
        XCTAssertEqual(record.image, original.image); XCTAssertEqual(record.metadata, original.metadataBytes)
        XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read(), receipt)
    }
    func testUnknownForeignOrAdvancedGenerationNeverStampsOrDeletes() async throws {
        for owner in [String?.none, .some("foreign"), .some("owner")] {
            let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
            let original = try raw(owner: owner); var calls = 0
            let admission = try make(dir, raw: { original }, transport: { _ in calls += 1; return self.response(1) })
            do { _ = try await admission.adoptKnownLegacyOwner(session: current!); XCTFail("unsafe adoption") }
            catch { }
            XCTAssertNil(try AccountGenerationReceiptStore(directory: dir).read())
            XCTAssertEqual(calls, owner == "owner" ? 1 : 0)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("preservation").path).isEmpty)
            XCTAssertNotNil(original.metadataBytes)
        }
    }
    func testChangedRawInventoryAfterAwaitRefusesPreservationAndStamp() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try raw(); var changed = false
        let admission = try make(dir, raw: {
            if changed { return RecipeShoppingRawInventory(image: .init(recipes: [], shopping: []), metadataBytes: original.metadataBytes) }
            return original
        }, transport: { _ in changed = true; return self.response(0) })
        do { _ = try await admission.adoptKnownLegacyOwner(session: current!); XCTFail("changed raw adopted") }
        catch RecipeShoppingLegacyAdmission.Refusal.changedInventory {} catch { XCTFail("unexpected \(error)") }
        XCTAssertNil(try AccountGenerationReceiptStore(directory: dir).read())
    }
    func testCorruptPreservationTempBlocksReceiptWithoutReplacingEvidence() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try raw()
        let admission = try make(dir, raw: { original }, transport: { _ in self.response(0) })
        let temp = dir.appendingPathComponent("preservation/legacy-recipe-shopping-v1.json.tmp")
        let evidence = Data("partial".utf8); try evidence.write(to: temp)
        do { _ = try await admission.adoptKnownLegacyOwner(session: current!); XCTFail("corrupt evidence replaced") }
        catch RecipeShoppingLegacyAdmission.Refusal.preservationUnverified {} catch { XCTFail("unexpected \(error)") }
        XCTAssertNil(try AccountGenerationReceiptStore(directory: dir).read())
        XCTAssertEqual(try Data(contentsOf: temp), evidence)
    }
    func testSessionChangeDuringSnapshotRefusesReceiptAndPreservation() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try raw(); let session = current!
        let admission = try make(dir, raw: { original }, transport: { _ in
            self.current = nil
            return self.response(0)
        })
        do { _ = try await admission.adoptKnownLegacyOwner(session: session); XCTFail("changed session adopted") }
        catch RecipeShoppingLegacyAdmission.Refusal.ownerChanged {} catch { XCTFail("unexpected \(error)") }
        XCTAssertNil(try AccountGenerationReceiptStore(directory: dir).read())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("preservation").path).isEmpty)
    }
    func testExistingReceiptRefusesBeforeNetworkOrRawCapture() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try raw(); var calls = 0, captures = 0
        let receipt = AccountGenerationPolicy.Receipt(ownerID: "owner", generation: 0)
        try AccountGenerationReceiptStore(directory: dir).save(receipt)
        let admission = try make(dir, raw: { captures += 1; return original }, transport: { _ in
            calls += 1; return self.response(0)
        })
        do { _ = try await admission.adoptKnownLegacyOwner(session: current!); XCTFail("receipt overwritten") }
        catch RecipeShoppingLegacyAdmission.Refusal.existingReceipt {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(calls, 0); XCTAssertEqual(captures, 0)
        XCTAssertEqual(try AccountGenerationReceiptStore(directory: dir).read(), receipt)
    }

}
