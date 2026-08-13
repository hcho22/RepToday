import XCTest
@testable import RepToday

/// US-007: the cross-cutting strength-primary regression guard for the "Strength-Primary Sessions"
/// slice (US-001 ... US-005).
///
/// This suite adds **no engine behavior**. It is a single consolidated invariant that a future tuning
/// change would have to break loudly: it sweeps every requested length in
/// `5, 10, 15, 20, 30, 45, 60` across all three generation regimes - **steady-state**, **cold-start**
/// (US-004's First-Week window), and **Return** (US-005's post-gap comeback) - and pins that every
/// generated session:
///
///   1. contains a real `.strength` **training** block (not merely a mobility warm-up), and is never
///      **mobility-led** (the training block owning the most planned time is strength, never mobility);
///   2. holds the strength-primary share bands - a single-focus session's training time is essentially
///      all strength (mobility survives only as the warm-up), and a blend runs strength-dominant inside
///      the US-002/US-003-validated band; and
///   3. stays deterministic and a pure function of the injected `asOf` (no wall-clock read).
///
/// The originally-reported bug this guards against is a 5-minute desk-worker session generated as all
/// stretches. `SessionAssemblyTests`/`PillarBalanceTests` prove the per-story behavior; this suite is
/// the one place a maintainer can see, at a glance, that the invariant holds across the whole matrix -
/// so a change that quietly reintroduces a mobility-only session for some length/mode fails here even
/// if it slipped past a narrower per-story test.
final class StrengthPrimaryRegressionTests: XCTestCase {

    // MARK: - Fixtures (mirrors SessionAssemblyTests so the sweep exercises the real pipeline)

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

    /// The seven lengths swept: two single-focus (5, 10) and five blends (15/20 light, 30 full, 45/60
    /// extended), so every session shape the engine builds is covered.
    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private func user(
        level: FitnessLevel = .intermediate,
        sitsLong: Bool = false
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
                injuries: [],
                typicalAvailableMinutes: 15
            ),
            phase: .discipline,
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

    /// A cold-start user inside the First-Week window (US-004): the shared user plus an active
    /// cold-start state. A desk worker (`sitsLong`) with a mobility bias is the hardest case - the
    /// original bug's profile - so the sweep uses it.
    private func coldStartUser(sitsLong: Bool = true) -> User {
        var user = user(level: .beginner, sitsLong: sitsLong)
        user.coldStart = User.ColdStart(sessionsLogged: 1, active: true)
        user.why = User.Why(statement: "", openingBias: .mobility)
        return user
    }

    /// The cold-start contract the policy carries during the First-Week window (US-E04/US-004): contrast
    /// on, difficulty capped at the gentle end.
    private func coldStartPolicy() -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.coldStartContract = SessionPolicy.ColdStartContract(
            forceContrastSpread: true,
            cappedMaxDifficulty: 2
        )
        return policy
    }

    /// A completed session `daysAgo` training `pillar`, used to build a genuine Return history (a gap
    /// past `returnThresholdDays`) for a user who has trained before.
    private func log(pillar: Pillar, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: .justRight,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "ex-\(pillar.rawValue)-\(daysAgo)",
                    pillar: pillar,
                    movementPattern: pillar == .mobility ? .mobility : (pillar == .primal ? .locomotion : .push),
                    completedSets: [
                        CompletedSet(reps: 12, durationSeconds: nil),
                        CompletedSet(reps: 12, durationSeconds: nil),
                        CompletedSet(reps: 12, durationSeconds: nil),
                    ],
                    skipped: false
                )
            ]
        )
    }

    /// A prior training history whose most recent session sits past `returnThresholdDays` - so the
    /// engine treats the next session as a Return (US-005) - but with no active cold-start state, so
    /// the two overrides do not overlap.
    private func returnHistory() -> [WorkoutLog] {
        [
            log(pillar: .strength, daysAgo: 10),
            log(pillar: .mobility, daysAgo: 17),
        ]
    }

    private func assemble(
        minutes: Int,
        user: User,
        library: [Exercise],
        logs: [WorkoutLog],
        policy: SessionPolicy = .default
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            sessionPolicy: policy,
            asOf: asOf,
            calendar: calendar
        )
    }

    // MARK: - Share helpers (reuse the engine's own work model, as SessionAssemblyTests does)

    /// Planned wall-clock of one materialized block (`Σ sets × workPerSet + (sets - 1) × rest`),
    /// measured with the engine's own per-set work model - the same computation
    /// `SessionAssemblyTests.plannedSeconds(_:)` uses to compare how much time each pillar block owns.
    private func plannedSeconds(_ block: WorkoutBlock) -> Int {
        block.exercises.reduce(0) { sum, p in
            sum + p.sets * SessionAssembly.workSecondsPerSet(of: p) + max(0, p.sets - 1) * p.restSeconds
        }
    }

    /// Planned training seconds per pillar (warm-up and cooldown excluded), keyed by the block's pillar.
    private func trainingSecondsByPillar(_ workout: Workout) -> [Pillar: Int] {
        var totals: [Pillar: Int] = [:]
        for block in workout.blocks where block.category != .warmup && block.category != .cooldown {
            guard let pillar = SessionAssembly.pillar(of: block.category) else { continue }
            totals[pillar, default: 0] += plannedSeconds(block)
        }
        return totals
    }

    /// The pillar of the training block that owns the most planned time - the session's actual lead.
    private func leadingTrainingPillar(_ workout: Workout) -> Pillar? {
        trainingSecondsByPillar(workout).max { $0.value < $1.value }?.key
    }

    /// A run-to-run-stable description of a workout's content (ids vary by design, so this captures
    /// structure, ordering, and targets while ignoring `UUID`s). Mirrors
    /// `SessionAssemblyTests.structuralSignature(_:)`.
    private func structuralSignature(_ workout: Workout) -> String {
        workout.blocks.map { block in
            let items = block.exercises.map { p in
                "\(p.exercise.id):\(p.sets):\(p.reps.map(String.init) ?? "-"):\(p.durationSeconds.map(String.init) ?? "-"):\(p.restSeconds)"
            }.joined(separator: ",")
            return "\(block.category.rawValue)[\(items)]"
        }.joined(separator: "|")
    }

    // MARK: - The three generation regimes

    /// One labelled regime: a name for failure messages plus a closure that generates the session for a
    /// given length. All three are strength-primary by US-001 ... US-005.
    private struct Regime {
        let name: String
        let generate: (Int) -> Workout
    }

    private func regimes(library: [Exercise]) -> [Regime] {
        [
            // Steady-state: a fresh (no-history) desk worker - the originally-reported failure profile -
            // past any cold-start window. Single-focus at 5-10, blend at 11+.
            Regime(name: "steady-state") { minutes in
                self.assemble(minutes: minutes, user: self.user(sitsLong: true), library: library, logs: [])
            },
            // Cold-start: a new user inside the First-Week window (US-004), difficulty-capped but still
            // strength-led.
            Regime(name: "cold-start") { minutes in
                self.assemble(
                    minutes: minutes, user: self.coldStartUser(), library: library,
                    logs: [], policy: self.coldStartPolicy()
                )
            },
            // Return: a user with prior history and a gap past the Return threshold, not in the
            // cold-start window (US-005) - gentle but still strength-led.
            Regime(name: "return") { minutes in
                self.assemble(minutes: minutes, user: self.user(), library: library, logs: self.returnHistory())
            },
        ]
    }

    // MARK: - Regime preconditions (the sweep tests what they claim to test)

    /// Guards that the three regimes really are distinct engine paths: cold-start is active for the
    /// cold-start user, and the Return history is a genuine Return (and not a cold-start) for the
    /// steady/Return user. Without this a silent fixture drift could make every "mode" the steady state.
    func testRegimesAreDistinctEnginePaths() async throws {
        let library = try await library()

        // Cold-start regime: the cold-start override is active.
        XCTAssertTrue(
            ColdStartOverride.isActive(user: coldStartUser(), sessionPolicy: coldStartPolicy()),
            "the cold-start regime must actually engage the cold-start override"
        )

        // Return regime: a genuine Return, and (no cold-start state) not suppressed by cold-start.
        XCTAssertTrue(
            ReturnOverride.isReturn(recentLogs: returnHistory(), asOf: asOf, calendar: calendar),
            "the Return regime's history must cross the Return threshold"
        )
        XCTAssertTrue(
            SessionAssembly.isReturnSession(
                user: user(), recentLogs: returnHistory(), sessionPolicy: .default,
                asOf: asOf, calendar: calendar
            ),
            "the Return regime must resolve to a Return end-to-end (not be suppressed)"
        )
        // And the engine actually stamps it as a Return on the produced session.
        let returned = assemble(minutes: 20, user: user(), library: library, logs: returnHistory())
        XCTAssertTrue(returned.wasReturn, "the Return regime's session must be flagged wasReturn")
    }

    // MARK: - 1. A strength training block in every session, every length, every regime

    func testEverySessionHasAStrengthTrainingBlockAndIsNeverMobilityLed() async throws {
        let library = try await library()
        for regime in regimes(library: library) {
            for minutes in lengths {
                let workout = regime.generate(minutes)

                // A real strength *training* block exists (not just the mobility warm-up).
                XCTAssertTrue(
                    workout.blocks.contains { $0.category == .strength },
                    "[\(regime.name)] \(minutes) min must contain a strength training block"
                )
                let strengthBlocks = workout.blocks.filter { $0.category == .strength }
                XCTAssertTrue(
                    strengthBlocks.allSatisfy { !$0.exercises.isEmpty },
                    "[\(regime.name)] \(minutes) min strength block must not be empty"
                )

                // The session is never mobility-led: the training block owning the most planned time is
                // strength, never mobility. (Extended blends also carry a smaller primal block, and
                // strength still leads it - so the lead is specifically strength.)
                let lead = try XCTUnwrap(
                    leadingTrainingPillar(workout),
                    "[\(regime.name)] \(minutes) min produced no training block"
                )
                XCTAssertNotEqual(lead, .mobility, "[\(regime.name)] \(minutes) min must not be mobility-led")
                XCTAssertEqual(lead, .strength, "[\(regime.name)] \(minutes) min must be strength-led")

                // Single-focus (5-10 min) carries no mobility training block at all - mobility survives
                // only as the warm-up, the exact regression the original all-stretches bug produced.
                if minutes <= 10 {
                    XCTAssertEqual(
                        workout.focusPillar, .strength,
                        "[\(regime.name)] \(minutes) min single-focus must report a strength focus"
                    )
                    XCTAssertFalse(
                        workout.blocks.contains { $0.category == .mobility },
                        "[\(regime.name)] \(minutes) min must have no mobility training block (warm-up only)"
                    )
                }
            }
        }
    }

    // MARK: - 2. Strength-share bands

    /// A single-focus session's training time is essentially all strength (mobility is warm-up only),
    /// and a blend runs strength-dominant inside the US-002/US-003-validated band. Bands, not exact
    /// pins, consistent with `SessionAssemblyTests.testBlendTrainingTimeIsStrengthDominantAtValidationLengths`.
    func testStrengthShareBandsHoldAcrossRegimes() async throws {
        let library = try await library()
        for regime in regimes(library: library) {
            for minutes in lengths {
                let workout = regime.generate(minutes)
                let totals = trainingSecondsByPillar(workout)
                let strengthSeconds = totals[.strength] ?? 0
                let primalSeconds = totals[.primal] ?? 0
                let totalTraining = totals.values.reduce(0, +)
                XCTAssertGreaterThan(totalTraining, 0, "[\(regime.name)] \(minutes) min produced no training time")

                if minutes <= 10 {
                    // Single-focus: no mobility training block, so training time is ~100% strength -
                    // comfortably above the 0.8 strength-primary floor the US-002 blend band centres on.
                    let strengthShare = Double(strengthSeconds) / Double(totalTraining)
                    XCTAssertGreaterThanOrEqual(
                        strengthShare, 0.8,
                        "[\(regime.name)] \(minutes) min single-focus strength share \(strengthShare) fell below the strength-primary floor"
                    )
                } else {
                    // Blend: the **leading strength family** (strength + any dedicated primal block) is
                    // strength-dominant inside the validated band. An extended blend (41-60 min) carves
                    // primal into its own block (US-E02), so strength *alone* is smaller there while the
                    // family still holds the ~0.75-0.80 lead - this measures the family, matching how
                    // `PillarBalanceTests` pins `strength + primal == 0.8` with mobility the 0.2 minority.
                    // A light/full blend (11-40 min) folds primal into strength, so the family share is
                    // just the strength block. Lower bound 0.7 (a genuine mobility accessory is present);
                    // upper bound 0.88 (US-003 widened it from 0.85 as the leaner warm-up routed freed
                    // budget into strength sets).
                    let familyShare = Double(strengthSeconds + primalSeconds) / Double(totalTraining)
                    XCTAssertGreaterThan(
                        totals[.mobility] ?? 0, 0,
                        "[\(regime.name)] \(minutes) min blend must keep a genuine mobility accessory"
                    )
                    XCTAssertGreaterThan(
                        strengthSeconds, primalSeconds,
                        "[\(regime.name)] \(minutes) min blend: strength must lead the strength family (never primal)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        familyShare, 0.7,
                        "[\(regime.name)] \(minutes) min blend strength-family share \(familyShare) fell below the strength-dominant floor"
                    )
                    XCTAssertLessThanOrEqual(
                        familyShare, 0.88,
                        "[\(regime.name)] \(minutes) min blend strength-family share \(familyShare) left a too-thin mobility accessory"
                    )
                }
            }
        }
    }

    /// The story's explicit share check, isolated: the representative blend lengths (20 and 30 min) run
    /// strength-dominant near the ~0.75-0.80 target (inside the validated 0.7-0.88 band), for a
    /// no-history steady-state user - the exact configuration US-002's validation pins.
    func testRepresentativeBlendLengthsSitInTheStrengthTargetBand() async throws {
        let library = try await library()
        for minutes in [20, 30] {
            let workout = assemble(minutes: minutes, user: user(sitsLong: false), library: library, logs: [])
            let totals = trainingSecondsByPillar(workout)
            let strengthShare = Double(totals[.strength] ?? 0) / Double(totals.values.reduce(0, +))
            XCTAssertGreaterThan(totals[.mobility] ?? 0, 0, "\(minutes) min must keep a mobility accessory")
            XCTAssertGreaterThanOrEqual(strengthShare, 0.7, "\(minutes) min strength share \(strengthShare) below band")
            XCTAssertLessThanOrEqual(strengthShare, 0.88, "\(minutes) min strength share \(strengthShare) above band")
        }
    }

    // MARK: - 3. Determinism and asOf-purity stay green (this guard does not weaken them)

    /// Every swept (regime, length) generates byte-identically on repeat at a fixed injected `asOf` -
    /// the structural signature is stable run to run. This reaffirms, across the whole strength-primary
    /// matrix, the determinism `SessionAssemblyTests` and `DeterministicSessionPolicyServiceTests`
    /// already guard; it does not replace or loosen them.
    func testSweepIsDeterministicAtAFixedAsOf() async throws {
        let library = try await library()
        for regime in regimes(library: library) {
            for minutes in lengths {
                let first = structuralSignature(regime.generate(minutes))
                for _ in 0..<5 {
                    XCTAssertEqual(
                        structuralSignature(regime.generate(minutes)), first,
                        "[\(regime.name)] \(minutes) min generation is not deterministic"
                    )
                }
            }
        }
    }

    /// Generation is a pure function of the injected `asOf`: re-anchoring "now" and the whole history to
    /// a different absolute date (same relative gaps) produces the identical session, so nothing in the
    /// pipeline reads the wall clock. Guards the `asOf`-purity the engine's clock-injection depends on.
    func testGenerationIsPureFunctionOfInjectedAsOf() async throws {
        let library = try await library()

        // Two absolute anchors a year apart; the Return history is expressed relative to each anchor, so
        // the only thing that changes is the absolute date fed in.
        func session(anchor: Date) -> Workout {
            let logs = [
                WorkoutLog(
                    id: UUID(), workoutId: UUID(),
                    completedAt: calendar.date(byAdding: .day, value: -10, to: anchor)!,
                    requestedMinutes: 20, durationMinutes: 20, shape: .blend, focusPillar: nil,
                    perceivedDifficulty: .justRight,
                    exercises: [LoggedExercise(
                        id: UUID(), exerciseId: "ex-strength", pillar: .strength,
                        movementPattern: .push,
                        completedSets: [CompletedSet(reps: 12, durationSeconds: nil)], skipped: false
                    )]
                )
            ]
            return SessionAssembly.assemble(
                requestedMinutes: 20, user: user(), library: library, recentLogs: logs,
                asOf: anchor, calendar: calendar
            )
        }

        let anchorA = calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
        let anchorB = calendar.date(from: DateComponents(year: 2027, month: 6, day: 29, hour: 12))!
        XCTAssertEqual(
            structuralSignature(session(anchor: anchorA)),
            structuralSignature(session(anchor: anchorB)),
            "generation must depend only on the injected asOf, not the wall clock"
        )
    }
}
