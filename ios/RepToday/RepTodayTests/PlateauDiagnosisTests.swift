import XCTest
@testable import RepToday

/// Tests the pure plateau diagnosis (US-F02): `PlateauDiagnosis`, which classifies recent history as
/// a Physical Stall (capacity earned but gated -> add challenge) or Disengagement (pulling away ->
/// reduce friction), and maps each to the Session Policy levers the re-weighting service (US-F03)
/// writes.
///
/// Coverage mirrors the PRD acceptance criteria: a clear stall case (a rung cleared at the Training
/// Day bar - four sets at the top of the user's range, at Earned Reps that reached it - in two sessions
/// while the next rung is gated), sessions short of that bar never stalling, a clear disengagement case,
/// and a mixed case resolved by Trigger Precedence (disengagement wins); the diagnosis reads only log
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

    /// A Training Day main station on `exerciseId`: `sets` sets at `reps`, recording Earned Reps of
    /// `earned` (defaulting to `reps`).
    private func logged(
        _ exerciseId: String,
        reps: Int,
        earned: Int? = nil,
        sets: Int = 4,
        role: StationRole? = .main
    ) -> LoggedExercise {
        TrainingDayFixtures.station(exerciseId, pattern: .push, role: role, value: reps, earned: earned ?? reps, sets: sets)
    }

    /// A log written before Training Days: no role, no Earned Reps.
    private func legacyLogged(_ exerciseId: String, reps: Int, sets: Int) -> LoggedExercise {
        TrainingDayFixtures.station(exerciseId, pattern: .push, role: nil, value: reps, earned: nil, sets: sets)
    }

    /// The new bar on the entry tier of `pushChain()` for a beginner or intermediate user: four sets at
    /// the top of the 15-30 range, at Earned Reps of 30.
    private func clears() -> [LoggedExercise] {
        [logged("push_knee", reps: 30)]
    }

    /// A push chain whose entry tier's next tier exists but is gated behind the Strength phase, so a
    /// discipline-phase user who clears the entry tier can never advance off it - the shape a Physical
    /// Stall reads.
    private func pushChain() -> [Exercise] {
        [
            exercise(id: "push_knee", difficulty: 1, order: 0, progressionId: "push_one_arm", phase: .discipline),
            exercise(id: "push_one_arm", difficulty: 5, order: 1, progressionId: nil, phase: .strength),
        ]
    }

    private func exercise(
        id: String,
        difficulty: Int,
        order: Int,
        progressionId: String?,
        phase: Phase
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
            advancementCriteria: "4 clean sets at the top of your rep range",
            apartmentFriendly: true
        )
    }

    /// A single-tier mobility chain (no next tier): a healthy user holding it at the top of the hold
    /// range every session has a frontier that can never rise, so it must NOT diagnose as a stall.
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
                advancementCriteria: "4 clean sets at the top of your rep range",
                apartmentFriendly: true
            )
        ]
    }

    // MARK: - Diagnosis

    /// History A: consistent attendance, the frontier tier cleared at the new bar across two sessions,
    /// the next tier gated -> `physicalStall`.
    func testClearStallDiagnosesPhysicalStall() {
        let logs = [
            log(on: dayInWeek(1), exercises: clears()),
            log(on: dayInWeek(2), exercises: clears()),
        ]
        XCTAssertEqual(PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain()), .physicalStall)
        XCTAssertEqual(PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain(), level: .intermediate), .physicalStall)
    }

    /// The same stall over the real catalog: an advanced Discipline-Phase user holding Archer Push-Ups
    /// at four sets of 15 a side, session after session, cannot move up - the next rung (Assisted
    /// One-Arm Push-Up) is a Strength-Phase skill.
    func testRealCatalogStallBehindAStrengthPhaseRung() async throws {
        let library = try await MockExerciseService().exercises()
        let archer = try XCTUnwrap(library.first { $0.id == "push_archer" })
        let next = try XCTUnwrap(library.first { $0.id == archer.progressionId })
        XCTAssertEqual(next.phase, .strength, "the fixture needs a gated next rung")

        let logs = [
            log(on: dayInWeek(1), exercises: [logged(archer.id, reps: 15)]),
            log(on: dayInWeek(3), exercises: [logged(archer.id, reps: 15)]),
        ]
        XCTAssertEqual(PlateauDiagnosis.diagnose(recentLogs: logs, library: library, level: .advanced), .physicalStall)

        let oneShort = [
            log(on: dayInWeek(1), exercises: [logged(archer.id, reps: 15)]),
            log(on: dayInWeek(3), exercises: [logged(archer.id, reps: 10)]),
        ]
        XCTAssertNil(PlateauDiagnosis.diagnose(recentLogs: oneShort, library: library, level: .advanced))
    }

    /// The bar is the top of the user's own range: 30 reps clears for a beginner or intermediate user and
    /// not for an advanced one, whose range runs to 50.
    func testTheStallBarIsTheTopOfTheLevelsRange() {
        let atThirty = [log(on: dayInWeek(1), exercises: clears()), log(on: dayInWeek(2), exercises: clears())]
        XCTAssertTrue(PlateauDiagnosis.isPhysicallyStalled(recentLogs: atThirty, library: pushChain(), level: .beginner))
        XCTAssertTrue(PlateauDiagnosis.isPhysicallyStalled(recentLogs: atThirty, library: pushChain(), level: .intermediate))
        XCTAssertFalse(PlateauDiagnosis.isPhysicallyStalled(recentLogs: atThirty, library: pushChain(), level: .advanced))

        let atFifty = [
            log(on: dayInWeek(1), exercises: [logged("push_knee", reps: 50)]),
            log(on: dayInWeek(2), exercises: [logged("push_knee", reps: 50)]),
        ]
        XCTAssertTrue(PlateauDiagnosis.isPhysicallyStalled(recentLogs: atFifty, library: pushChain(), level: .advanced))
    }

    /// Sessions that fall short of the bar are never a stall, however often they repeat: three-set logs
    /// written before Training Days, four sets padded to the top over lower Earned Reps, only three sets
    /// at the top, a session rated too hard, and a Practice station at the very top numbers.
    func testSessionsUnderTheBarAreNotAStall() {
        func twice(_ exercise: LoggedExercise, difficulty: PerceivedDifficulty? = nil) -> [WorkoutLog] {
            [dayInWeek(1), dayInWeek(2)].map { day in
                var session = log(on: day, exercises: [exercise])
                session.perceivedDifficulty = difficulty
                return session
            }
        }
        let shortOfTheBar: [String: [WorkoutLog]] = [
            "legacy 3x12": twice(legacyLogged("push_knee", reps: 12, sets: 3)),
            "legacy 3x30": twice(legacyLogged("push_knee", reps: 30, sets: 3)),
            "padded": twice(logged("push_knee", reps: 30, earned: 25)),
            "three sets": twice(logged("push_knee", reps: 30, sets: 3)),
            "too hard": twice(logged("push_knee", reps: 30), difficulty: .tooHard),
            "practice": twice(logged("push_knee", reps: 30, role: .practice)),
        ]
        for (name, logs) in shortOfTheBar {
            XCTAssertNil(PlateauDiagnosis.diagnose(recentLogs: logs, library: pushChain()), name)
        }
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
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20, exercises: clears()),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 12, exercises: clears()),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 5, exercises: clears()),
        ]
        XCTAssertTrue(PlateauDiagnosis.isPhysicallyStalled(recentLogs: logs, library: pushChain()), "the history is stalled")
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

    /// A single-tier chain cleared every session is not a stall (nothing to advance to), mirroring the
    /// real-library regression guarded in trigger detection.
    func testRepeatedlyClearedSingleTierChainDiagnosesNil() {
        let held = [TrainingDayFixtures.station("deep_squat_hold", pattern: .mobility, pillar: .mobility, value: 60, earned: 60, isHold: true)]
        let logs = [
            log(on: dayInWeek(1), exercises: held),
            log(on: dayInWeek(2), exercises: held),
        ]
        XCTAssertEqual(RepGrammar.clearingSessionCount(mobilityHoldChain()[0], in: logs, level: .beginner), 2,
                       "the fixture clears the bar in both sessions")
        XCTAssertNil(PlateauDiagnosis.diagnose(recentLogs: logs, library: mobilityHoldChain()))
    }

    /// Diagnosis is deterministic for a given `(recentLogs, library, level)`.
    func testDiagnosisIsDeterministic() {
        let logs = [log(on: dayInWeek(1), exercises: clears()), log(on: dayInWeek(2), exercises: clears())]
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
