import XCTest
@testable import Ate

/// Source-level gates for the always-visible "Suggest a new recipe" entry in Add
/// recipe (#641). Pure presentation logic: no model, backend, demo or remote call
/// is possible here, and no state fabricates saved-recipe context.
final class RecipeDiscoveryReadinessTests: XCTestCase {
    func testReadyRequiresPrivateModeOffOnDeviceModelAndASavedRecipe() {
        let ready = RecipeDiscoveryReadiness(privateMode: false, onDeviceBackend: true,
            modelAvailable: true, modelUnavailableReason: "Apple Intelligence ready", savedRecipes: 1)
        XCTAssertEqual(ready, .ready)
        XCTAssertTrue(ready.canGenerate)
        XCTAssertNil(ready.explanation)
    }

    func testPrivateModeBlocksFirstEvenWhenModelAndLibraryWouldPass() {
        let blocked = RecipeDiscoveryReadiness(privateMode: true, onDeviceBackend: true,
            modelAvailable: true, modelUnavailableReason: "Apple Intelligence ready", savedRecipes: 3)
        XCTAssertEqual(blocked, .privateMode)
        XCTAssertFalse(blocked.canGenerate)
        XCTAssertEqual(blocked.explanation, "Private mode is on. Turn it off in Settings to use AI suggestions.")
    }

    func testUnavailableModelBlocksWithTheExactReadinessReasonPreserved() {
        for reason in ["Turn on Apple Intelligence in Settings", "Apple Intelligence is still downloading",
                       "This iPhone doesn't support Apple Intelligence", "Needs iOS 26"] {
            let blocked = RecipeDiscoveryReadiness(privateMode: false, onDeviceBackend: true,
                modelAvailable: false, modelUnavailableReason: reason, savedRecipes: 2)
            XCTAssertEqual(blocked, .modelUnavailable(reason: reason))
            XCTAssertFalse(blocked.canGenerate)
            XCTAssertEqual(blocked.explanation,
                "Suggestions need on-device Apple Intelligence: \(reason). No suggestion can start yet.")
        }
    }

    func testNonOnDeviceBackendBlocksWithoutClaimingAModelState() {
        let blocked = RecipeDiscoveryReadiness(privateMode: false, onDeviceBackend: false,
            modelAvailable: true, modelUnavailableReason: "Apple Intelligence ready", savedRecipes: 2)
        XCTAssertEqual(blocked, .nonOnDeviceBackend)
        XCTAssertFalse(blocked.canGenerate)
        XCTAssertEqual(blocked.explanation,
            "Suggestions need on-device Apple Intelligence, which is not the active backend. No suggestion can start yet.")
    }

    func testEmptyLibraryBlocksOnlyAfterBackendAndModelPass() {
        let blocked = RecipeDiscoveryReadiness(privateMode: false, onDeviceBackend: true,
            modelAvailable: true, modelUnavailableReason: "Apple Intelligence ready", savedRecipes: 0)
        XCTAssertEqual(blocked, .emptyLibrary)
        XCTAssertFalse(blocked.canGenerate)
        XCTAssertEqual(blocked.explanation, "Save a recipe first so Ate can suggest something based on your tastes.")
    }

    func testEntryExplanationsMatchTheSessionMessagesForTheSameStates() {
        // RecipeDiscovery.context and RecipeDiscoverySession show these exact strings
        // for the same states; the entry must never tell a different story.
        XCTAssertEqual(RecipeDiscoveryReadiness.privateMode.explanation,
            "Private mode is on. Turn it off in Settings to use AI suggestions.")
        XCTAssertEqual(RecipeDiscoveryReadiness.emptyLibrary.explanation,
            "Save a recipe first so Ate can suggest something based on your tastes.")
    }
}
