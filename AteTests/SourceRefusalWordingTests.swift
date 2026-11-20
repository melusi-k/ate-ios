import XCTest
@testable import Ate

@MainActor
final class SourceRefusalWordingTests: XCTestCase {
    func testBareDishAndNonFoodKeepRefusalWithRelevantWordingAndNoModelCall() async {
        let expected = "That text doesn't look like a recipe source. Paste a recipe with ingredients or written cooking instructions, use a recipe link or screenshot, or enter it manually. Nothing was generated."
        XCTAssertEqual(AddPromptSourceImport.missingSourceMessage, expected)
        for text in ["Beef stroganoff", "The quarterly report is due Friday. Please send the updated figures to the team before the meeting."] {
            var availabilityChecks = 0, modelCalls = 0
            let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: {
                availabilityChecks += 1
                return true
            }, modelWillGenerate: { modelCalls += 1 })
            XCTAssertFalse(SourceDraftImport.hasSource(text))
            do {
                _ = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: text), using: backend)
                XCTFail("Neither a bare dish name nor non-food text can become a recipe source")
            } catch {
                XCTAssertEqual(error.localizedDescription, expected)
            }
            XCTAssertEqual(availabilityChecks, 0)
            XCTAssertEqual(modelCalls, 0)
        }
    }
}
