import XCTest
@testable import Ate

final class AccountGenerationPolicyTests: XCTestCase {
    private typealias P = AccountGenerationPolicy
    func testLegacyNonemptyStateIsNeverStampedWithFreshSnapshotGeneration() {
        XCTAssertEqual(P.decide(receipt: nil, ownerID: "a", remoteGeneration: 7,
                                allPersonalLocalStateVerifiedEmpty: false), .legacyLocalStateNeedsReconciliation)
    }
    func testVerifiedEmptyFirstSyncMayAdoptGeneration() {
        XCTAssertEqual(P.decide(receipt: nil, ownerID: "a", remoteGeneration: 7,
                                allPersonalLocalStateVerifiedEmpty: true), .adoptForVerifiedEmptyLocalState)
    }
    func testRemoteResetRequiresLocalEraseEvenWhenRecipeListIsEmpty() {
        XCTAssertEqual(P.decide(receipt: .init(ownerID: "a", generation: 2), ownerID: "a", remoteGeneration: 3,
                                allPersonalLocalStateVerifiedEmpty: true), .remoteResetNeedsLocalErase)
    }
    func testSameGenerationCanMerge() {
        XCTAssertEqual(P.decide(receipt: .init(ownerID: "a", generation: 2), ownerID: "a", remoteGeneration: 2,
                                allPersonalLocalStateVerifiedEmpty: false), .mergeCurrentGeneration)
    }
    func testOwnerChangeCannotReuseReceipt() {
        XCTAssertEqual(P.decide(receipt: .init(ownerID: "a", generation: 2), ownerID: "b", remoteGeneration: 2,
                                allPersonalLocalStateVerifiedEmpty: true), .ownerChangeNeedsReconciliation)
    }
    func testNegativeRegressedOrEmptyOwnerRefused() {
        for (owner, local, remote) in [("a", Int64(2), Int64(1)), ("a", -1, 0), ("a", 0, -1), ("", 0, 0)] {
            XCTAssertEqual(P.decide(receipt: .init(ownerID: owner, generation: local), ownerID: owner,
                                    remoteGeneration: remote, allPersonalLocalStateVerifiedEmpty: true),
                           .refuseInvalidOrRegressedGeneration)
        }
    }
}
