import XCTest
@testable import RepToday

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
        vm.heightFeet = 5
        vm.heightInches = 6
        vm.weightPounds = 137
        vm.fitnessLevel = .beginner
        vm.whyStatement = "  get on the floor with my grandkids  "
        vm.sitsLong = true
        vm.selectedInjuries = [.knees, .back]
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

    // MARK: - Imperial in, metric stored (US-O04)

    /// The PRD's own numbers: the user types 5 ft 7 in and 165 lb, the persisted profile is metric.
    func testImperialAnswersArePersistedAsMetric() {
        let vm = makeViewModel()
        fillAnswers(vm)
        vm.heightFeet = 5
        vm.heightInches = 7
        vm.weightPounds = 165

        let profile = vm.buildUser().profile

        XCTAssertEqual(profile.heightCm, 170.18, accuracy: 0.01, "5 ft 7 in is ~170 cm")
        XCTAssertEqual(profile.weightKg, 74.84, accuracy: 0.01, "165 lb is ~74.8 kg")
    }

    /// The defaults open somewhere plausible for a US adult - and are *not* the values the validation
    /// test types, so a conversion that silently ignored its input could not pass by coincidence.
    func testDefaultsAreUSSensibleAndNotTheTestedValues() {
        let vm = makeViewModel()

        XCTAssertEqual(vm.heightFeet, 5)
        XCTAssertEqual(vm.heightInches, 8)
        XCTAssertEqual(vm.weightPounds, 175)
        XCTAssertFalse(
            vm.heightInches == 7 && vm.weightPounds == 165,
            "the defaults must differ from the acceptance-criteria input, else the mapping is untested"
        )
    }

    /// The single height control writes both parts, and the split it leaves behind is always
    /// normalized - `5 ft 12 in` is unreachable.
    func testHeightTotalInchesNormalizesTheFeetInchesSplit() {
        let vm = makeViewModel()

        vm.heightTotalInches = 67
        XCTAssertEqual(vm.heightFeet, 5)
        XCTAssertEqual(vm.heightInches, 7)

        vm.heightTotalInches = 72
        XCTAssertEqual(vm.heightFeet, 6)
        XCTAssertEqual(vm.heightInches, 0)

        vm.heightFeet = 5
        vm.heightInches = 11
        XCTAssertEqual(vm.heightTotalInches, 71, "the parts read back as one number")
    }

    /// The derived metric values track the imperial answers with no separate state to fall out of sync.
    func testMetricValuesAreDerivedFromTheImperialAnswers() {
        let vm = makeViewModel()

        vm.heightTotalInches = 70
        vm.weightPounds = 200
        XCTAssertEqual(vm.heightCm, 177.8, accuracy: 0.001)
        XCTAssertEqual(vm.weightKg, 90.718, accuracy: 0.001)

        vm.heightTotalInches = 60
        vm.weightPounds = 120
        XCTAssertEqual(vm.heightCm, 152.4, accuracy: 0.001)
        XCTAssertEqual(vm.weightKg, 54.431, accuracy: 0.001)
    }

    /// End-to-end past the boundary: the HealthKit energy estimate prices the session off the
    /// onboarded weight in *kilograms*. Reading it as pounds would inflate every calorie written to
    /// Health by ~2.2x, and nothing downstream would flag it - so the unit is pinned here.
    func testHealthKitEnergyUsesKilogramsFromTheOnboardedWeight() {
        let vm = makeViewModel()
        fillAnswers(vm)
        vm.weightPounds = 165

        let user = vm.buildUser()
        let completedAt = Date(timeIntervalSinceReferenceDate: 760_000_000)
        let log = WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: completedAt,
            requestedMinutes: 60,
            durationMinutes: 60,
            wasReturn: false,
            shape: .blend,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "push_standard",
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: false
                )
            ]
        )

        let sample = HealthKitWorkoutSample.from(
            log: log,
            user: user,
            metValuesByExerciseId: ["push_standard": 5]
        )

        // 5 MET x 74.8427 kg x 1 h.
        XCTAssertEqual(sample.energyKilocalories, 374.21, accuracy: 0.05)
        XCTAssertLessThan(
            sample.energyKilocalories,
            5 * 165,
            "the estimate must not be reading the raw pound value as kilograms"
        )
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

    // MARK: - Identity and "Save your plan" (US-AU02)

    /// A new user's record is keyed by a local id: the account owns the data on the server, so the key
    /// never has to change when the user signs in on another phone.
    func testFinishKeysUserByLocalIdentifier() async throws {
        let users = MockUserService()
        let vm = makeViewModel(userService: users)
        fillAnswers(vm)

        let finished = await vm.finish()
        XCTAssertTrue(finished)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "onboarding-test-user", "the local id keys the record")
    }

    /// Signing in to an account with no plan creates the plan from the answers.
    func testSignInToANewAccountCreatesThePlan() async throws {
        let users = MockUserService()
        let policies = RecordingSessionPolicyService()
        let restorer = StubAccountRestorer(result: .success([]))
        let vm = OnboardingViewModel(
            userService: users,
            sessionPolicyService: policies,
            accountRestorer: restorer,
            userIdentifier: { "new-user" },
            now: { self.fixedDate }
        )
        fillAnswers(vm)

        let completion = try await vm.completeSignIn(as: Self.identity)
        XCTAssertEqual(completion, .created)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.id, "new-user")
        XCTAssertEqual(policies.seededUserIds, ["new-user"], "the cold-start policy is seeded for the new plan")
        let restoreCalls = await restorer.calls
        XCTAssertEqual(restoreCalls, 1, "the account is checked before anything is written")
    }

    /// Signing in to an account that already holds a plan - the same person on a new phone - brings it
    /// back; the answers given in this onboarding are not saved over it and no new policy is seeded.
    func testSignInToAnExistingAccountRestoresItsPlan() async throws {
        let users = MockUserService()
        let policies = RecordingSessionPolicyService()
        let restored = MockPersistence.sampleUser
        let restorer = StubAccountRestorer(result: .success([.profile, .workoutLog])) {
            try await users.save(restored)
        }
        let analytics = MockAnalyticsService()
        let vm = OnboardingViewModel(
            userService: users,
            sessionPolicyService: policies,
            accountRestorer: restorer,
            analytics: analytics,
            userIdentifier: { "would-be-new-user" },
            now: { self.fixedDate }
        )
        vm.onboardingStarted()
        fillAnswers(vm)

        let completion = try await vm.completeSignIn(as: Self.identity)
        XCTAssertEqual(completion, .restored)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved, restored, "the account's plan is what the phone now holds")
        XCTAssertTrue(policies.seededUserIds.isEmpty, "a restored plan keeps its own policy")
        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.onboardingStarted, .onboardingCompleted])
    }

    /// When the account cannot be reached, nothing is saved, so a returning user's plan is never
    /// overwritten by a fresh one; the user can try again.
    func testAnUnreachableAccountSavesNothing() async throws {
        let users = MockUserService()
        let policies = RecordingSessionPolicyService()
        let vm = OnboardingViewModel(
            userService: users,
            sessionPolicyService: policies,
            accountRestorer: StubAccountRestorer(result: .failure(SyncRemoteError.unreachable)),
            userIdentifier: { "new-user" },
            now: { self.fixedDate }
        )
        fillAnswers(vm)

        do {
            _ = try await vm.completeSignIn(as: Self.identity)
            XCTFail("an unreachable account must not finish onboarding")
        } catch let error as OnboardingViewModel.CompletionError {
            XCTAssertEqual(error, .accountUnreachable)
        }
        let saved = try await users.currentUser()
        XCTAssertNil(saved)
        XCTAssertTrue(policies.seededUserIds.isEmpty)
    }

    /// A build with no account backend creates the plan on the phone.
    func testSignInWithNoAccountBackendCreatesThePlan() async throws {
        let users = MockUserService()
        let vm = makeViewModel(userService: users)
        fillAnswers(vm)
        let completion = try await vm.completeSignIn(as: Self.identity)
        XCTAssertEqual(completion, .created)
        let saved = try await users.currentUser()
        XCTAssertNotNil(saved)
    }

    private static let identity = AccountIdentity(userId: "user_123", email: "riley@example.com", method: .email)

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
        while vm.step != .duration { vm.advance() }
        XCTAssertTrue(vm.canAdvance, "a duration is preselected; the flow is never gated on it")
    }

    /// "Save your plan" is the last step, and signing in is the only way past it (decision 23).
    func testSaveYourPlanIsTheRequiredLastStep() {
        let vm = makeViewModel()
        vm.displayName = "Riley"
        for _ in OnboardingViewModel.Step.allCases.dropFirst() { vm.advance() }
        XCTAssertEqual(vm.step, .saveYourPlan)
        XCTAssertTrue(vm.isLastStep)
        XCTAssertFalse(vm.canAdvance, "there is no Continue past sign-in")
        XCTAssertEqual(OnboardingViewModel.Step.allCases.last, .saveYourPlan)
        XCTAssertEqual(
            OnboardingViewModel.Step.allCases.firstIndex(of: .saveYourPlan),
            OnboardingViewModel.Step.allCases.firstIndex(of: .duration).map { $0 + 1 },
            "sign-in comes straight after the onboarding answers"
        )
    }

    // MARK: - Onboarding funnel telemetry (US-T08)

    /// An advanceable clock so a test can pin distinct instants to `onboarding_started` and the
    /// `finish()` that emits `onboarding_completed`, and assert the exact `elapsed_seconds`.
    private final class MutableClock {
        var now: Date
        init(_ start: Date) { now = start }
        func advance(_ interval: TimeInterval) { now += interval }
    }

    private func makeTelemetryViewModel(
        analytics: any AnalyticsServiceProtocol,
        clock: MutableClock,
        userService: any UserServiceProtocol = MockUserService()
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            userService: userService,
            sessionPolicyService: MockSessionPolicyService(),
            analytics: analytics,
            userIdentifier: { "onboarding-telemetry-user" },
            now: { clock.now }
        )
    }

    /// `onboardingStarted()` emits exactly one `onboarding_started` with no properties.
    func testOnboardingStartedEmitsOnceWithNoProperties() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(fixedDate)
        let vm = makeTelemetryViewModel(analytics: analytics, clock: clock)

        vm.onboardingStarted()

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.onboardingStarted])
        XCTAssertTrue(events[0].properties.isEmpty, "onboarding_started carries no properties")
    }

    /// A re-`onAppear` within the same flow must not double-fire `onboarding_started`.
    func testOnboardingStartedIsIdempotent() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(fixedDate)
        let vm = makeTelemetryViewModel(analytics: analytics, clock: clock)

        vm.onboardingStarted()
        vm.onboardingStarted()

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.filter { $0.name == .onboardingStarted }.count, 1)
    }

    /// A successful `finish()` after `onboardingStarted()` emits exactly one `onboarding_completed`
    /// carrying `elapsed_seconds` as `.int`, equal to the whole seconds the clock advanced (including
    /// sub-second truncation).
    func testFinishEmitsOnboardingCompletedWithElapsedSeconds() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(fixedDate)
        let vm = makeTelemetryViewModel(analytics: analytics, clock: clock)
        fillAnswers(vm)

        vm.onboardingStarted()
        clock.advance(42.9) // truncates to 42 whole seconds
        let ok = await vm.finish()
        XCTAssertTrue(ok)

        let completed = await analytics.recordedEvents.filter { $0.name == .onboardingCompleted }
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0].properties, ["elapsed_seconds": .int(42)])
    }

    /// A failed `finish()` (the user service throws) emits no `onboarding_completed`.
    func testFailedFinishEmitsNoOnboardingCompleted() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(fixedDate)
        let vm = makeTelemetryViewModel(
            analytics: analytics,
            clock: clock,
            userService: FailingUserService()
        )
        fillAnswers(vm)

        vm.onboardingStarted()
        clock.advance(10)
        let ok = await vm.finish()
        XCTAssertFalse(ok)

        let completed = await analytics.recordedEvents.filter { $0.name == .onboardingCompleted }
        XCTAssertTrue(completed.isEmpty, "onboarding_completed never fires on the failure branch")
    }

    /// The two funnel emissions are optional: a view model built with no analytics sink completes
    /// onboarding without trapping.
    func testTelemetryIsOptional() async {
        let vm = makeViewModel()
        fillAnswers(vm)
        vm.onboardingStarted()
        let ok = await vm.finish()
        XCTAssertTrue(ok, "onboarding completes with no analytics sink wired")
    }
}

// MARK: - Test doubles

/// A user service whose `save` always throws, to exercise the failure path.
private struct FailingUserService: UserServiceProtocol {
    struct SaveError: Error {}
    func currentUser() async throws -> User? { nil }
    func save(_ user: User) async throws { throw SaveError() }
    func advancePhase(to earnedPhase: Phase, for userId: String) async throws -> User? { throw SaveError() }
    func deleteCurrentUser() async throws {}
}

/// Restores from a scripted account: the result to return and what the restore writes on the way.
private actor StubAccountRestorer: AccountRestoring {
    private let result: Result<Set<SyncRecordType>, Error>
    private let sideEffect: (@Sendable () async throws -> Void)?
    private(set) var calls = 0

    init(result: Result<Set<SyncRecordType>, Error>, sideEffect: (@Sendable () async throws -> Void)? = nil) {
        self.result = result
        self.sideEffect = sideEffect
    }

    func restoreFromAccount() async throws -> Set<SyncRecordType> {
        calls += 1
        try await sideEffect?()
        return try result.get()
    }
}

/// Records which users had a cold-start policy seeded.
private final class RecordingSessionPolicyService: SessionPolicyServiceProtocol, @unchecked Sendable {
    private(set) var seededUserIds: [String] = []
    func currentPolicy(for user: User) async throws -> SessionPolicy { .default }
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy {
        seededUserIds.append(user.id)
        return .default
    }
    func reprogram(user: User, recentLogs: [WorkoutLog], trigger: ReprogramTrigger) async throws -> SessionPolicy { .default }
    func dueTriggers(user: User, recentLogs: [WorkoutLog], asOf: Date) async throws -> [ReprogramTrigger] { [] }
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
