import XCTest
@testable import RepToday

/// Tests US-004: cold-start first-week days lead strength (kept gentle).
///
/// US-004 originally forced the cold-start lead to strength through `ColdStartOverride.overridePlan`,
/// gated on `coldStartContract.forceContrastSpread`. **Since US-M01 that override is gone**: the
/// strength lead is now *structural* in `SessionAssembly` - every session, in every regime, builds a
/// leading strength block - so there is no lead override left to unit-test in isolation. What still
/// holds, and what this suite pins end-to-end through the real onboarding seed, is the observable
/// contract US-004 promised: a `sitsLong` beginner's first cold-start sessions lead strength (not the
/// mobility days their bias used to force) while the gentleness rail (`cappedMaxDifficulty`) holds. A
/// control run on the neutral `SessionPolicy.default` confirms the cold-start and steady-state leads now
/// agree - both strength (US-001).
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

    /// A desk-worker beginner on cold-start day `sessionsLogged`. `sitsLong == true` is exactly the
    /// single-theme mobility collapse the cold-start strength lead had to override; under US-M01 the
    /// structural strength lead keeps that day on strength regardless. `openingBias` optionally pins the
    /// onboarding opening bias.
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

    // MARK: - The real onboarding seed, end-to-end (US-G01 + US-004)

    /// The PRD validation test, driven by the *actual* onboarding seed rather than a hand-built policy: a
    /// `sitsLong` beginner's first three cold-start sessions all lead strength - not the mobility days
    /// their bias used to force.
    func testSeededContractLeadsStrengthEveryDayEndToEnd() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)

        for day in 0..<3 {
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: day), library: library, policy: policy)
            let focus = try XCTUnwrap(workout.focusPillar, "a single-focus cold-start day must report a focus pillar")
            XCTAssertEqual(focus, .strength, "cold-start day \(day) must lead strength")
            // Mobility survives only as the warm-up: no mobility training block on a cold-start day.
            XCTAssertFalse(
                workout.blocks.contains { $0.category == .mobility },
                "cold-start day \(day) must not carry a mobility training block"
            )
        }
    }

    /// A mobility opening bias does not unseat the cold-start strength lead: the structural lead keeps
    /// every day on strength whatever the onboarding bias says.
    func testColdStartLeadsStrengthDespiteMobilityOpeningBias() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)

        for day in 0..<2 {
            let workout = assemble(
                minutes: 8, user: deskWorker(sessionsLogged: day, openingBias: .mobility), library: library, policy: policy
            )
            XCTAssertEqual(
                workout.focusPillar, .strength,
                "day \(day): a mobility opening bias does not unseat the cold-start strength lead"
            )
        }
    }

    /// The seeded strength-led first week stays gentle: every selected movement is at or below the
    /// cold-start difficulty cap. US-004 changed which pillar leads, never how gentle the day is - the
    /// cap (`cappedMaxDifficulty`) and Start-Seed volume rails are untouched by US-M01.
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

    /// The control that gives the tests above their meaning: the identical desk worker run on the neutral
    /// `SessionPolicy.default` (no cold-start contract, so Step 0 is a no-op) also leads strength every
    /// day (US-001 steady state). Cold start and the steady state agree - both lead strength.
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
