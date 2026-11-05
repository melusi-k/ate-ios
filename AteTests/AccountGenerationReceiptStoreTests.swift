import XCTest
@testable import Ate

final class AccountGenerationReceiptStoreTests: XCTestCase {
    private func fixture(_ run: (AccountGenerationReceiptStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(try AccountGenerationReceiptStore(directory: directory), directory)
    }
    func testAbsentReceiptIsOnlyNilState() throws {
        try fixture { store, _ in XCTAssertNil(try store.read()) }
    }
    func testSaveThenFreshStoreExactReadback() throws {
        try fixture { store, directory in
            let receipt = AccountGenerationPolicy.Receipt(ownerID: "fixture-owner", generation: 9)
            try store.save(receipt)
            XCTAssertEqual(try AccountGenerationReceiptStore(directory: directory).read(), receipt)
        }
    }
    func testPresentCorruptBytesThrowInsteadOfUnknownLegacy() throws {
        try fixture { store, directory in
            try Data("broken".utf8).write(to: directory.appendingPathComponent("account-generation-v1.json"))
            XCTAssertThrowsError(try store.read())
        }
    }
    func testInvalidSemanticReceiptRefusedBeforeSave() throws {
        try fixture { store, _ in
            XCTAssertThrowsError(try store.save(.init(ownerID: "", generation: 1)))
            XCTAssertThrowsError(try store.save(.init(ownerID: "fixture", generation: -1)))
            XCTAssertNil(try store.read())
        }
    }
    func testSymlinkReceiptIsNotFollowed() throws {
        try fixture { store, directory in
            let target = directory.appendingPathComponent("not-control")
            try Data("preserve".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("account-generation-v1.json"),
                                                       withDestinationURL: target)
            XCTAssertThrowsError(try store.read())
            XCTAssertEqual(try Data(contentsOf: target), Data("preserve".utf8))
        }
    }
    func testDanglingSymlinkIsNotAbsentReceipt() throws {
        try fixture { store, directory in
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("account-generation-v1.json"),
                withDestinationURL: directory.appendingPathComponent("missing"))
            XCTAssertThrowsError(try store.read())
        }
    }

    func testMissingParentCannotMeanAbsentReceipt() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try AccountGenerationReceiptStore(directory: missing).read())
    }
    func testSymbolicParentCannotMeanAbsentReceipt() throws {
        try fixture { _, directory in
            let link = directory.appendingPathComponent("alias")
            let target = directory.appendingPathComponent("real")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            XCTAssertThrowsError(try AccountGenerationReceiptStore(directory: link).read())
        }
    }
    func testSaveRefusesExistingCorruptOrSymlinkReceipt() throws {
        try fixture { store, directory in
            let file = directory.appendingPathComponent("account-generation-v1.json")
            let broken = Data("broken".utf8)
            try broken.write(to: file)
            XCTAssertThrowsError(try store.save(.init(ownerID: "fixture", generation: 2)))
            XCTAssertEqual(try Data(contentsOf: file), broken)
            try FileManager.default.removeItem(at: file)
            let target = directory.appendingPathComponent("unrelated")
            try broken.write(to: target)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertThrowsError(try store.save(.init(ownerID: "fixture", generation: 2)))
            XCTAssertEqual(try Data(contentsOf: target), broken)
        }
    }

}
