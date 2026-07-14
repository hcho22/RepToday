import XCTest
@testable import RepToday

/// Tests the pure plateau diagnosis (US-F02): `PlateauDiagnosis`, which classifies recent history as
/// a Physical Stall (capacity earned but gated -> add challenge) or Disengagement (pulling away ->
/// reduce friction), and maps each to the Session Policy levers the re-weighting service (US-F03)
/// writes.
///
/// Coverage mirrors the PRD acceptance criteria: a clear stall case, a clear disengagement case, and
/// a mixed case resolved by Trigger Precedence (disengagement wins); the diagnosis reads only log
/// history and is deterministic; and the lever mapping is explicit (stall raises
/// `progressionRate`/variety, disengagement eases them and never raises challenge), clamped to its
/// rails. The stall/disengagement detection itself is the shared seam exercised through the trigger
/// path in `ReprogramTriggerDetectionTests`; here we assert the diagnosis and the lever mapping.
final class PlateauDiagnosisTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var weekStart: Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 12))!
        return calendar.dateInterval(of: .weekOfYear, for: base)!.start
    }

    private func dayInWeek(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: weekStart)!
    }

    private func log(
        on date: Date,
        requestedMinutes: Int = 15,
        durationMinutes: Int = 15,
        exercises: [LoggedExercise] = []
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date,
            requestedMinutes: requestedMinutes,
            durationMinutes: durationMinutes,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: exercises
        )
    }

    private func logged(
        _ exerciseId: String,
        reps: Int,
        sets: Int,
        skipped: Bool = false
    ) -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: exerciseId,
            pillar: .strength,
            movementPattern: .push,
            completedSets: Array(repeating: CompletedSet(reps: reps, durationSeconds: nil), count: sets),
            skipped: skipped
        )
    }

    private func loggedHold(
        _ exerciseId: String,
        seconds: Int,
        sets: Int
    ) -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: exerciseId,
            pillar: .mobility,
            movementPattern: .mobility,
            completedSets: Array(repeating: CompletedSet(reps: nil, durationSeconds: seconds), count: sets),
            skipped: false
        )
    }

    /// A push chain whose entry tier's next tier exists but is gated behind the Strength phase, so a
    /// discipline-phase user who clears the entry tier can never advance off it - the shape a Physical
    /// Stall reads.
    private func pushChain() -> [Exercise] {
        [
            exercise(id: "push_knee", difficulty: 1, order: 0, progressionId: "push_one_arm", phase: .discipline, criteria: "3x12"),
            exercise(id: "push_one_arm", difficulty: 5, order: 1, progressionId: nil, phase: .strength, criteria: "3x8"),
        ]
    }

    private func exercise(
        id: String,
        difficulty: Int,
        order: Int,
        progressionId: String?,
        phase: Phase,
        criteria: String
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: .strength,
            movementPattern: .push,
            category: .strength,
            difficulty: difficulty,
            phase: phase,
            equipment: [],
            isHold: false,
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "push",
            progressionOrder: order,
            regressionId: nil,
            progressionId: progressionId,
            advancementCriteria: criteria,
            apartmentFriendly: true
        )
    }

    /// A single-tier mobility chain (no next tier) with easily-met hold criteria: a healthy user
    /// clearing it every session has a frontier that can never rise, so it must NOT diagnose as a
    /// stall.
    private func mobilityHoldChain() -> [Exercise] {
        [
            Exercise(
                id: "deep_squat_hold",
                displayName: "deep_squat_hold",
                pillar: .mobility,
                movementPattern: .mobility,
                category: .mobility,
                difficulty: 1,
                phase: .discipline,
                equipment: [],
                isHold: true,
                defaultReps: nil,
                defaultDurationSeconds: 60,
                estimatedTimePerSetSeconds: 60,
                metValue: 2,
                progressionChainId: "deep_squat_hold",
                progressionOrder: 0,
                regressionId: nil,
                progressionId: nil,
                advancementCriteria: "hold 60s",
                apartmentFriendly: true
            )
        ]
    }

    // MARK: - Diagnosis

    /// History A: consistent attendance, frontier criteria cleared across two sessions, next tier
    /// gated -> `physicalStall`.
    func testClearStallDiagnosesPhysicalStall() {
        let clears = [logged("push_knee", reps: 12, sets: 3)] // meets "3x12"
        let logs = [
            log(on: dayInWeek(1), exercises: clears),
            log(on: dayInWeek(2), exercises: clears),
        ]
        XCTAssertEqual(PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain()), .physicalStall)
    }

    /// History B: sessions completing a shrinking share of what was requested (20 asked; 20, 12, 5
    /// done) -> `disengagement`.
    func testClearDisengagementDiagnosesDisengagement() {
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 12),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 5),
        ]
        XCTAssertEqual(PlateauDiagnosis.diagnose(recentLogs: logs, library: []), .disengagement)
    }

    /// A history that is simultaneously stalled and disengaging: Trigger Precedence resolves it to
    /// `disengagement` (PRD validation - a user pulling away is never handed more challenge).
    func testMixedCaseResolvedByPrecedence() {
        let clears = [logged("push_knee", reps: 12, sets: 3)] // clears the gated frontier every session
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20, exercises: clears),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 12, exercises: clears),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 5, exercises: clears),
        ]
        XCTAssertEqual(PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain()), .disengagement)
    }

    /// Steady, complete sessions with no gated stall diagnose as neither plateau.
    func testHealthyHistoryDiagnosesNil() {
        let logs = [
            log(on: dayInWeek(1), durationMinutes: 20),
            log(on: dayInWeek(2), durationMinutes: 20),
            log(on: dayInWeek(3), durationMinutes: 20),
        ]
        XCTAssertNil(PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain()))
    }

    /// A fresh user with no history has nothing to diagnose.
    func testFreshUserDiagnosesNil() {
        XCTAssertNil(PlateauDiagnosis.diagnose(recentLogs: [], library: pushChain()))
    }

    /// A single-tier mobility chain cleared every session is not a stall (nothing to advance to),
    /// mirroring the real-library regression guarded in trigger detection.
    func testRepeatedlyClearedSingleTierChainDiagnosesNil() {
        let clears = [loggedHold("deep_squat_hold", seconds: 60, sets: 1)] // meets "hold 60s"
        let logs = [
            log(on: dayInWeek(1), exercises: clears),
            log(on: dayInWeek(2), exercises: clears),
        ]
        XCTAssertNil(PlateauDiagnosis.diagnose(recentLogs: logs, library: mobilityHoldChain()))
    }

    /// Diagnosis is deterministic for a given `(recentLogs, library)`.
    func testDiagnosisIsDeterministic() {
        let clears = [logged("push_knee", reps: 12, sets: 3)]
        let logs = [log(on: dayInWeek(1), exercises: clears), log(on: dayInWeek(2), exercises: clears)]
        XCTAssertEqual(
            PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain()),
            PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain())
        )
    }

    // MARK: - Lever mapping

    /// A physical stall raises `progressionRate` and widens the variety window off the neutral
    /// default (1.0 / 3 -> 1.15 / 4), touching no other lever.
    func testPhysicalStallRaisesProgressionAndVariety() {
        let policy = PlateauDiagnosis.reweighted(.default, for: .physicalStall)
        XCTAssertGreaterThan(policy.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertGreaterThan(policy.varietyWindow, SessionPolicy.default.varietyWindow)
        XCTAssertEqual(policy.progressionRate, 1.0 * PlateauDiagnosis.stallProgressionBoost, accuracy: 1e-9)
        XCTAssertEqual(policy.varietyWindow, 3 + PlateauDiagnosis.stallVarietyWiden)
        // Untouched levers are preserved.
        XCTAssertEqual(policy.pillarWeighting, SessionPolicy.default.pillarWeighting)
        XCTAssertEqual(policy.version, SessionPolicy.default.version, "F02 moves levers only; version is F03's")
    }

    /// Disengagement eases `progressionRate` (lower difficulty) and narrows the variety window off
    /// the neutral default (1.0 / 3 -> 0.85 / 2).
    func testDisengagementEasesProgressionAndNarrowsVariety() {
        let policy = PlateauDiagnosis.reweighted(.default, for: .disengagement)
        XCTAssertLessThan(policy.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertLessThan(policy.varietyWindow, SessionPolicy.default.varietyWindow)
        XCTAssertEqual(policy.progressionRate, 1.0 * PlateauDiagnosis.disengagementProgressionEase, accuracy: 1e-9)
        XCTAssertEqual(policy.varietyWindow, 3 - PlateauDiagnosis.disengagementVarietyNarrow)
    }

    /// Disengagement never increases challenge no matter the starting policy (Trigger Precedence at
    /// the lever level): from an already-accelerated program it still eases and never widens variety.
    func testDisengagementNeverRaisesChallenge() {
        var accelerated = SessionPolicy.default
        accelerated.progressionRate = 1.4
        accelerated.varietyWindow = 5
        let policy = PlateauDiagnosis.reweighted(accelerated, for: .disengagement)
        XCTAssertLessThanOrEqual(policy.progressionRate, accelerated.progressionRate)
        XCTAssertLessThanOrEqual(policy.varietyWindow, accelerated.varietyWindow)
    }

    /// Repeated stalls accelerate but never exceed the rails.
    func testStallClampsAtCeiling() {
        var hot = SessionPolicy.default
        hot.progressionRate = 1.95 // * 1.15 would exceed the ceiling
        hot.varietyWindow = PlateauDiagnosis.maxVarietyWindow
        let policy = PlateauDiagnosis.reweighted(hot, for: .physicalStall)
        XCTAssertEqual(policy.progressionRate, PlateauDiagnosis.maxProgressionRate, accuracy: 1e-9)
        XCTAssertEqual(policy.varietyWindow, PlateauDiagnosis.maxVarietyWindow)
    }

    /// Repeated disengagement eases but never below the rails.
    func testDisengagementClampsAtFloor() {
        var low = SessionPolicy.default
        low.progressionRate = 0.55 // * 0.85 would drop below the floor
        low.varietyWindow = PlateauDiagnosis.minVarietyWindow
        let policy = PlateauDiagnosis.reweighted(low, for: .disengagement)
        XCTAssertEqual(policy.progressionRate, PlateauDiagnosis.minProgressionRate, accuracy: 1e-9)
        XCTAssertEqual(policy.varietyWindow, PlateauDiagnosis.minVarietyWindow)
    }
}
