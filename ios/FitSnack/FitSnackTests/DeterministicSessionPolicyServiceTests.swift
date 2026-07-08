import XCTest
@testable import FitSnack

/// Tests the real on-device deterministic Programmer (US-F03): `DeterministicSessionPolicyService`,
/// which quietly re-tunes a user's `SessionPolicy` when a trigger fires and folds Default Duration
/// learning (US-F04) - never generating a workout, and always upholding Trigger Precedence.
///
/// Coverage mirrors the PRD acceptance criteria:
/// - `version` increments and `updatedBy == .deterministic` on every re-program;
/// - each trigger moves the expected levers (stall accelerates, disengagement eases, return seeds
///   the Re-entry Ramp, weekly boundary re-tunes only the learned duration);
/// - a disengagement re-program never raises challenge, end-to-end even off a stall trigger;
/// - the written policy persists and reads back through `currentPolicy`;
/// - Default Duration learning tracks completed (not requested) minutes, folds each session once,
///   and the note names only the real change.
final class DeterministicSessionPolicyServiceTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: d, hour: 12))!
    }

    /// A fresh user whose Ready-Screen default and onboarding seed are both `minutes`, with no
    /// completed-duration history yet. Built inline so the test stays hermetic (no persistence).
    private func user(defaultMinutes: Int = 15) -> User {
        User(
            id: "policy-test-user",
            displayName: "Riley",
            createdAt: day(1),
            profile: UserProfile(
                age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: true, injuries: [], typicalAvailableMinutes: defaultMinutes
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 78.0, workoutsThisWeek: 2,
                longestChain: 6, totalWorkoutsCompleted: 38, totalMinutesExercised: 540
            ),
            why: User.Why(statement: "get on the floor with my grandkids", openingBias: .mobility),
            duration: User.Duration.seeded(minutes: defaultMinutes),
            coldStart: User.ColdStart(sessionsLogged: 6, active: false)
        )
    }

    private func service(
        library: [Exercise] = [],
        store: InMemorySessionPolicyStore = InMemorySessionPolicyStore(),
        userService: MockUserService
    ) -> DeterministicSessionPolicyService {
        DeterministicSessionPolicyService(
            store: store,
            exerciseService: StubExerciseService(library: library),
            userService: userService
        )
    }

    private func log(
        on date: Date,
        requestedMinutes: Int,
        durationMinutes: Int,
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

    private func clearedPush() -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: "push_knee",
            pillar: .strength,
            movementPattern: .push,
            completedSets: Array(repeating: CompletedSet(reps: 12, durationSeconds: nil), count: 3),
            skipped: false
        )
    }

    /// A push chain whose entry tier's next tier exists but is gated behind the Strength phase, so a
    /// discipline-phase user who clears the entry tier stays stuck on it - the shape a Physical Stall.
    private func gatedPushChain() -> [Exercise] {
        [
            Exercise(
                id: "push_knee", displayName: "push_knee", pillar: .strength, movementPattern: .push,
                category: .strength, difficulty: 1, phase: .discipline, equipment: [], isHold: false,
                defaultReps: 10, defaultDurationSeconds: nil, estimatedTimePerSetSeconds: 40, metValue: 4,
                progressionChainId: "push", progressionOrder: 0, regressionId: nil,
                progressionId: "push_one_arm", advancementCriteria: "3x12", apartmentFriendly: true
            ),
            Exercise(
                id: "push_one_arm", displayName: "push_one_arm", pillar: .strength, movementPattern: .push,
                category: .strength, difficulty: 5, phase: .strength, equipment: [], isHold: false,
                defaultReps: 8, defaultDurationSeconds: nil, estimatedTimePerSetSeconds: 40, metValue: 4,
                progressionChainId: "push", progressionOrder: 1, regressionId: nil,
                progressionId: nil, advancementCriteria: "3x8", apartmentFriendly: true
            ),
        ]
    }

    private func trigger(_ kind: ReprogramTrigger.Kind, at date: Date) -> ReprogramTrigger {
        ReprogramTrigger(kind: kind, detectedAt: date)
    }

    // MARK: - Reading

    /// Until the Programmer writes a policy, the current policy is the always-valid default.
    func testCurrentPolicyIsDefaultUntilProgrammed() async throws {
        let users = MockUserService()
        let policy = try await service(userService: users).currentPolicy(for: user())
        XCTAssertEqual(policy, .default)
    }

    // MARK: - Provenance

    /// Every re-program increments `version` and stamps `updatedBy == .deterministic` and the
    /// injected `detectedAt` (never the wall clock).
    func testReprogramStampsVersionUpdatedByAndTime() async throws {
        let users = MockUserService()
        let svc = service(library: gatedPushChain(), userService: users)
        let clears = [clearedPush()]
        let logs = [
            log(on: day(1), requestedMinutes: 15, durationMinutes: 15, exercises: clears),
            log(on: day(2), requestedMinutes: 15, durationMinutes: 15, exercises: clears),
        ]
        let when = day(3)
        let policy = try await svc.reprogram(user: user(), recentLogs: logs, trigger: trigger(.physicalStall, at: when))

        XCTAssertEqual(policy.version, SessionPolicy.default.version + 1)
        XCTAssertEqual(policy.updatedBy, .deterministic)
        XCTAssertEqual(policy.updatedAt, when)
    }

    // MARK: - Lever mapping per trigger

    /// A physical stall raises `progressionRate` and widens the variety window (add challenge).
    func testPhysicalStallRaisesChallenge() async throws {
        let users = MockUserService()
        let svc = service(library: gatedPushChain(), userService: users)
        let clears = [clearedPush()]
        let logs = [
            log(on: day(1), requestedMinutes: 15, durationMinutes: 15, exercises: clears),
            log(on: day(2), requestedMinutes: 15, durationMinutes: 15, exercises: clears),
        ]
        let policy = try await svc.reprogram(user: user(), recentLogs: logs, trigger: trigger(.physicalStall, at: day(3)))

        XCTAssertGreaterThan(policy.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertGreaterThan(policy.varietyWindow, SessionPolicy.default.varietyWindow)
    }

    /// A disengagement re-program eases `progressionRate` and narrows the variety window, never
    /// raising challenge.
    func testDisengagementDoesNotRaiseChallenge() async throws {
        let users = MockUserService()
        let svc = service(userService: users)
        let logs = [
            log(on: day(1), requestedMinutes: 20, durationMinutes: 20),
            log(on: day(2), requestedMinutes: 20, durationMinutes: 12),
            log(on: day(3), requestedMinutes: 20, durationMinutes: 5),
        ]
        let policy = try await svc.reprogram(user: user(defaultMinutes: 20), recentLogs: logs, trigger: trigger(.disengagement, at: day(4)))

        XCTAssertLessThan(policy.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertLessThanOrEqual(policy.varietyWindow, SessionPolicy.default.varietyWindow)
    }

    /// Trigger Precedence holds end-to-end: even handed a `physicalStall` trigger, a history that is
    /// actually disengaging eases (re-diagnosis) rather than being handed more challenge.
    func testStallTriggerOnDisengagingHistoryStillEases() async throws {
        let users = MockUserService()
        let svc = service(library: gatedPushChain(), userService: users)
        let logs = [
            log(on: day(1), requestedMinutes: 20, durationMinutes: 20),
            log(on: day(2), requestedMinutes: 20, durationMinutes: 12),
            log(on: day(3), requestedMinutes: 20, durationMinutes: 5),
        ]
        let policy = try await svc.reprogram(user: user(defaultMinutes: 20), recentLogs: logs, trigger: trigger(.physicalStall, at: day(4)))

        XCTAssertLessThanOrEqual(policy.progressionRate, SessionPolicy.default.progressionRate)
    }

    /// A Return seeds the Re-entry Ramp and moves no optimization lever (discipline overrides
    /// optimization; the readjustment lives only in the ramp).
    func testReturnSeedsReentryRampAndLeavesLeversNeutral() async throws {
        let users = MockUserService()
        let svc = service(userService: users)
        let policy = try await svc.reprogram(user: user(), recentLogs: [], trigger: trigger(.return, at: day(3)))

        XCTAssertEqual(policy.reentry?.rampSessionsRemaining, ReturnOverride.rampSessions)
        XCTAssertEqual(policy.progressionRate, SessionPolicy.default.progressionRate, accuracy: 1e-9)
        XCTAssertEqual(policy.varietyWindow, SessionPolicy.default.varietyWindow)
    }

    // MARK: - Persistence

    /// The written policy persists: a follow-up `currentPolicy` returns it, not the default.
    func testReprogramPersistsPolicy() async throws {
        let users = MockUserService()
        let store = InMemorySessionPolicyStore()
        let svc = service(library: gatedPushChain(), store: store, userService: users)
        let clears = [clearedPush()]
        let logs = [
            log(on: day(1), requestedMinutes: 15, durationMinutes: 15, exercises: clears),
            log(on: day(2), requestedMinutes: 15, durationMinutes: 15, exercises: clears),
        ]
        let written = try await svc.reprogram(user: user(), recentLogs: logs, trigger: trigger(.physicalStall, at: day(3)))

        let readBack = try await svc.currentPolicy(for: user())
        XCTAssertEqual(readBack, written)
        XCTAssertEqual(readBack.version, SessionPolicy.default.version + 1)
    }

    // MARK: - Default Duration learning (US-F04 wiring / validation)

    /// PRD validation: five sessions requested at 20 but completed at ~12 drift the learned default
    /// down (EWMA toward ~12, `defaultMinutes` snaps to 10 or 15, never the requested 20), and the
    /// weekly-boundary note names the real duration change without claiming a difficulty move.
    func testWeeklyBoundaryLearnsDefaultDurationAndWritesHonestNote() async throws {
        let seedUser = user(defaultMinutes: 20)
        let users = MockUserService(user: seedUser)
        let svc = service(userService: users)
        let logs = (1...5).map { i in
            log(on: day(i), requestedMinutes: 20, durationMinutes: 12)
        }
        let policy = try await svc.reprogram(user: seedUser, recentLogs: logs, trigger: trigger(.weeklyBoundary, at: day(6)))

        // The learned duration is persisted onto the user, tracking completed (not requested) minutes.
        let learned = try await users.currentUser()!.duration
        XCTAssertLessThan(learned.completedDurationEWMA ?? .infinity, 20)
        XCTAssertTrue([10, 15].contains(learned.defaultMinutes), "default snaps to 10 or 15, got \(learned.defaultMinutes)")
        XCTAssertNotEqual(learned.defaultMinutes, 20, "must not track the requested 20")

        // The note names the real duration change; a weekly boundary moved no difficulty lever, so
        // it must not claim one.
        let note = try XCTUnwrap(policy.note)
        XCTAssertEqual(note.source, .template)
        XCTAssertTrue(note.text.contains("\(learned.defaultMinutes) minutes"))
        XCTAssertEqual(policy.progressionRate, SessionPolicy.default.progressionRate, accuracy: 1e-9)
    }

    /// Default Duration learning folds each session exactly once: re-programming again over the same
    /// (now-old) logs does not move the EWMA a second time.
    func testDefaultDurationFoldsEachSessionOnce() async throws {
        let seedUser = user(defaultMinutes: 20)
        let users = MockUserService(user: seedUser)
        let store = InMemorySessionPolicyStore()
        let svc = service(store: store, userService: users)
        let logs = (1...4).map { i in log(on: day(i), requestedMinutes: 20, durationMinutes: 12) }

        _ = try await svc.reprogram(user: seedUser, recentLogs: logs, trigger: trigger(.weeklyBoundary, at: day(10)))
        let afterFirst = try await users.currentUser()!.duration

        // Second re-program carries the updated user forward but the same logs, all now completed
        // before the policy's last write - so nothing new is folded.
        let carried = try await users.currentUser()!
        _ = try await svc.reprogram(user: carried, recentLogs: logs, trigger: trigger(.weeklyBoundary, at: day(20)))
        let afterSecond = try await users.currentUser()!.duration

        XCTAssertEqual(afterFirst.completedDurationEWMA, afterSecond.completedDurationEWMA)
        XCTAssertEqual(afterFirst.defaultMinutes, afterSecond.defaultMinutes)
    }

    /// A re-program that moves no lever and learns no new duration still writes a policy but attaches
    /// no note (the honest outcome - nothing observable changed).
    func testNoteIsNilWhenNothingObservableChanged() async throws {
        let users = MockUserService()
        let svc = service(userService: users)
        let policy = try await svc.reprogram(user: user(), recentLogs: [], trigger: trigger(.weeklyBoundary, at: day(3)))
        XCTAssertNil(policy.note)
        XCTAssertEqual(policy.version, SessionPolicy.default.version + 1)
    }
}

// MARK: - Test stub

/// A minimal `ExerciseServiceProtocol` returning a fixed in-memory library, so the deterministic
/// Programmer's tests stay hermetic and free of the bundled catalog / CoreData.
private struct StubExerciseService: ExerciseServiceProtocol {
    let library: [Exercise]

    func exercises() async throws -> [Exercise] { library }
    func exercise(id: String) async throws -> Exercise? { library.first { $0.id == id } }
    func exercises(for pillar: Pillar) async throws -> [Exercise] { library.filter { $0.pillar == pillar } }
    func exercises(for movementPattern: MovementPattern) async throws -> [Exercise] {
        library.filter { $0.movementPattern == movementPattern }
    }
    func exercises(for phase: Phase) async throws -> [Exercise] { library.filter { $0.phase == phase } }
    func exercises(inDifficultyRange range: ClosedRange<Int>) async throws -> [Exercise] {
        library.filter { range.contains($0.difficulty) }
    }
    func nextInChain(after id: String) async throws -> Exercise? {
        guard let current = library.first(where: { $0.id == id }), let nextId = current.progressionId else { return nil }
        return library.first { $0.id == nextId }
    }
}
