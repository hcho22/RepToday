import XCTest
@testable import RepToday

/// The "just crossed into `.strength`" detector behind the US-SP06 graduation reveal.
///
/// Two layers of coverage: the crossing *decision* against a controllable phase service (earned
/// Strength -> reveal; still Discipline -> no reveal; a missing user -> no reveal), and one true
/// end-to-end pass that drives the **real** deterministic `PhaseEvaluatorService` over the **real**
/// catalog with logs that actually clear the earn threshold - the PRD Validation Test's "a user whose
/// logs just crossed the earn threshold" setup. The once-only / survives-relaunch half of the
/// validation lives in `AppStateTests` (the persisted one-shot flag).
@MainActor
final class StrengthGraduationViewModelTests: XCTestCase {

    // MARK: - Crossing decision (controllable phase service)

    func testEarnedStrengthTriggersTheReveal() async {
        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: StubPhaseService(earned: .strength)
        )

        await viewModel.evaluate()

        XCTAssertTrue(viewModel.earnedStrength, "a user the evaluator resolves to .strength should trigger the reveal")
    }

    func testStillDisciplineDoesNotTriggerTheReveal() async {
        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: StubPhaseService(earned: .discipline)
        )

        await viewModel.evaluate()

        XCTAssertFalse(viewModel.earnedStrength, "a user still earning Strength must not trigger the reveal")
    }

    func testNoUserDoesNotTriggerTheReveal() async {
        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: nil),
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: StubPhaseService(earned: .strength)
        )

        await viewModel.evaluate()

        XCTAssertFalse(viewModel.earnedStrength, "with no profile there is nothing to congratulate; the reveal must stay closed")
    }

    // MARK: - End to end over the real evaluator + real catalog (the PRD Validation setup)

    /// Logs that have just crossed the real earn threshold - sustained consistency over the full window
    /// plus every foundation's entry tier cleared - make the real `PhaseEvaluatorService` report
    /// `.strength`, and the view model fires. This proves the wiring reaches the same gate the engine
    /// uses, not just a stub.
    func testRealLogsCrossingTheEarnThresholdTriggerTheReveal() async throws {
        let exerciseService = try MockExerciseService()
        let library = try await exerciseService.exercises()
        let logs = Self.sustainedHistory(weeks: 10) + Self.competenceLogs(library: library)

        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: logs),
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService, now: { Self.asOf }, calendar: Self.calendar)
        )

        await viewModel.evaluate()

        XCTAssertTrue(viewModel.earnedStrength, "real earn-threshold logs should resolve to .strength and fire the reveal")
    }

    /// The negative end-to-end control: a fresh user with no history stays Discipline through the real
    /// evaluator, so the reveal never fires - guarding against a wiring that always reports Strength.
    func testRealFreshHistoryDoesNotTriggerTheReveal() async throws {
        let exerciseService = try MockExerciseService()

        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService, now: { Self.asOf }, calendar: Self.calendar)
        )

        await viewModel.evaluate()

        XCTAssertFalse(viewModel.earnedStrength, "a user with no history has earned nothing yet")
    }

    // MARK: - Real earn-threshold fixture

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private static let asOf = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!

    private static func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    /// `weeklyGoal` on-goal show-up sessions per week across `weeks` weeks - a fully sustained history
    /// whose Consistency Score clears the bar over the full ~8-week window.
    private static func sustainedHistory(weeks: Int, weeklyGoal: Int = 3) -> [WorkoutLog] {
        (0..<weeks).flatMap { w in
            (0..<weeklyGoal).map { d in
                WorkoutLog(
                    id: UUID(), workoutId: UUID(),
                    completedAt: date(weeksAgo: w, dayOffset: d),
                    requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
                    shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
                    exercises: []
                )
            }
        }
    }

    /// One clearing log per foundational pattern, each derived from the **real** catalog: it finds the
    /// pattern's entry tier (the lowest `progressionOrder` in one of its chains) and logs a generous,
    /// non-skipped performance that clears whatever `advancementCriteria` that entry carries - so the
    /// fixture stays correct as the catalog evolves rather than hard-coding exercise ids.
    private static func competenceLogs(library: [Exercise]) -> [WorkoutLog] {
        PhaseEvaluator.foundationalPatterns.compactMap { pattern in
            let members = library.filter { $0.movementPattern == pattern }
            let byChain = Dictionary(grouping: members, by: \.progressionChainId)
            guard let entry = byChain.values
                .compactMap({ $0.min(by: { $0.progressionOrder < $1.progressionOrder }) })
                .min(by: { $0.progressionOrder < $1.progressionOrder })
            else { return nil }

            // Five generous sets each carrying both a big rep count and a big hold, so it clears any
            // "{sets}x{target}" criteria whether the entry is rep-based or a hold.
            let sets = (0..<5).map { _ in CompletedSet(reps: 1000, durationSeconds: 1000) }
            return WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: date(weeksAgo: 0, dayOffset: 0),
                requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
                shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
                exercises: [
                    LoggedExercise(
                        id: UUID(), exerciseId: entry.id, pillar: entry.pillar,
                        movementPattern: pattern, completedSets: sets, skipped: false
                    )
                ]
            )
        }
    }
}

/// A `PhaseServiceProtocol` that reports a fixed earned phase, so the crossing decision can be tested
/// without standing up the real evaluator and its earn-threshold fixture.
private struct StubPhaseService: PhaseServiceProtocol {
    let earned: Phase

    func phase(for user: User, recentLogs: [WorkoutLog]) async throws -> Phase { earned }

    func progress(for user: User, recentLogs: [WorkoutLog]) async throws -> PhaseProgress {
        PhaseProgress(
            activeWeeks: 0, requiredWeeks: PhaseEvaluator.sustainedWeeks,
            currentScore: 0, scoreThreshold: PhaseEvaluator.consistencyThreshold, foundations: []
        )
    }
}
