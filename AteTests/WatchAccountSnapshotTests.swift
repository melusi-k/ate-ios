import XCTest
@testable import Ate

final class WatchAccountSnapshotTests: XCTestCase {
    func testStrictOwnerGenerationAndFullRowShapeBeforeAuthorizingWatchWrite() throws {
        let valid = #"{"generation":3,"rows":[{"user_id":"owner","kind":"shopping","id":"item","data":{"name":"Eggs"},"updated_at":12,"deleted":false}]}"#
        let snapshot = try WatchAccountSnapshot.decode(Data(valid.utf8), ownerID: "owner")
        XCTAssertEqual(snapshot.generation, 3)
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertThrowsError(try WatchAccountSnapshot.decode(Data(valid.utf8), ownerID: "foreign"))
        for bad in [valid.replacingOccurrences(of: "\"generation\":3", with: "\"generation\":true"),
                    valid.replacingOccurrences(of: "\"generation\":3", with: "\"generation\":-1"),
                    valid.replacingOccurrences(of: "\"updated_at\":12", with: "\"updated_at\":1.5"),
                    valid.replacingOccurrences(of: ",\"deleted\":false", with: ""),
                    valid.replacingOccurrences(of: "\"data\":{\"name\":\"Eggs\"},", with: "")] {
            XCTAssertThrowsError(try WatchAccountSnapshot.decode(Data(bad.utf8), ownerID: "owner"))
        }
    }
}
