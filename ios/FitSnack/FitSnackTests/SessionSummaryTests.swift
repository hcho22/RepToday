import XCTest
@testable import FitSnack

/// Tests the pure post-session summary builder (US-L01).
///
/// The summary is what the celebration screen renders: the effort (duration + sets) and the
/// muscle/mobility coverage the session produced. It is derived entirely from the logged rows, so
/// these tests confirm it can only ever name coverage the user actually did - skipped movements
/// contribute nothing, and the labels/order are deterministic.
final class SessionSummaryTests: XCTestCase {

    private func logged(
        _ exerciseId: String,
        pillar: Pillar,
        pattern: MovementPattern,
        sets: Int,
        skipped: Bool = false
    ) -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: exerciseId,
            pillar: pillar,
            movementPattern: pattern,
            completedSets: (0..<sets).map { _ in CompletedSet(reps: 10, durationSeconds: nil) },
            skipped: skipped
        )
    }

    /// Coverage counts every non-skipped exercise with at least one completed set, de-duplicated and
    /// returned in canonical pillar/pattern order.
    func testCoverageFromCompletedExercises() {
        let rows = [
            logged("cat_cow", pillar: .mobility, pattern: .mobility, sets: 1),
            logged("push_up", pillar: .strength, pattern: .push, sets: 3),
            logged("air_squat", pillar: .strength, pattern: .squat, sets: 2)
        ]

        let summary = SessionSummary.from(loggedExercises: rows, durationMinutes: 14)

        XCTAssertEqual(summary.durationMinutes, 14)
        XCTAssertEqual(summary.completedSetCount, 6)
        XCTAssertEqual(summary.completedExerciseCount, 3)
        XCTAssertEqual(summary.skippedExerciseCount, 0)
        // Canonical Pillar order is strength, mobility, primal.
        XCTAssertEqual(summary.pillars, [.strength, .mobility])
        // Canonical MovementPattern order is push, squat, hinge, core, pull, mobility, locomotion.
        XCTAssertEqual(summary.movementPatterns, [.push, .squat, .mobility])
    }

    /// A skipped exercise contributes nothing to coverage (it was abandoned), only to the skip tally.
    func testSkippedExercisesDoNotCountTowardCoverage() {
        let rows = [
            logged("push_up", pillar: .strength, pattern: .push, sets: 3),
            logged("bear_crawl", pillar: .primal, pattern: .locomotion, sets: 0, skipped: true)
        ]

        let summary = SessionSummary.from(loggedExercises: rows, durationMinutes: 10)

        XCTAssertEqual(summary.completedExerciseCount, 1)
        XCTAssertEqual(summary.skippedExerciseCount, 1)
        XCTAssertEqual(summary.pillars, [.strength], "the skipped primal movement is not claimed")
        XCTAssertFalse(summary.movementPatterns.contains(.locomotion))
    }

    /// A non-skipped exercise with no recorded sets (nothing actually performed) is not coverage.
    func testExerciseWithNoCompletedSetsIsNotCoverage() {
        let rows = [logged("push_up", pillar: .strength, pattern: .push, sets: 0)]

        let summary = SessionSummary.from(loggedExercises: rows, durationMinutes: 5)

        XCTAssertEqual(summary.completedExerciseCount, 0)
        XCTAssertTrue(summary.pillars.isEmpty)
        XCTAssertEqual(summary.coverageText, "", "nothing covered -> no coverage phrase to over-claim")
    }

    /// Duplicate pillars/patterns across exercises are collapsed to one each.
    func testCoverageDeduplicates() {
        let rows = [
            logged("push_up", pillar: .strength, pattern: .push, sets: 2),
            logged("pike_push", pillar: .strength, pattern: .push, sets: 2)
        ]

        let summary = SessionSummary.from(loggedExercises: rows, durationMinutes: 8)

        XCTAssertEqual(summary.pillars, [.strength])
        XCTAssertEqual(summary.movementPatterns, [.push])
        XCTAssertEqual(summary.completedSetCount, 4)
    }

    /// The coverage phrase reads as natural language across one/two/three pillars.
    func testCoverageTextNaturalLanguage() {
        XCTAssertEqual(SessionSummary.naturalJoin(["Strength"]), "Strength")
        XCTAssertEqual(SessionSummary.naturalJoin(["Strength", "Mobility"]), "Strength and Mobility")
        XCTAssertEqual(SessionSummary.naturalJoin(["Strength", "Mobility", "Primal"]), "Strength, Mobility, and Primal")
    }

    /// The focus line lists the movement areas, separated by a middot.
    func testFocusText() {
        let rows = [
            logged("push_up", pillar: .strength, pattern: .push, sets: 1),
            logged("air_squat", pillar: .strength, pattern: .squat, sets: 1),
            logged("plank", pillar: .strength, pattern: .core, sets: 1)
        ]

        let summary = SessionSummary.from(loggedExercises: rows, durationMinutes: 12)

        XCTAssertEqual(summary.coverageText, "Strength")
        XCTAssertEqual(summary.focusText, "Push · Squat · Core")
    }

    /// Building the same rows twice yields the same summary (deterministic).
    func testDeterministic() {
        let rows = [
            logged("push_up", pillar: .strength, pattern: .push, sets: 3),
            logged("cat_cow", pillar: .mobility, pattern: .mobility, sets: 1)
        ]

        XCTAssertEqual(
            SessionSummary.from(loggedExercises: rows, durationMinutes: 14),
            SessionSummary.from(loggedExercises: rows, durationMinutes: 14)
        )
    }
}
