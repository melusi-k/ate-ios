import XCTest
import Observation
@testable import Ate

@MainActor
final class CookTimerObservationTests: XCTestCase {
    func testClockTickDoesNotInvalidateCookStructureReads() {
        let clock = TimerCenter()
        let invalidated = ChangeFlag()
        withObservationTracking {
            _ = clock.timers
            _ = clock.timer("synthetic-recipe", 0)
        } onChange: {
            invalidated.mark()
        }
        clock.tick(.distantPast)
        XCTAssertFalse(invalidated.value, "No active timer expires or changes: a redraw tick must not invalidate Cook structure")
    }

    func testCountdownClockReadIsInvalidatedByTick() {
        let clock = TimerCenter()
        let invalidated = ChangeFlag()
        withObservationTracking {
            _ = clock.now
        } onChange: {
            invalidated.mark()
        }
        clock.tick(.distantPast)
        XCTAssertTrue(invalidated.value, "Countdown leaf still receives wall-clock redraws")
    }
}


// Observation's callback is Sendable. Keep the test signal synchronized rather
// than mutating an unsafely captured local variable.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func mark() { lock.lock(); defer { lock.unlock() }; changed = true }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return changed }
}
