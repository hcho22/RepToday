import XCTest
@testable import FitSnack

/// Tests US-G02: First-Week Contrast enforcement.
///
/// The mechanism (the Step 0 pillar rotation) lives in `ColdStartOverride` (US-E04) and the seed
/// that turns it on (`coldStartContract.forceContrastSpread == true`) lives in the onboarding
/// contract (`SessionPolicy.seeded(forFitnessLevel:)`, US-G01). This suite owns the *contract*
/// between them - that the seeded flag actually drives a visible strength/mobility/primal spread
/// across the first week, no pillar repeating back-to-back, even for a desk worker whose `sitsLong`
/// bias would otherwise collapse the week into all-mobility.
///
/// It covers three altitudes:
/// - the pure `ColdStartOverride` rule in isolation (rotation + the flag as the on/off switch),
/// - the real onboarding seed end-to-end through `SessionAssembly.assemble` (proving the actual
///   seeded contract, not a hand-built one, enforces the spread), and
/// - a control that a desk worker *without* the flag collapses to a single pillar - so the spread is
///   demonstrably produced by First-Week Contrast, not by staleness.
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
    /// session toward mobility, which is exactly the single-theme collapse First-Week Contrast must
    /// override. `openingBias` optionally pins where the rotation opens.
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

    /// The lead (largest-share) pillar of a blend plan, for asserting a blend's contrast.
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

    // MARK: - The rule in isolation (US-E04 mechanism, gated on the US-G01 flag)

    /// The pure rotation spans all three pillars with no back-to-back repeat across the first week,
    /// even though a desk worker's onboarding bias points squarely at mobility.
    func testDeskWorkerRotationSpansPillarsWithNoRepeat() {
        var pillars: [Pillar] = []
        for day in 0..<5 {
            pillars.append(ColdStartOverride.contrastPillar(user: deskWorker(sessionsLogged: day), available: Pillar.allCases))
        }
        XCTAssertEqual(Set(pillars).count, 3, "the first week must visibly span strength, mobility, and primal")
        for index in 1..<pillars.count {
            XCTAssertNotEqual(pillars[index], pillars[index - 1], "no pillar may repeat back-to-back")
        }
    }

    /// `forceContrastSpread` is the switch: with it on, a desk worker's mobility-biased single-focus
    /// plan is rewritten onto the rotation; with it off, the same plan passes through untouched (so a
    /// desk worker would collapse to all-mobility). This is the exact contract US-G01 seeds on.
    func testForceContrastSpreadFlagDrivesTheOverride() {
        let biasedPlan = PillarPlan.single(.mobility) // what a desk worker's staleness would pick every day

        func policy(spread: Bool) -> SessionPolicy {
            var policy = SessionPolicy.default
            policy.coldStartContract = SessionPolicy.ColdStartContract(forceContrastSpread: spread, cappedMaxDifficulty: 2)
            return policy
        }

        // Flag on: day 1 rotates off mobility.
        let dayOne = ColdStartOverride.overridePlan(
            biasedPlan, template: .singleFocus, user: deskWorker(sessionsLogged: 1), sessionPolicy: policy(spread: true)
        )
        XCTAssertNotEqual(lead(of: dayOne), .mobility, "with the flag on, the rotation overrides the mobility bias")

        // Flag off: the biased plan is a no-op passthrough - mobility persists.
        let flagOff = ColdStartOverride.overridePlan(
            biasedPlan, template: .singleFocus, user: deskWorker(sessionsLogged: 1), sessionPolicy: policy(spread: false)
        )
        XCTAssertEqual(flagOff, biasedPlan, "with the flag off, First-Week Contrast is a no-op")
    }

    /// Contrast is enforced on blend days too: a desk worker's short-blend lead alternates rather
    /// than staying on mobility, so the spread is felt whatever duration the user picks.
    func testBlendDaysAlsoAlternateTheLeadPillar() {
        var policy = SessionPolicy.default
        policy.coldStartContract = SessionPolicy.ColdStartContract(forceContrastSpread: true, cappedMaxDifficulty: 2)
        // A mobility-led short blend, the desk-worker default.
        let biasedBlend = PillarPlan.blend(PillarWeights(strength: 0.4, mobility: 0.6, primal: 0))

        var leads: [Pillar] = []
        for day in 0..<4 {
            let plan = ColdStartOverride.overridePlan(
                biasedBlend, template: .blendLight, user: deskWorker(sessionsLogged: day), sessionPolicy: policy
            )
            leads.append(lead(of: plan))
        }
        XCTAssertGreaterThan(Set(leads).count, 1, "a blend week must not stay on one lead pillar")
        for index in 1..<leads.count {
            XCTAssertNotEqual(leads[index], leads[index - 1], "no blend lead may repeat back-to-back")
        }
    }

    /// The spread is a pure function of the onboarding inputs: the same day resolves to the same
    /// pillar every time.
    func testSpreadIsDeterministicGivenOnboardingInputs() {
        for day in 0..<6 {
            let first = ColdStartOverride.contrastPillar(user: deskWorker(sessionsLogged: day), available: Pillar.allCases)
            for _ in 0..<10 {
                XCTAssertEqual(
                    ColdStartOverride.contrastPillar(user: deskWorker(sessionsLogged: day), available: Pillar.allCases),
                    first, "day \(day)'s pillar must be deterministic"
                )
            }
        }
    }

    // MARK: - The real onboarding seed, end-to-end (US-G01 + US-E04)

    /// The PRD validation test, driven by the *actual* onboarding seed rather than a hand-built
    /// policy: a `sitsLong` beginner's first four cold-start sessions span at least two pillars with
    /// no back-to-back repeat - not four mobility days.
    func testSeededContractSpreadsTheFirstWeekEndToEnd() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)

        var focus: [Pillar] = []
        for day in 0..<4 {
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: day), library: library, policy: policy)
            focus.append(try XCTUnwrap(workout.focusPillar, "a single-focus cold-start day must report a focus pillar"))
        }
        XCTAssertGreaterThan(Set(focus).count, 1, "the seeded first week must span more than one pillar")
        for index in 1..<focus.count {
            XCTAssertNotEqual(focus[index], focus[index - 1], "no pillar may repeat back-to-back in the seeded first week")
        }
    }

    /// The control that gives the test above its meaning: the identical desk worker run on the neutral
    /// `SessionPolicy.default` (no cold-start contract, so Step 0 is a no-op) collapses to a single
    /// pillar every day. The spread above is therefore produced by First-Week Contrast, not staleness.
    func testWithoutTheContractADeskWorkerCollapsesToOnePillar() async throws {
        let library = try await library()

        var focus: [Pillar] = []
        for day in 0..<4 {
            // Cold-start still "active" on the user, but the policy carries no contract, so the gate is off.
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: day), library: library, policy: .default)
            focus.append(try XCTUnwrap(workout.focusPillar))
        }
        XCTAssertEqual(Set(focus), [.mobility], "without First-Week Contrast a desk worker's week collapses to all-mobility")
    }
}
