import XCTest
@testable import Ate

final class GenerationStageHistoryTests: XCTestCase {
    private let stages: [DiagnosticEvent.Kind] = [
        .generationAttemptStarted, .generationFetchStarted, .generationFetchReturned,
        .generationPromptBuilt, .generationModelStarted, .generationFirstSnapshot,
        .generationModelReturned, .generationRepairStarted, .generationRepairReturned,
        .generationTimedOut, .generationAttemptReturned, .generationAttemptFailed
    ]

    func testStageCategoriesAndTimestampsPersistWithoutAddingContentFields() throws {
        let name = "GenerationStageHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = DiagnosticHistory(defaults: defaults, key: "stages")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for (index, stage) in stages.enumerated() {
            history.recordLocal(stage, at: start.addingTimeInterval(Double(index)))
            let encoded = try JSONEncoder().encode(DiagnosticEvent(kind: stage))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(Set(object.keys), Set(["id", "kind", "timestamp"]))
            XCTAssertEqual(try JSONDecoder().decode(DiagnosticEvent.self, from: encoded).kind, stage)
            XCTAssertFalse(DiagnosticEvent(kind: stage).title.isEmpty)
        }
        let restored = DiagnosticHistory(defaults: defaults, key: "stages")
        XCTAssertEqual(restored.entries.map(\.kind), stages)
        XCTAssertEqual(restored.entries.last?.timestamp.timeIntervalSince(start), 11)
        let report = restored.exportReport(appVersion: "Test", buildNumber: "454")
        XCTAssertTrue(report.contains("generationFirstSnapshot"))
        XCTAssertTrue(report.contains("generationRepairStarted"))
        XCTAssertTrue(report.contains("generationTimedOut"))
        XCTAssertFalse(report.contains("lancewood"))
        XCTAssertFalse(report.contains("trifle"))
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(defaults.data(forKey: "stages"))
    }

    func testLocalStageWritesKeepTheExistingRollingBound() throws {
        let name = "GenerationStageHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = DiagnosticHistory(defaults: defaults, key: "stages")
        for _ in 0..<(DiagnosticHistory.maximumEntries + 3) { history.recordLocal(.generationModelStarted) }
        XCTAssertEqual(history.entries.count, DiagnosticHistory.maximumEntries)
        XCTAssertTrue(history.entries.allSatisfy { $0.kind == .generationModelStarted })
    }
}
