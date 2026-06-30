import XCTest
@testable import FitSnack

/// Tests pipeline Step 7 of the deterministic engine (US-C07): assembling Steps 1-6 into a complete,
/// timing-fit `Workout`.
///
/// Coverage mirrors the PRD acceptance criteria, run end-to-end over the real bundled library so the
/// whole pipeline is exercised: every session opens with a warm-up; a cooldown closes a session only
/// when it runs past 10 minutes; the planned wall-clock lands within ±1 minute of the request for
/// 5/10/15/20/30; generation is under 100ms; the output is a fully-formed, capacity-relative session;
/// and assembly is deterministic. The final block is the PRD's own validation case (intermediate user,
/// some history, 20 minutes).
final class SessionAssemblyTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        sitsLong: Bool = false,
        injuries: [String] = []
    ) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: level,
                primaryGoal: .stayActive,
                sitsLong: sitsLong,
                injuries: injuries,
                typicalAvailableMinutes: 15
            ),
            phase: phase,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 1,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
    }

    /// A completed session `daysAgo` working `exercises` (id, pillar, pattern, per-set reps), used to
    /// give the user "some history" so Steps 2-6 have signal.
    private func log(
        _ exercises: [(id: String, pillar: Pillar, pattern: MovementPattern, reps: Int)],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            durationMinutes: 20,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: difficulty,
            exercises: exercises.map { entry in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: entry.id,
                    pillar: entry.pillar,
                    movementPattern: entry.pattern,
                    completedSets: [
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                    ],
                    skipped: false
                )
            }
        )
    }

    /// A few days of mixed history so the engine has staleness and capacity signal to read.
    private func someHistory() -> [WorkoutLog] {
        [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 2, difficulty: .justRight),
            log([
                ("mobility_cat_cow", .mobility, .mobility, 10),
            ], daysAgo: 4),
        ]
    }

    private let durations = [5, 10, 15, 20, 30]

    private func assemble(
        minutes: Int,
        user: User,
        library: [Exercise],
        logs: [WorkoutLog]
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            asOf: asOf,
            calendar: calendar
        )
    }

    // MARK: - Warm-up always opens the session

    func testEverySessionOpensWithAWarmUp() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let first = try XCTUnwrap(workout.blocks.first, "\(minutes) min produced no blocks")
            XCTAssertEqual(first.category, .warmup, "\(minutes) min must open with a warm-up")
            XCTAssertFalse(first.exercises.isEmpty, "\(minutes) min warm-up must have an exercise")
        }
    }

    func testMobilityLedSessionStillOpensWithAWarmUp() async throws {
        let library = try await library()
        // A desk worker whose mobility is the stalest pillar gets a mobility-led short session that
        // still opens with a warm-up (the opening flow doubles as warm-up + training).
        let logs = [log([("push_standard", .strength, .push, 12)], daysAgo: 1)]
        let workout = assemble(minutes: 10, user: user(sitsLong: true), library: library, logs: logs)
        XCTAssertEqual(workout.blocks.first?.category, .warmup)
        XCTAssertEqual(workout.focusPillar, .mobility, "stale mobility + desk worker leads to a mobility focus")
    }

    // MARK: - Cooldown only past 10 minutes

    func testCooldownPresentOnlyWhenOverTenMinutes() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let hasCooldown = workout.blocks.contains { $0.category == .cooldown }
            if minutes > 10 {
                XCTAssertTrue(hasCooldown, "\(minutes) min should end with a cooldown")
                XCTAssertEqual(workout.blocks.last?.category, .cooldown, "\(minutes) min cooldown must be last")
            } else {
                XCTAssertFalse(hasCooldown, "\(minutes) min should not have a cooldown")
            }
        }
    }

    // MARK: - Timing fit: within ±1 minute

    func testTotalTimeLandsWithinOneMinuteForEveryDuration() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let planned = SessionAssembly.plannedSeconds(of: workout)
            let target = minutes * 60
            XCTAssertLessThanOrEqual(
                abs(planned - target),
                SessionAssembly.toleranceSeconds,
                "\(minutes) min planned \(planned)s is outside ±60s of \(target)s"
            )
        }
    }

    func testTimingFitHoldsForAFreshUserToo() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: [])
            let planned = SessionAssembly.plannedSeconds(of: workout)
            XCTAssertLessThanOrEqual(abs(planned - minutes * 60), SessionAssembly.toleranceSeconds,
                                     "fresh-user \(minutes) min planned \(planned)s outside tolerance")
        }
    }

    // MARK: - Latency under 100ms

    func testGenerationLatencyUnder100ms() async throws {
        let library = try await library()
        let user = user()
        let logs = someHistory()
        // Warm the path once, then measure a single end-to-end assembly.
        _ = assemble(minutes: 20, user: user, library: library, logs: logs)

        let start = DispatchTime.now()
        _ = assemble(minutes: 20, user: user, library: library, logs: logs)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertLessThan(elapsedMs, 100, "assembly took \(elapsedMs)ms, over the 100ms budget")
    }

    // MARK: - Fully-formed, playable output

    func testOutputIsFullyFormedAndCapacityRelative() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            XCTAssertEqual(workout.requestedMinutes, minutes)
            XCTAssertFalse(workout.blocks.isEmpty, "\(minutes) min produced no blocks")

            for block in workout.blocks {
                XCTAssertFalse(block.exercises.isEmpty, "block '\(block.title)' is empty")
                for prescription in block.exercises {
                    XCTAssertGreaterThanOrEqual(prescription.sets, 1, "every prescription needs >=1 set")
                    if prescription.exercise.isHold {
                        XCTAssertNotNil(prescription.durationSeconds, "\(prescription.exercise.id) hold needs seconds")
                        XCTAssertNil(prescription.reps, "\(prescription.exercise.id) hold must not carry reps")
                    } else {
                        XCTAssertNotNil(prescription.reps, "\(prescription.exercise.id) rep movement needs reps")
                        XCTAssertNil(prescription.durationSeconds, "\(prescription.exercise.id) reps must not carry seconds")
                        // Capacity-relative, never a fixed heroic number: within the overload rails.
                        XCTAssertLessThanOrEqual(prescription.reps!, AdaptiveOverload.maxReps,
                                                 "\(prescription.exercise.id) reps must stay within the safety rail")
                    }
                    XCTAssertTrue(prescription.exercise.equipment.isEmpty, "Zero-Equipment Floor")
                }
            }
        }
    }

    func testNoExerciseRepeatsAcrossBlocks() async throws {
        let library = try await library()
        let workout = assemble(minutes: 30, user: user(), library: library, logs: someHistory())
        let ids = workout.blocks.flatMap { $0.exercises.map { $0.exercise.id } }
        XCTAssertEqual(Set(ids).count, ids.count, "an exercise appeared in more than one block")
    }

    // MARK: - Determinism (content, not ids)

    func testAssemblyIsDeterministic() async throws {
        let library = try await library()
        let user = user()
        let logs = someHistory()
        let first = assemble(minutes: 20, user: user, library: library, logs: logs)
        let signature = structuralSignature(first)
        for _ in 0..<20 {
            let next = assemble(minutes: 20, user: user, library: library, logs: logs)
            XCTAssertEqual(structuralSignature(next), signature, "assembly is not deterministic")
        }
    }

    /// A run-to-run-stable description of a workout's content (the ids vary by design, so this
    /// captures structure, ordering, and targets while ignoring `UUID`s).
    private func structuralSignature(_ workout: Workout) -> String {
        workout.blocks.map { block in
            let items = block.exercises.map { p in
                "\(p.exercise.id):\(p.sets):\(p.reps.map(String.init) ?? "-"):\(p.durationSeconds.map(String.init) ?? "-"):\(p.restSeconds)"
            }.joined(separator: ",")
            return "\(block.category.rawValue)[\(items)]"
        }.joined(separator: "|")
    }

    // MARK: - PRD validation test (intermediate user, some history, 20 minutes)

    func testPRDValidationTwentyMinuteSession() async throws {
        let library = try await library()
        let user = user(level: .intermediate)

        let start = DispatchTime.now()
        let workout = assemble(minutes: 20, user: user, library: library, logs: someHistory())
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        XCTAssertEqual(workout.blocks.first?.category, .warmup, "opens with a warm-up")
        XCTAssertEqual(workout.blocks.last?.category, .cooldown, "closes with a cooldown")

        let planned = SessionAssembly.plannedSeconds(of: workout)
        XCTAssertGreaterThanOrEqual(planned, 19 * 60, "20-min session should total at least 19 min")
        XCTAssertLessThanOrEqual(planned, 21 * 60, "20-min session should total at most 21 min")
        XCTAssertLessThan(elapsedMs, 100, "assembly took \(elapsedMs)ms, over the 100ms budget")
    }
}
