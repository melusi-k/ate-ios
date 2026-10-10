import XCTest
@testable import Ate

final class VoiceCommandTests: XCTestCase {
    func testBasicCommands() {
        XCTAssertEqual(VoiceCommands.parse("next"), .next)
        XCTAssertEqual(VoiceCommands.parse("Go back"), .back)
        XCTAssertEqual(VoiceCommands.parse("okay start the timer"), .startTimer)
        XCTAssertEqual(VoiceCommands.parse("can you repeat"), .repeatStep)
        XCTAssertEqual(VoiceCommands.parse("pause timer"), .pauseTimer)
        XCTAssertNil(VoiceCommands.parse("the onions are browning nicely"))
    }
    func testWholeWordsOnly() {
        XCTAssertNil(VoiceCommands.parse("backyard"))
        XCTAssertNil(VoiceCommands.parse("nextdoor"))
    }
    func testNewestCommandWinsAndConsumedTailIgnored() {
        XCTAssertEqual(VoiceCommands.parse("next and then back"), .back)
        let t = "next"
        XCTAssertNil(VoiceCommands.parse(t, after: t.count))
        XCTAssertEqual(VoiceCommands.parse("next repeat", after: 4), .repeatStep)
    }
    func testTimerPhraseBeatsBareWords() {
        // "stop timer" is pause, not exit/stop cooking
        XCTAssertEqual(VoiceCommands.parse("stop timer"), .pauseTimer)
        XCTAssertEqual(VoiceCommands.parse("stop cooking"), .exit)
    }
}
