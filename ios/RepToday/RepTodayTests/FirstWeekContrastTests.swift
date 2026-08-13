import XCTest
@testable import RepToday

/// Tests US-004: cold-start first-week days lead strength (kept gentle).
///
/// The mechanism (the Step 0 pillar override) lives in `ColdStartOverride.overridePlan` and the seed
/// that turns it on (`coldStartContract.forceContrastSpread == true`) lives in the onboarding
/// contract (`SessionPolicy.seeded(forFitnessLevel:)`, US-G01). This suite owns the *contract*
/// between them - that the seeded flag now drives a **strength-led** first week rather than the
/// retired First-Week Contrast spread across strength/mobility/primal. Every cold-start day leads
/// strength, even for a desk worker whose `sitsLong` bias used to force the week toward mobility.
///
/// It covers three altitudes:
/// - the pure `ColdStartOverride` rule in isolation (the flag as the on/off switch, single and blend),
/// - the real onboarding seed end-to-end through `SessionAssembly.assemble` (proving the actual
///   seeded contract, not a hand-built one, leads strength), and
/// - a control that a desk worker *without* the flag also leads strength (US-001 steady state), so the
///   override and the steady state now agree: cold start no longer diverts a beginner off strength.
final class FirstWeekContrastTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// A desk-worker beginner on cold-start day `sessionsLogged`. `sitsLong == true` biases every
    /// session toward mobility, which is exactly the single-theme collapse the cold-start strength lead
    /// must override. `openingBias` optionally pins the onboarding opening bias.
    private func deskWorker(
        sessionsLogged: Int,
        active: Bool = true,
        openingBias: Pillar? = nil
    ) -> User {
        var user = User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: .beginner,
                primaryGoal: .stayActive,
                sitsLong: true,
                injuries: [],
                typicalAvailableMinutes: 8
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 0,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
        user.coldStart = User.ColdStart(sessionsLogged: sessionsLogged, active: active)
        user.why = User.Why(statement: "", openingBias: openingBias)
        return user
    }

    private func assemble(minutes: Int, user: User, library: [Exercise], policy: SessionPolicy) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: [],
            sessionPolicy: policy,
            asOf: asOf,
            calendar: calendar
        )
    }

    private func contrastPolicy(spread: Bool) -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.coldStartContract = SessionPolicy.ColdStartContract(forceContrastSpread: spread, cappedMaxDifficulty: 2)
        return policy
    }

    /// The lead (largest-share) pillar of a plan, for asserting a blend's lead.
    private func lead(of plan: PillarPlan) -> Pillar {
        switch plan {
        case .single(let pillar):
            return pillar
        case .blend(let weights):
            let shares: [(Pillar, Double)] = [
                (.strength, weights.strength),
                (.mobility, weights.mobility),
                (.primal, weights.primal),
            ]
            return shares.max { $0.1 < $1.1 }!.0
        }
    }

    // MARK: - The rule in isolation (US-004 override, gated on the US-G01 flag)

    /// Every cold-start day leads strength for a single-focus plan, even though a desk worker's
    /// onboarding bias points squarely at mobility - and every day is the *same* pillar, no rotation.
    func testDeskWorkerSingleFocusLeadsStrengthEveryDay() {
        let biasedPlan = PillarPlan.single(.mobility) // what a desk worker's staleness would pick every day
        for day in 0..<5 {
            let plan = ColdStartOverride.overridePlan(
                biasedPlan, user: deskWorker(sessionsLogged: day), sessionPolicy: contrastPolicy(spread: true)
            )
            XCTAssertEqual(plan, .single(.strength), "day \(day) must lead strength")
        }
    }

    /// `forceContrastSpread` is the switch: with it on, a desk worker's mobility-biased single-focus
    /// plan is rewritten to lead strength; with it off, the same plan passes through untouched (so a
    /// desk worker's staleness bias would persist). This is the exact contract US-G01 seeds on.
    func testForceContrastSpreadFlagDrivesTheOverride() {
        let biasedPlan = PillarPlan.single(.mobility)

        // Flag on: the mobility bias is overridden to strength.
        let flagOn = ColdStartOverride.overridePlan(
            biasedPlan, user: deskWorker(sessionsLogged: 1), sessionPolicy: contrastPolicy(spread: true)
        )
        XCTAssertEqual(flagOn, .single(.strength), "with the flag on, cold start leads strength")

        // Flag off: the biased plan is a no-op passthrough - mobility persists.
        let flagOff = ColdStartOverride.overridePlan(
            biasedPlan, user: deskWorker(sessionsLogged: 1), sessionPolicy: contrastPolicy(spread: false)
        )
        XCTAssertEqual(flagOff, biasedPlan, "with the flag off, the cold-start lead override is a no-op")
    }

    /// A blend day leads strength too: a desk worker's mobility-led short blend is re-pointed so
    /// strength owns the largest share, every day, whatever duration the user picks.
    func testBlendDaysLeadStrength() {
        let policy = contrastPolicy(spread: true)
        // A mobility-led short blend, the desk-worker default.
        let biasedBlend = PillarPlan.blend(PillarWeights(strength: 0.4, mobility: 0.6, primal: 0))

        for day in 0..<4 {
            let plan = ColdStartOverride.overridePlan(
                biasedBlend, user: deskWorker(sessionsLogged: day), sessionPolicy: policy
            )
            XCTAssertEqual(lead(of: plan), .strength, "day \(day): a blend must lead strength")
        }
    }

    /// `favoring(.strength)` preserves the multiset of shares - the emphasis is reordered, never a
    /// pillar starved - so a strength-led blend still sums to 1 and keeps every pillar's floor.
    func testBlendLeadPreservesShareMultiset() {
        let biasedBlend = PillarWeights(strength: 0.4, mobility: 0.6, primal: 0)
        let plan = ColdStartOverride.overridePlan(
            .blend(biasedBlend), user: deskWorker(sessionsLogged: 0), sessionPolicy: contrastPolicy(spread: true)
        )
        guard case .blend(let weights) = plan else { return XCTFail("expected a blend") }
        XCTAssertEqual(weights.strength, 0.6, accuracy: 1e-9, "strength takes the largest share")
        XCTAssertEqual(weights.mobility, 0.4, accuracy: 1e-9, "mobility keeps the other share")
        XCTAssertEqual(weights.primal, 0, accuracy: 1e-9)
        XCTAssertEqual(weights.strength + weights.mobility + weights.primal, 1, accuracy: 1e-9)
    }

    /// The lead is a pure function of the inputs: the same day resolves to strength every time.
    func testStrengthLeadIsDeterministicGivenInputs() {
        for day in 0..<6 {
            for _ in 0..<10 {
                let plan = ColdStartOverride.overridePlan(
                    .single(.mobility), user: deskWorker(sessionsLogged: day), sessionPolicy: contrastPolicy(spread: true)
                )
                XCTAssertEqual(plan, .single(.strength), "day \(day)'s lead must be deterministic")
            }
        }
    }

    // MARK: - The real onboarding seed, end-to-end (US-G01 + US-004)

    /// The PRD validation test, driven by the *actual* onboarding seed rather than a hand-built
    /// policy: a `sitsLong` beginner's first three cold-start sessions all lead strength - not the
    /// mobility days their bias used to force.
    func testSeededContractLeadsStrengthEveryDayEndToEnd() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)

        for day in 0..<3 {
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: day), library: library, policy: policy)
            let focus = try XCTUnwrap(workout.focusPillar, "a single-focus cold-start day must report a focus pillar")
            XCTAssertEqual(focus, .strength, "cold-start day \(day) must lead strength")
        }
    }

    /// The seeded strength-led first week stays gentle: every selected strength movement is at or
    /// below the cold-start difficulty cap. US-004 changes which pillar leads, never how gentle the
    /// day is - the cap (`cappedMaxDifficulty`) and Start-Seed volume rails are untouched.
    func testSeededStrengthLeadStaysUnderTheDifficultyCap() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let cap = try XCTUnwrap(policy.coldStartContract?.cappedMaxDifficulty)

        for day in 0..<3 {
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: day), library: library, policy: policy)
            for block in workout.blocks {
                for item in block.exercises {
                    XCTAssertLessThanOrEqual(
                        item.exercise.difficulty, cap,
                        "day \(day): \(item.exercise.displayName) exceeds the cold-start difficulty cap"
                    )
                }
            }
        }
    }

    /// The control that gives the tests above their meaning: the identical desk worker run on the
    /// neutral `SessionPolicy.default` (no cold-start contract, so Step 0 is a no-op) also leads
    /// strength every day (US-001 steady state). Cold start and the steady state now agree - the
    /// override no longer diverts a beginner off strength, it keeps them on it while the window is open.
    func testWithoutTheContractADeskWorkerAlsoLeadsStrength() async throws {
        let library = try await library()

        for day in 0..<4 {
            // Cold-start still "active" on the user, but the policy carries no contract, so the gate is off.
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: day), library: library, policy: .default)
            let focus = try XCTUnwrap(workout.focusPillar)
            XCTAssertEqual(focus, .strength, "without the contract a desk worker's single-focus week is all-strength (US-001)")
        }
    }
}
