import XCTest
@testable import FitSnack

/// Tests the minimal v6 onboarding flow's view model (US-I01).
///
/// Coverage mirrors the PRD acceptance criteria:
/// - the collected answers build a `User` with `why`, the seeded `duration`, and a fresh `coldStart`;
/// - the one duration answer seeds both `defaultMinutes` and `onboardingSeedMinutes`;
/// - `finish()` saves the user and seeds a cold-start `SessionPolicy` (capped Starting Difficulty,
///   First-Week Contrast) that reads back through the policy service;
/// - step navigation and the name gate behave; a save failure surfaces without trapping the flow.
final class OnboardingViewModelTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 760_000_000)

    private func makeViewModel(
        userService: any UserServiceProtocol = MockUserService(),
        policyService: any SessionPolicyServiceProtocol = MockSessionPolicyService()
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            userService: userService,
            sessionPolicyService: policyService,
            userIdentifier: { "onboarding-test-user" },
            now: { self.fixedDate }
        )
    }

    /// Fill every answer so `buildUser`/`finish` have realistic input.
    private func fillAnswers(_ vm: OnboardingViewModel) {
        vm.displayName = "  Riley  "
        vm.age = 34
        vm.sex = .female
        vm.heightCm = 168
        vm.weightKg = 62
        vm.fitnessLevel = .beginner
        vm.whyStatement = "  get on the floor with my grandkids  "
        vm.sitsLong = true
        vm.selectedInjuries = [.knees, .lowerBack]
        vm.durationMinutes = 15
    }

    // MARK: - buildUser mapping

    func testBuildUserMapsAnswers() {
        let vm = makeViewModel()
        fillAnswers(vm)

        let user = vm.buildUser()

        XCTAssertEqual(user.id, "onboarding-test-user")
        XCTAssertEqual(user.displayName, "Riley", "name is trimmed")
        XCTAssertEqual(user.createdAt, fixedDate)
        XCTAssertEqual(user.phase, .discipline)
        XCTAssertEqual(user.profile.age, 34)
        XCTAssertEqual(user.profile.sex, .female)
        XCTAssertEqual(user.profile.fitnessLevel, .beginner)
        XCTAssertTrue(user.profile.sitsLong)
        XCTAssertEqual(user.why.statement, "get on the floor with my grandkids", "why is trimmed")
        XCTAssertNil(user.why.openingBias, "the minimal flow states no opening bias")
    }

    /// The one duration answer seeds both the Ready-Screen default and the immutable onboarding seed.
    func testDurationSeedsBothFields() {
        let vm = makeViewModel()
        fillAnswers(vm)
        vm.durationMinutes = 20

        let user = vm.buildUser()
        XCTAssertEqual(user.duration.defaultMinutes, 20)
        XCTAssertEqual(user.duration.onboardingSeedMinutes, 20)
        XCTAssertNil(user.duration.completedDurationEWMA, "no completed history at onboarding")
        XCTAssertEqual(user.profile.typicalAvailableMinutes, 20)
    }

    /// Cold-start starts fresh: active, nothing logged - the engine retires it after the handoff.
    func testColdStartStartsFresh() {
        let vm = makeViewModel()
        fillAnswers(vm)

        let user = vm.buildUser()
        XCTAssertTrue(user.coldStart.active)
        XCTAssertEqual(user.coldStart.sessionsLogged, 0)
    }

    /// Selected injuries become sorted engine tags on the profile.
    func testInjuriesBecomeSortedTags() {
        let vm = makeViewModel()
        fillAnswers(vm)
        vm.selectedInjuries = [.shoulders, .knees]

        let user = vm.buildUser()
        XCTAssertEqual(user.profile.injuries, ["knees", "shoulders"].sorted())
    }

    // MARK: - finish (save + seed)

    /// `finish()` saves the built user and reads back through the user service.
    func testFinishSavesUser() async throws {
        let users = MockUserService()
        let vm = makeViewModel(userService: users)
        fillAnswers(vm)

        let ok = await vm.finish()
        XCTAssertTrue(ok)

        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "onboarding-test-user")
        XCTAssertEqual(saved?.duration.defaultMinutes, 15)
        XCTAssertNil(vm.errorMessage)
    }

    /// `finish()` seeds a cold-start policy that persists and reads back with a contract capped from
    /// the user's fitness level - so the engine's Step 0 overrides apply from the first session.
    func testFinishSeedsColdStartPolicy() async throws {
        let users = MockUserService()
        let store = InMemorySessionPolicyStore()
        let policyService = DeterministicSessionPolicyService(
            store: store,
            exerciseService: OnboardingStubExerciseService(),
            userService: users
        )
        let vm = makeViewModel(userService: users, policyService: policyService)
        fillAnswers(vm)
        vm.fitnessLevel = .beginner

        let finished = await vm.finish()
        XCTAssertTrue(finished)

        let saved = try await users.currentUser()!
        let policy = try await policyService.currentPolicy(for: saved)
        XCTAssertNotNil(policy.coldStartContract)
        XCTAssertEqual(policy.coldStartContract?.forceContrastSpread, true)
        XCTAssertEqual(policy.coldStartContract?.cappedMaxDifficulty,
                       SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: .beginner))
    }

    /// A save failure surfaces a message, returns false, and leaves the flow in place to retry.
    func testFinishFailureSurfacesErrorWithoutTrapping() async {
        let vm = makeViewModel(userService: FailingUserService())
        fillAnswers(vm)

        let ok = await vm.finish()
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isFinishing, "the in-flight flag resets after failure")
    }

    // MARK: - Navigation

    func testAdvanceAndGoBackWalkTheSteps() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.isFirstStep)
        XCTAssertEqual(vm.step, .welcome)

        vm.advance()
        XCTAssertEqual(vm.step, .basics)
        vm.goBack()
        XCTAssertEqual(vm.step, .welcome)
        vm.goBack()  // no-op at the first step
        XCTAssertEqual(vm.step, .welcome)
    }

    /// The basics step gates advance until a name is entered; every other step is always ready, so
    /// the flow never opens the Ready Screen onto a blocked Start.
    func testCanAdvanceRequiresNameOnBasics() {
        let vm = makeViewModel()
        vm.advance()  // -> basics
        XCTAssertEqual(vm.step, .basics)
        XCTAssertFalse(vm.canAdvance, "no name yet")

        vm.displayName = "Riley"
        XCTAssertTrue(vm.canAdvance)

        vm.displayName = "   "
        XCTAssertFalse(vm.canAdvance, "whitespace-only name does not count")
    }

    func testDurationStepIsAlwaysReady() {
        let vm = makeViewModel()
        // Walk to the last step.
        for _ in OnboardingViewModel.Step.allCases.dropFirst() { vm.advance() }
        XCTAssertEqual(vm.step, .duration)
        XCTAssertTrue(vm.isLastStep)
        XCTAssertTrue(vm.canAdvance, "a duration is preselected; finish is never gated")
    }
}

// MARK: - Test doubles

/// A user service whose `save` always throws, to exercise the failure path.
private struct FailingUserService: UserServiceProtocol {
    struct SaveError: Error {}
    func currentUser() async throws -> User? { nil }
    func save(_ user: User) async throws { throw SaveError() }
    func deleteCurrentUser() async throws {}
}

/// A minimal, empty-library exercise service so the deterministic policy service stays hermetic in
/// the seeding test (seeding never reads the library, but the service requires one).
private struct OnboardingStubExerciseService: ExerciseServiceProtocol {
    func exercises() async throws -> [Exercise] { [] }
    func exercise(id: String) async throws -> Exercise? { nil }
    func exercises(for pillar: Pillar) async throws -> [Exercise] { [] }
    func exercises(for movementPattern: MovementPattern) async throws -> [Exercise] { [] }
    func exercises(for phase: Phase) async throws -> [Exercise] { [] }
    func exercises(inDifficultyRange range: ClosedRange<Int>) async throws -> [Exercise] { [] }
    func nextInChain(after id: String) async throws -> Exercise? { nil }
}
