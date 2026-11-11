import XCTest
@testable import RepToday

/// Tests the pure re-program trigger detection (US-F01): the deterministic `ReprogramTriggerDetection`
/// that decides which `ReprogramTrigger`s are due on app open.
///
/// Coverage mirrors the PRD acceptance criteria at the unit level: each of the four triggers fires
/// independently (Weekly Boundary, Return, Physical Stall, Disengagement); Trigger Precedence is
/// enforced (Disengagement suppresses Physical Stall); a healthy in-week history and a fresh user
/// produce no triggers; and detection is pure and deterministic under an injected clock. The Return
/// gap detection itself is exercised in `ReturnOverrideTests`; here we assert only that the `return`
/// trigger surfaces when that seam fires.
final class ReprogramTriggerDetectionTests: XCTestCase {

    // MARK: - Calendar & date fixtures

    /// A fixed UTC gregorian calendar so week boundaries and day gaps are deterministic.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The start of the calendar week containing a stable mid-2026 reference date.
    private var weekStart: Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 12))!
        return calendar.dateInterval(of: .weekOfYear, for: base)!.start
    }

    /// A date `days` into the reference week (0 == the week's start-of-day).
    private func dayInWeek(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: weekStart)!
    }

    // MARK: - Log & exercise fixtures

    /// A completed session on `date` with the given logged exercises. Duration defaults keep the
    /// session steady (not shrinking) unless a test overrides them.
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

    /// A worked (or skipped) Training Day main station with `sets` sets of `reps` reps, recording Earned
    /// Reps of `reps`.
    private func logged(
        _ exerciseId: String,
        reps: Int,
        sets: Int = 4,
        skipped: Bool = false
    ) -> LoggedExercise {
        TrainingDayFixtures.station(exerciseId, pattern: .push, value: reps, earned: reps, sets: sets, skipped: skipped)
    }

    /// The Training Day bar on the entry tier of `pushChain()` for the intermediate sample user: four
    /// sets at the top of the 15-30 range, at Earned Reps of 30.
    private func clears() -> [LoggedExercise] {
        [logged("push_knee", reps: 30)]
    }

    /// A push-chain library: a beginner entry tier whose next tier exists but is gated behind the
    /// Strength phase, so a discipline-phase user who clears the entry tier can never advance off it -
    /// the shape a Physical Stall reads.
    private func pushChain() -> [Exercise] {
        [
            exercise(
                id: "push_knee",
                difficulty: 1,
                order: 0,
                progressionId: "push_one_arm",
                phase: .discipline
            ),
            exercise(
                id: "push_one_arm",
                difficulty: 5,
                order: 1,
                progressionId: nil,
                phase: .strength
            ),
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

    /// A single-tier mobility chain (no next tier), mirroring the library's deep-squat-hold / pigeon /
    /// cat-cow shape: a healthy user holding it at the top of the hold range every session has a frontier
    /// that can never rise, so it must NOT read as a Physical Stall.
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

    /// A hold station with four sets of `seconds` seconds, recording them as earned.
    private func loggedHold(_ exerciseId: String, seconds: Int) -> LoggedExercise {
        TrainingDayFixtures.station(exerciseId, pattern: .mobility, pillar: .mobility, value: seconds, earned: seconds, isHold: true)
    }

    /// The sample user (intermediate) at `level`.
    private func user(level: FitnessLevel) -> User {
        var user = MockPersistence.sampleUser
        user.profile.fitnessLevel = level
        return user
    }

    private func kinds(
        user: User = MockPersistence.sampleUser,
        recentLogs: [WorkoutLog],
        library: [Exercise] = [],
        asOf: Date
    ) -> [ReprogramTrigger.Kind] {
        ReprogramTriggerDetection.dueTriggers(
            user: user,
            recentLogs: recentLogs,
            library: library,
            asOf: asOf,
            calendar: calendar
        ).map(\.kind)
    }

    // MARK: - Empty / healthy baselines

    func testFreshUserHasNoTriggers() {
        XCTAssertTrue(kinds(recentLogs: [], asOf: dayInWeek(3)).isEmpty,
                      "a user with no history has nothing to re-program against")
    }

    /// Three steady, complete, same-week sessions read as fully engaged and mid-week: no trigger.
    func testHealthyInWeekHistoryHasNoTriggers() {
        let logs = [
            log(on: dayInWeek(1), durationMinutes: 20),
            log(on: dayInWeek(2), durationMinutes: 20),
            log(on: dayInWeek(3), durationMinutes: 20),
        ]
        XCTAssertTrue(kinds(recentLogs: logs, asOf: dayInWeek(4)).isEmpty)
    }

    // MARK: - Weekly Boundary

    /// A single session in the previous calendar week, opened this week with only a small gap: the
    /// Weekly Boundary is due while Return (gap < threshold) and the trend triggers are not.
    func testWeeklyBoundaryFiresIndependently() {
        let lastWeek = calendar.date(byAdding: .day, value: -1, to: weekStart)! // last day of prior week
        let asOf = dayInWeek(1) // early this week; a ~2-day gap, but a new week
        let result = kinds(recentLogs: [log(on: lastWeek)], asOf: asOf)
        XCTAssertEqual(result, [.weeklyBoundary])
    }

    /// Same week as the last session: no boundary has been crossed.
    func testNoWeeklyBoundaryWithinTheSameWeek() {
        let logs = [log(on: dayInWeek(1))]
        XCTAssertFalse(kinds(recentLogs: logs, asOf: dayInWeek(3)).contains(.weeklyBoundary))
    }

    // MARK: - Return

    /// A gap past the Return threshold surfaces the `return` trigger (the gap detection itself is
    /// covered in `ReturnOverrideTests`).
    func testReturnFiresOnALongGap() {
        let asOf = dayInWeek(3)
        let lastSession = calendar.date(byAdding: .day, value: -10, to: asOf)!
        XCTAssertTrue(kinds(recentLogs: [log(on: lastSession)], asOf: asOf).contains(.return))
    }

    // MARK: - Physical Stall

    /// Clearing the frontier tier at the Training Day bar across two same-week sessions, with no
    /// eligible next tier to advance onto, fires Physical Stall alone.
    func testPhysicalStallFiresIndependently() {
        let logs = [
            log(on: dayInWeek(2), exercises: clears()),
            log(on: dayInWeek(3), exercises: clears()),
        ]
        XCTAssertEqual(kinds(recentLogs: logs, library: pushChain(), asOf: dayInWeek(4)), [.physicalStall])
    }

    /// Clearing the bar only once is not "repeatedly": no stall.
    func testSingleClearIsNotAStall() {
        let logs = [
            log(on: dayInWeek(2), exercises: clears()),
            log(on: dayInWeek(3), exercises: [logged("push_knee", reps: 25)]), // a step under the top
        ]
        XCTAssertFalse(kinds(recentLogs: logs, library: pushChain(), asOf: dayInWeek(4)).contains(.physicalStall))
    }

    /// Three-set sessions written before Training Days never clear a rung, however often they repeat:
    /// the bar is four sets at the top of the user's range.
    func testThreeSetLegacyClearsAreNotAStall() {
        let legacy = [TrainingDayFixtures.station("push_knee", pattern: .push, role: nil, value: 12, sets: 3)]
        let logs = [
            log(on: dayInWeek(2), exercises: legacy),
            log(on: dayInWeek(3), exercises: legacy),
        ]
        XCTAssertFalse(kinds(recentLogs: logs, library: pushChain(), asOf: dayInWeek(4)).contains(.physicalStall))
    }

    /// The bar is read at the user's own level: 30 reps is the top of an intermediate range but mid-range
    /// for an advanced user, whose range runs to 50.
    func testPhysicalStallReadsTheUsersLevel() {
        let atThirty = [
            log(on: dayInWeek(2), exercises: clears()),
            log(on: dayInWeek(3), exercises: clears()),
        ]
        XCTAssertFalse(
            kinds(user: user(level: .advanced), recentLogs: atThirty, library: pushChain(), asOf: dayInWeek(4))
                .contains(.physicalStall)
        )
        let atFifty = [
            log(on: dayInWeek(2), exercises: [logged("push_knee", reps: 50)]),
            log(on: dayInWeek(3), exercises: [logged("push_knee", reps: 50)]),
        ]
        XCTAssertEqual(
            kinds(user: user(level: .advanced), recentLogs: atFifty, library: pushChain(), asOf: dayInWeek(4)),
            [.physicalStall]
        )
    }

    /// A skipped clearing session does not count toward a stall.
    func testSkippedWorkIsNotAStall() {
        let logs = [
            log(on: dayInWeek(2), exercises: [logged("push_knee", reps: 30, skipped: true)]),
            log(on: dayInWeek(3), exercises: [logged("push_knee", reps: 30, skipped: true)]),
        ]
        XCTAssertFalse(kinds(recentLogs: logs, library: pushChain(), asOf: dayInWeek(4)).contains(.physicalStall))
    }

    /// A single-tier chain (no next tier to advance to) cleared every session is NOT a stall - a
    /// healthy user doing routine mobility to target must never be handed "add challenge". This is the
    /// regression for the real-library false positive: the single-tier mobility chains held at the top
    /// of the range would otherwise all read as plateaus.
    func testRepeatedlyClearedSingleTierChainIsNotStall() {
        let held = [loggedHold("deep_squat_hold", seconds: 60)]
        let logs = [
            log(on: dayInWeek(2), exercises: held),
            log(on: dayInWeek(3), exercises: held),
        ]
        XCTAssertTrue(RepGrammar.hasCleared(mobilityHoldChain()[0], in: logs, level: .intermediate),
                      "the fixture clears the bar")
        XCTAssertFalse(
            kinds(recentLogs: logs, library: mobilityHoldChain(), asOf: dayInWeek(4)).contains(.physicalStall),
            "a maxed single-tier chain has nothing to advance to and is not a plateau"
        )
    }

    // MARK: - Disengagement

    /// Completing a shrinking share of what was requested (20 asked / 20, 12, 5 done -> ratios
    /// 1.0, 0.6, 0.25), same week, fires Disengagement alone (no stations, so no stall confounds it).
    func testDisengagementFiresOnFallingCompletion() {
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 12),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 5),
        ]
        XCTAssertEqual(kinds(recentLogs: logs, asOf: dayInWeek(4)), [.disengagement])
    }

    /// A user who deliberately requests shorter sessions and finishes each fully (Default Duration
    /// learning) holds a completion ratio of 1.0 and never reads as disengaging - the requested-vs-
    /// completed gap, not absolute completed minutes, is what the signal reads (US-D02).
    func testIntentionalShorterSessionsAreNotDisengagement() {
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 15, durationMinutes: 15),
            log(on: dayInWeek(2), requestedMinutes: 10, durationMinutes: 10),
            log(on: dayInWeek(3), requestedMinutes: 5, durationMinutes: 5),
        ]
        XCTAssertFalse(kinds(recentLogs: logs, asOf: dayInWeek(4)).contains(.disengagement),
                       "finishing what you asked for is engagement, even as the ask shrinks")
    }

    /// A window whose skip rate reaches the threshold fires Disengagement even when completion holds
    /// (each session finishes the full requested duration, so only the skip branch is exercised).
    func testDisengagementFiresOnRisingSkips() {
        let skippedPair = [
            logged("a", reps: 10, sets: 2, skipped: true),
            logged("b", reps: 10, sets: 2, skipped: false),
        ]
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20, exercises: skippedPair),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 20, exercises: skippedPair),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 20, exercises: skippedPair),
        ]
        XCTAssertEqual(kinds(recentLogs: logs, asOf: dayInWeek(4)), [.disengagement])
    }

    /// Steady, complete sessions do not read as disengagement.
    func testSteadySessionsAreNotDisengagement() {
        let logs = [
            log(on: dayInWeek(1), durationMinutes: 20),
            log(on: dayInWeek(2), durationMinutes: 20),
            log(on: dayInWeek(3), durationMinutes: 20),
        ]
        XCTAssertFalse(kinds(recentLogs: logs, asOf: dayInWeek(4)).contains(.disengagement))
    }

    /// Fewer than a full window of sessions is not enough of a trend to judge.
    func testTwoSessionsNeverReadAsDisengagement() {
        let logs = [
            log(on: dayInWeek(1), durationMinutes: 20),
            log(on: dayInWeek(3), durationMinutes: 3),
        ]
        XCTAssertFalse(kinds(recentLogs: logs, asOf: dayInWeek(4)).contains(.disengagement))
    }

    // MARK: - Trigger Precedence

    /// A history that is simultaneously stalled (the frontier cleared at the bar repeatedly) and
    /// disengaging (completing a falling share of the requested time): Disengagement wins and Physical
    /// Stall is suppressed (PRD validation).
    func testDisengagementSuppressesPhysicalStall() {
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20, exercises: clears()),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 12, exercises: clears()),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 5, exercises: clears()),
        ]
        XCTAssertTrue(
            PlateauDiagnosis.isPhysicallyStalled(recentLogs: logs, library: pushChain(), level: .intermediate),
            "the history clears the bar in every session"
        )
        let result = kinds(recentLogs: logs, library: pushChain(), asOf: dayInWeek(4))
        XCTAssertTrue(result.contains(.disengagement), "disengagement is due")
        XCTAssertFalse(result.contains(.physicalStall), "physical stall is suppressed under disengagement")
    }

    // MARK: - Ordering & determinism

    /// When several triggers are due, they are returned in precedence order (Return leads).
    func testTriggersReturnedInPrecedenceOrder() {
        // A long gap into a new week yields both `return` and `weeklyBoundary`; return precedes it.
        let asOf = dayInWeek(3)
        let lastSession = calendar.date(byAdding: .day, value: -10, to: asOf)!
        let result = kinds(recentLogs: [log(on: lastSession)], asOf: asOf)
        XCTAssertEqual(result, [.return, .weeklyBoundary])
    }

    /// Detection is deterministic and stamps every trigger's `detectedAt` from the injected clock.
    func testDeterministicAndStampsDetectedAt() {
        let logs = [
            log(on: dayInWeek(1), requestedMinutes: 20, durationMinutes: 20),
            log(on: dayInWeek(2), requestedMinutes: 20, durationMinutes: 12),
            log(on: dayInWeek(3), requestedMinutes: 20, durationMinutes: 5),
        ]
        let asOf = dayInWeek(4)
        let first = ReprogramTriggerDetection.dueTriggers(
            user: MockPersistence.sampleUser, recentLogs: logs, library: [], asOf: asOf, calendar: calendar
        )
        let second = ReprogramTriggerDetection.dueTriggers(
            user: MockPersistence.sampleUser, recentLogs: logs, library: [], asOf: asOf, calendar: calendar
        )
        XCTAssertEqual(first, second, "identical inputs yield identical triggers")
        XCTAssertTrue(first.allSatisfy { $0.detectedAt == asOf }, "detectedAt is stamped from asOf")
    }
}
