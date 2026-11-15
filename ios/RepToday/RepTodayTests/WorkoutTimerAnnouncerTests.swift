import XCTest
@testable import RepToday

/// The workout timer's VoiceOver announcements: the halfway point, ten seconds and three seconds, each
/// once per countdown, only while VoiceOver runs and the countdown is live.
final class WorkoutTimerAnnouncerTests: XCTestCase {

    /// Ticks a countdown of `total` seconds down to zero twice a second, as the timer's ticker does, and
    /// returns what was announced.
    private func announcements(total: Int, isLive: Bool = true, voiceOver: Bool = true) -> [String] {
        var announcer = WorkoutTimerAnnouncer()
        var spoken: [String] = []
        for remaining in stride(from: total, through: 0, by: -1) {
            for _ in 0..<2 {
                if let sentence = announcer.tick(remaining: remaining, total: total, isLive: isLive, voiceOverRunning: voiceOver) {
                    spoken.append(sentence)
                }
            }
        }
        return spoken
    }

    func testAnnouncesHalfwayTenAndThreeOnceEach() {
        XCTAssertEqual(announcements(total: 50), ["Halfway, 25 seconds left", "10 seconds left", "3 seconds left"])
    }

    func testAShortCountdownSkipsTheMarksItStartsBelow() {
        XCTAssertEqual(announcements(total: 10), ["Halfway, 5 seconds left", "3 seconds left"])
        XCTAssertEqual(announcements(total: 3), ["Halfway, 1 second left"])
    }

    /// A countdown whose halfway point falls at or below three seconds (the 5-second switch-sides beat)
    /// never says "Halfway" after it has said "3 seconds left".
    func testAHalfwayAtOrBelowThreeSecondsGivesWayToTheThreeSecondMark() {
        XCTAssertEqual(announcements(total: 4), ["3 seconds left"])
        XCTAssertEqual(announcements(total: 5), ["3 seconds left"])
        XCTAssertEqual(announcements(total: 6), ["3 seconds left"])
        XCTAssertEqual(announcements(total: 8), ["Halfway, 4 seconds left", "3 seconds left"])
    }

    func testSilentWithoutVoiceOverOrWhilePaused() {
        XCTAssertEqual(announcements(total: 50, voiceOver: false), [])
        XCTAssertEqual(announcements(total: 50, isLive: false), [])
    }

    /// The next set's countdown, or "+ More time" pushing the time back up, announces its marks afresh.
    func testANewCountdownAnnouncesAgain() {
        var announcer = WorkoutTimerAnnouncer()
        XCTAssertEqual(announcer.tick(remaining: 3, total: 30, isLive: true, voiceOverRunning: true), "3 seconds left")
        XCTAssertNil(announcer.tick(remaining: 3, total: 30, isLive: true, voiceOverRunning: true))
        XCTAssertNil(announcer.tick(remaining: 30, total: 30, isLive: true, voiceOverRunning: true))
        XCTAssertEqual(announcer.tick(remaining: 3, total: 30, isLive: true, voiceOverRunning: true), "3 seconds left")
    }
}
