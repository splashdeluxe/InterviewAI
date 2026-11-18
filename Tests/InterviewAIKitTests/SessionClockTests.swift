import XCTest
@testable import InterviewAIKit

final class SessionClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testElapsedWithoutPause() {
        let clock = SessionClock(startedAt: start)
        XCTAssertEqual(clock.elapsed(at: at(90)), 90, accuracy: 0.001)
        XCTAssertFalse(clock.isPaused)
    }

    func testElapsedFreezesDuringPause() {
        var clock = SessionClock(startedAt: start)
        clock.beginPause(at: at(60))
        XCTAssertTrue(clock.isPaused)
        XCTAssertEqual(clock.elapsed(at: at(60)), 60, accuracy: 0.001)
        XCTAssertEqual(clock.elapsed(at: at(600)), 60, accuracy: 0.001)
    }

    func testElapsedAfterResumeExcludesThePause() {
        var clock = SessionClock(startedAt: start)
        clock.beginPause(at: at(60))
        clock.endPause(at: at(600))
        XCTAssertFalse(clock.isPaused)
        XCTAssertEqual(clock.elapsed(at: at(660)), 120, accuracy: 0.001)
    }

    func testTwoPausesAccumulate() {
        var clock = SessionClock(startedAt: start)
        clock.beginPause(at: at(10))
        clock.endPause(at: at(20))
        clock.beginPause(at: at(50))
        clock.endPause(at: at(90))
        XCTAssertEqual(clock.elapsed(at: at(100)), 50, accuracy: 0.001)
    }

    func testDoubleBeginAndEndAreNoOps() {
        var clock = SessionClock(startedAt: start)
        clock.beginPause(at: at(10))
        clock.beginPause(at: at(20))
        clock.endPause(at: at(30))
        clock.endPause(at: at(40))
        XCTAssertEqual(clock.elapsed(at: at(40)), 20, accuracy: 0.001)
    }

    func testElapsedNeverRunsBackwards() {
        let clock = SessionClock(startedAt: start)
        XCTAssertEqual(clock.elapsed(at: at(-5)), 0, accuracy: 0.001)
    }
}
