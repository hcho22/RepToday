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

    // MARK: - Identity (US-N01)

    /// With no auth service wired, identity falls back to the local identifier and the sign-in
    /// affordance is not offered - the offline-first core loop is never gated on Apple.
    func testNoAuthServiceFallsBackToLocalIdentifier() async throws {
        let users = MockUserService()
        let vm = makeViewModel(userService: users)
        fillAnswers(vm)
        XCTAssertFalse(vm.canSignInWithApple)

        let finished = await vm.finish()
        XCTAssertTrue(finished)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "onboarding-test-user", "the local fallback keys the record")
    }

    /// A previously-persisted Sign in with Apple identity keys the user record without any in-flow
    /// sign-in - `finish()` reads it from the auth service and keys by it.
    func testFinishKeysUserByPersistedAppleIdentifier() async throws {
        let users = MockUserService()
        let vm = OnboardingViewModel(
            userService: users,
            sessionPolicyService: MockSessionPolicyService(),
            authService: MockAuthService(userIdentifier: "apple-persisted"),
            userIdentifier: { "local-fallback" },
            now: { self.fixedDate }
        )
        fillAnswers(vm)

        let finished = await vm.finish()
        XCTAssertTrue(finished)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "apple-persisted", "the persisted Apple identifier keys the record")
    }

    /// Signing in with Apple during the flow records the returned identifier and keys the user by it.
    func testSignInWithAppleKeysUserByReturnedIdentifier() async throws {
        let users = MockUserService()
        let vm = OnboardingViewModel(
            userService: users,
            sessionPolicyService: MockSessionPolicyService(),
            authService: MockAuthService(),
            userIdentifier: { "local-fallback" },
            now: { self.fixedDate }
        )
        fillAnswers(vm)
        XCTAssertTrue(vm.canSignInWithApple)

        await vm.signInWithApple()
        XCTAssertEqual(vm.signedInIdentifier, "mock-apple-user")
        XCTAssertFalse(vm.canSignInWithApple, "no re-sign-in once signed in")

        let finished = await vm.finish()
        XCTAssertTrue(finished)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "mock-apple-user")
    }

    /// A failed sign-in is swallowed (non-gating): no identifier is recorded and `finish()` falls
    /// back to the local identifier, so the first session is never blocked.
    func testSignInFailureFallsBackToLocalIdentifier() async throws {
        let users = MockUserService()
        let vm = OnboardingViewModel(
            userService: users,
            sessionPolicyService: MockSessionPolicyService(),
            authService: FailingAuthService(),
            userIdentifier: { "onboarding-test-user" },
            now: { self.fixedDate }
        )
        fillAnswers(vm)

        await vm.signInWithApple()
        XCTAssertNil(vm.signedInIdentifier, "a failed sign-in records nothing")

        let finished = await vm.finish()
        XCTAssertTrue(finished)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "onboarding-test-user", "identity falls back to the local identifier")
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

/// An auth service whose `signInWithApple()` always fails, to prove sign-in is non-gating.
private struct FailingAuthService: AuthServiceProtocol {
    func currentUserIdentifier() async throws -> String? { nil }
    func signInWithApple() async throws -> String { throw AuthError.failed("stub failure") }
    func signOut() async throws {}
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
