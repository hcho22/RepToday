import XCTest
@testable import RepToday

/// US-007 / US-M05: the cross-cutting strength-primary regression guard.
///
/// One consolidated sweep a future tuning change would have to break loudly. It runs every requested
/// length in `5, 10, 15, 20, 30, 45, 60` on every Training Day across all three generation regimes -
/// **steady-state**, **cold-start** (the First-Week window) and **Return** (the post-gap comeback) - and
/// pins that every generated session:
///
///   1. trains through exactly one strength circuit, every station a strength-pillar movement, and never
///      carries a mobility *middle* block - mobility survives only as the warm-up and cooldown bookends
///      (the originally-reported bug was a 5-minute desk-worker session generated as all stretches);
///   2. stays deterministic and a pure function of the injected `asOf`;
///   3. opens and closes with stretches complementing the day's group (ADR-0018 day-matched bookends);
///   4. treats `sitsLong` as a bookend bias only - toggling it never changes the block structure.
///
/// `BookendComplementSelectionTests` / `SitsLongBookendBiasTests` prove the bookend mechanisms per story
/// and `TrainingDaySessionTests` the slots inside the circuit; this suite re-checks the structural
/// invariants across the whole regime x day x length matrix.
final class StrengthPrimaryRegressionTests: XCTestCase {

    // MARK: - Fixtures

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    /// A cold-start user inside the First-Week window: a desk-worker beginner with a mobility opening bias,
    /// the original bug's profile.
    private var coldStartUser: User {
        var user = TrainingDayFixtures.user(level: .beginner, sitsLong: true)
        user.coldStart = User.ColdStart(sessionsLogged: 1, active: true)
        user.why = User.Why(statement: "", openingBias: .mobility)
        return user
    }

    /// A trained history whose most recent session sits past `ReturnOverride.returnThresholdDays`, so the
    /// next session is a Return, with no active cold-start state.
    private var returnHistory: [WorkoutLog] {
        [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 12)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 10)),
        ]
    }

    private func assemble(
        minutes: Int,
        day: TrainingDay,
        user: User,
        logs: [WorkoutLog] = [],
        policy: SessionPolicy = .default,
        asOf: Date = TrainingDayFixtures.asOf
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            sessionPolicy: policy,
            trainingDay: day,
            asOf: asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    /// A run-to-run-stable description of a workout's content (ids vary by design).
    private func structuralSignature(_ workout: Workout) -> String {
        workout.blocks.map { block in
            let items = block.exercises.map { item in
                "\(item.exercise.id):\(item.sets):\(item.reps.map(String.init) ?? "-"):\(item.durationSeconds.map(String.init) ?? "-"):\(item.restSeconds)"
            }.joined(separator: ",")
            return "\(block.category.rawValue)[\(items)]"
        }.joined(separator: "|")
    }

    // MARK: - The three generation regimes

    private struct Regime {
        let name: String
        let generate: (Int, TrainingDay) -> Workout
    }

    private var regimes: [Regime] {
        [
            // Steady-state: a fresh desk worker past any cold-start window.
            Regime(name: "steady-state") { minutes, day in
                self.assemble(minutes: minutes, day: day, user: TrainingDayFixtures.user(sitsLong: true))
            },
            // Cold-start: the real onboarding seed for a beginner, difficulty-capped.
            Regime(name: "cold-start") { minutes, day in
                self.assemble(
                    minutes: minutes, day: day, user: self.coldStartUser,
                    policy: .seeded(forFitnessLevel: .beginner)
                )
            },
            // Return: a trained user back after a gap.
            Regime(name: "return") { minutes, day in
                self.assemble(minutes: minutes, day: day, user: TrainingDayFixtures.user(), logs: self.returnHistory)
            },
        ]
    }

    // MARK: - Regime preconditions

    /// The three regimes really are distinct engine paths, so a fixture drift cannot make every "mode"
    /// the steady state.
    func testRegimesAreDistinctEnginePaths() {
        XCTAssertTrue(
            ColdStartOverride.isActive(user: coldStartUser, sessionPolicy: .seeded(forFitnessLevel: .beginner)),
            "the cold-start regime must engage the cold-start override"
        )
        XCTAssertTrue(
            ReturnOverride.isReturn(recentLogs: returnHistory, asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar),
            "the Return regime's history must cross the Return threshold"
        )
        let returned = assemble(minutes: 20, day: .legs, user: TrainingDayFixtures.user(), logs: returnHistory)
        XCTAssertTrue(returned.wasReturn, "the Return regime's session must be flagged wasReturn")
        let steady = assemble(minutes: 20, day: .legs, user: TrainingDayFixtures.user(sitsLong: true))
        XCTAssertFalse(steady.wasReturn)
    }

    // MARK: - 1. One strength circuit, never a mobility middle block

    func testEverySessionTrainsThroughOneStrengthCircuitAndNoMobilityMiddleBlock() {
        for regime in regimes {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let workout = regime.generate(minutes, day)
                    let label = "[\(regime.name)] \(day) \(minutes) min"
                    let middle = workout.blocks.filter { $0.category != .warmup && $0.category != .cooldown }

                    XCTAssertEqual(middle.map(\.category), [.strength], "\(label): the training middle is \(middle.map(\.category))")
                    let circuit = middle.flatMap(\.exercises)
                    XCTAssertFalse(circuit.isEmpty, "\(label): an empty circuit")
                    XCTAssertTrue(
                        circuit.allSatisfy { $0.exercise.pillar == .strength },
                        "\(label): a non-strength station \(circuit.map(\.exercise.id))"
                    )
                    XCTAssertEqual(workout.focusPillar, .strength, label)
                    for bookend in workout.blocks where bookend.category == .warmup || bookend.category == .cooldown {
                        XCTAssertTrue(bookend.exercises.allSatisfy { $0.exercise.pillar == .mobility }, label)
                    }
                }
            }
        }
    }

    // MARK: - 2. Determinism and asOf-purity

    func testSweepIsDeterministicAtAFixedAsOf() {
        for regime in regimes {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let first = structuralSignature(regime.generate(minutes, day))
                    for _ in 0..<3 {
                        XCTAssertEqual(
                            structuralSignature(regime.generate(minutes, day)), first,
                            "[\(regime.name)] \(day) \(minutes) min generation is not deterministic"
                        )
                    }
                }
            }
        }
    }

    /// Re-anchoring "now" and the whole history a year later (same relative gaps) produces the identical
    /// session, so nothing in the pipeline reads the wall clock.
    func testGenerationIsAPureFunctionOfTheInjectedAsOf() {
        let calendar = TrainingDayFixtures.calendar
        func session(anchor: Date) -> Workout {
            let logs = [
                TrainingDayFixtures.trainingLog(.push, completedAt: calendar.date(byAdding: .day, value: -3, to: anchor)!),
                TrainingDayFixtures.trainingLog(.pull, completedAt: calendar.date(byAdding: .day, value: -2, to: anchor)!),
            ]
            return SessionAssembly.assemble(
                requestedMinutes: 30, user: TrainingDayFixtures.user(), library: library, recentLogs: logs,
                asOf: anchor, calendar: calendar
            )
        }
        let anchorA = TrainingDayFixtures.asOf
        let anchorB = calendar.date(byAdding: .year, value: 1, to: anchorA)!
        let a = session(anchor: anchorA)
        XCTAssertEqual(a.trainingDay, .legs, "the Rotation reads the logs: Push then Pull leaves Legs")
        XCTAssertEqual(structuralSignature(a), structuralSignature(session(anchor: anchorB)))
    }

    // MARK: - 3. The bookends match the day (ADR-0018)

    /// Every regime leaves the bookends day-matched: each warm-up and cooldown leads with a stretch that
    /// complements the day's group, and every stretch does on a Push or Legs Day. These regimes' users are
    /// all Discipline beginners or intermediates, offered only three pull stretches, so a 30-60 minute
    /// Pull Day's four bookend stretches hold exactly one fallback.
    func testBookendsMatchTheDayAcrossRegimes() throws {
        for regime in regimes {
            for day in TrainingDay.rotation {
                for minutes in [15, 20, 30, 45, 60] {
                    let workout = regime.generate(minutes, day)
                    var fallbacks = 0
                    for category in [ExerciseCategory.warmup, .cooldown] {
                        let label = "[\(regime.name)] \(day) \(minutes) min \(category)"
                        let stretches = try XCTUnwrap(
                            workout.blocks.first { $0.category == category }?.exercises.map(\.exercise),
                            "\(label): missing"
                        )
                        let first = try XCTUnwrap(stretches.first, "\(label): empty")
                        XCTAssertTrue(
                            SessionAssembly.complements(first, anyOf: day.patterns),
                            "\(label) leads with '\(first.id)', which does not complement \(day)"
                        )
                        fallbacks += stretches.filter { !SessionAssembly.complements($0, anyOf: day.patterns) }.count
                    }
                    let label = "[\(regime.name)] \(day) \(minutes) min"
                    XCTAssertEqual(fallbacks, day == .pull && minutes >= 30 ? 1 : 0, label)
                }
            }
        }
    }

    // MARK: - 4. sitsLong is a bookend bias only

    func testSitsLongNeverChangesTheBlockStructure() {
        for day in TrainingDay.rotation {
            for minutes in lengths {
                let desk = assemble(minutes: minutes, day: day, user: TrainingDayFixtures.user(sitsLong: true))
                let general = assemble(minutes: minutes, day: day, user: TrainingDayFixtures.user(sitsLong: false))
                XCTAssertEqual(
                    desk.blocks.map { "\($0.category):\($0.exercises.count)" },
                    general.blocks.map { "\($0.category):\($0.exercises.count)" },
                    "\(day) \(minutes) min: sitsLong changed the block structure"
                )
            }
        }
    }
}
