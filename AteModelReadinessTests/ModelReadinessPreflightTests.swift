import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI-ready lane preflight + real-inference smoke (docs/CI.md, decision 2026-11-01).
///
/// This target runs ONLY in the AI-ready real-model lane (ai-model-lane.yml).
/// It is never part of the standard lane: ordinary build/unit/UI lanes select
/// their tests with -only-testing filters that exclude this target.
///
/// Policy per the CI architecture decision:
/// - Require SystemLanguageModel.default.availability == .available.
/// - Then prove inference with a small real generation on THIS device.
/// - Fail explicitly on ineligibility, disabled Apple Intelligence, or model
///   not ready. Never substitute a mock, never skip to green.
/// - The readiness check and the smoke run in the same lane job on the same
///   simulator as the lane's real-model tests: a pass here qualifies this
///   machine only.
///
/// Failure strings carry a structured prefix so the lane can annotate the
/// exact failing condition:
/// - AI-LANE ELIGIBILITY: device cannot run Apple Intelligence or it is disabled
/// - AI-LANE READINESS: model assets not ready on this machine
/// - AI-LANE INFERENCE: a real generation request failed or timed out
final class ModelReadinessPreflightTests: XCTestCase {

    func testModelAvailabilityPreflight() {
        guard #available(iOS 26.0, *) else {
            XCTFail("AI-LANE ELIGIBILITY: runtime below iOS 26 - Foundation Models requires iOS 26 + Apple Intelligence")
            return
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            // Eligible and enabled; the smoke test proves real inference on this device.
            break
        case .unavailable(.deviceNotEligible):
            XCTFail("AI-LANE ELIGIBILITY: deviceNotEligible - this machine cannot run Apple Intelligence; move the lane to an eligible runner, do not weaken this test")
        case .unavailable(.appleIntelligenceNotEnabled):
            XCTFail("AI-LANE ELIGIBILITY: appleIntelligenceNotEnabled - enable Apple Intelligence on this machine, do not weaken this test")
        case .unavailable(.modelNotReady):
            XCTFail("AI-LANE READINESS: modelNotReady - model assets are not downloaded/ready on this machine")
        case .unavailable(let reason):
            XCTFail("AI-LANE ELIGIBILITY: unavailable(\(String(describing: reason)))")
        }
        #else
        XCTFail("AI-LANE ELIGIBILITY: FoundationModels framework is not importable in this build environment")
        #endif
    }

    func testRealInferenceSmoke() async throws {
        guard #available(iOS 26.0, *) else {
            XCTFail("AI-LANE ELIGIBILITY: runtime below iOS 26 - Foundation Models requires iOS 26 + Apple Intelligence")
            return
        }
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            XCTFail("AI-LANE ELIGIBILITY: smoke executed without .available on this device - failing per policy (no mock substitution, no skip)")
            return
        }
        let session = LanguageModelSession(instructions: "You are a CI smoke probe. Answer briefly.")
        do {
            let response = try await session.respond(to: "What is 2 + 2? Reply with the number only.")
            XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "AI-LANE INFERENCE: generation returned empty content")
        } catch {
            XCTFail("AI-LANE INFERENCE: real generation failed or timed out on this device: \(error)")
        }
        #else
        XCTFail("AI-LANE ELIGIBILITY: FoundationModels framework is not importable in this build environment")
        #endif
    }
}
