import XCTest
@testable import FitSnack

/// Tests the minimal Ready Screen view model (US-I01).
///
/// The Ready Screen's promise is that today's session is already there on open. These tests verify
/// the view model loads the current user, generates a session at the learned Default Duration
/// against the in-force policy, and degrades gracefully when there is no user.
final class ReadyViewModelTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 760_000_000)

    private func onboardedUser(defaultMinutes: Int = 15) -> User {
        var user = MockPersistence.sampleUser
        user.duration = .seeded(minutes: defaultMinutes)
        return user
    }

    private func makeViewModel(
        user: User?,
        engine: CapturingWorkoutEngine = CapturingWorkoutEngine(),
        policy: SessionPolicy = .seeded(forFitnessLevel: .beginner),
        logs: [WorkoutLog] = []
    ) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user),
            sessionPolicyService: StubPolicyService(policy: policy),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(logs: logs),
            activeSessionStore: InMemoryActiveSessionStore(),
            now: { self.fixedDate }
        )
    }

    /// A view model backed by a specific active-session store, so the resume/discard tests can
    /// pre-seed the store and inspect it (US-K04).
    private func makeViewModel(user: User?, store: any ActiveSessionStore) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: CapturingWorkoutEngine(),
            workoutLogService: MockWorkoutLogService(logs: []),
            activeSessionStore: store,
            now: { self.fixedDate }
        )
    }

    /// A minimal in-progress session snapshot parked mid-session, for the resume/discard tests.
    private func resumableState() -> ActiveSessionState {
        let exercise = Exercise(
            id: "push_up", displayName: "Push-up", pillar: .strength, movementPattern: .push,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [],
            isHold: false, defaultReps: 10, defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40, metValue: 4, progressionChainId: "push_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "3x12", apartmentFriendly: true
        )
        let prescription = PrescribedExercise(id: UUID(), exercise: exercise, sets: 3, reps: 12, durationSeconds: nil, restSeconds: 45)
        let workout = Workout(
            id: UUID(), createdAt: fixedDate, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 15, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [prescription])]
        )
        return ActiveSessionState(fresh: workout)
    }

    // MARK: - Background & resume (US-K04)

    /// On load, an abandoned session saved under the user's id is surfaced for Resume/Discard.
    func testLoadSurfacesResumableSession() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.save(resumableState(), for: "preview-user")
        let vm = makeViewModel(user: onboardedUser(), store: store)

        await vm.load()

        XCTAssertNotNil(vm.resumableSession, "a saved session is offered back")
        XCTAssertEqual(vm.resumableSession?.slots.first?.prescription.exercise.id, "push_up")
    }

    /// With nothing saved, there is no resumable session to offer.
    func testLoadNoResumableSessionWhenNoneSaved() async {
        let vm = makeViewModel(user: onboardedUser(), store: InMemoryActiveSessionStore())

        await vm.load()

        XCTAssertNil(vm.resumableSession)
    }

    /// Discarding clears the stored session and the surfaced state, so it is no longer offered.
    func testDiscardResumableSessionClearsIt() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.save(resumableState(), for: "preview-user")
        let vm = makeViewModel(user: onboardedUser(), store: store)
        await vm.load()
        XCTAssertNotNil(vm.resumableSession)

        await vm.discardResumableSession()

        XCTAssertNil(vm.resumableSession)
        let stillSaved = try await store.load(for: "preview-user")
        XCTAssertNil(stillSaved, "the store is cleared, not just the surfaced copy")
    }

    /// Refreshing after the player closes picks up a session the player just saved (abandoned) without
    /// a full reload.
    func testRefreshResumableSessionPicksUpNewlySaved() async throws {
        let store = InMemoryActiveSessionStore()
        let vm = makeViewModel(user: onboardedUser(), store: store)
        await vm.load()
        XCTAssertNil(vm.resumableSession)

        // The player persists an abandoned session, then the Ready Screen re-checks on dismiss.
        try await store.save(resumableState(), for: "preview-user")
        await vm.refreshResumableSession()

        XCTAssertNotNil(vm.resumableSession)
    }

    /// A completed session leaves nothing resumable on the Ready Screen. The player clears the store on
    /// completion and reports it completed; the dismiss handler drops the surfaced state directly rather
    /// than re-reading the store, so a not-yet-landed clear can never resurface the finished session.
    func testHandlePlayerDismissCompletedLeavesNothingResumable() async throws {
        // The store still holds the just-completed snapshot (the player's fire-and-forget clear has
        // not landed yet) - the dismiss handler must not surface it back.
        let store = InMemoryActiveSessionStore()
        try await store.save(resumableState(), for: "preview-user")
        let vm = makeViewModel(user: onboardedUser(), store: store)
        await vm.load()
        XCTAssertNotNil(vm.resumableSession)

        await vm.handlePlayerDismiss(completed: true)

        XCTAssertNil(vm.resumableSession, "a completed session is never offered as resumable")
    }

    /// After a completed session the Ready Screen refreshes its Consistency Score (US-L01): the
    /// completion recorder has written a new log, so returning from the player reflects the win without
    /// waiting for the next genuine open.
    func testHandlePlayerDismissCompletedRefreshesConsistency() async throws {
        let logService = MockWorkoutLogService(logs: [])
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: CapturingWorkoutEngine(),
            workoutLogService: logService,
            activeSessionStore: InMemoryActiveSessionStore(),
            now: { self.fixedDate }
        )
        await vm.load()
        XCTAssertEqual(vm.consistency?.totalWorkoutsCompleted, 0, "no history on the first open")

        // The player completed a session; the completion recorder wrote a log.
        let log = WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: fixedDate, requestedMinutes: 15,
            durationMinutes: 14, wasReturn: false, shape: .blend, focusPillar: nil,
            perceivedDifficulty: nil, exercises: []
        )
        try await logService.save(log)
        await vm.handlePlayerDismiss(completed: true)

        XCTAssertEqual(vm.consistency?.totalWorkoutsCompleted, 1, "the completed session is reflected on return")
    }

    /// An abandoned (not completed) session is re-read on dismiss, so the player's saved snapshot is
    /// surfaced back for Resume/Discard.
    func testHandlePlayerDismissAbandonedSurfacesSavedSession() async throws {
        let store = InMemoryActiveSessionStore()
        let vm = makeViewModel(user: onboardedUser(), store: store)
        await vm.load()
        XCTAssertNil(vm.resumableSession)

        // The player saved an abandoned session before dismissing.
        try await store.save(resumableState(), for: "preview-user")
        await vm.handlePlayerDismiss(completed: false)

        XCTAssertNotNil(vm.resumableSession, "an abandoned session is offered back")
    }

    /// On load the session is generated at the user's Default Duration and exposed, with no error.
    func testLoadGeneratesSessionAtDefaultDuration() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 15), engine: engine)

        await vm.load()

        XCTAssertNotNil(vm.workout)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.requestedMinutes, 15)
        XCTAssertEqual(engine.capturedRequestedMinutes, 15)
    }

    /// The in-force policy is threaded into generation (so the cold-start contract reaches the engine).
    func testLoadPassesCurrentPolicyToEngine() async {
        let engine = CapturingWorkoutEngine()
        let seeded = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let vm = makeViewModel(user: onboardedUser(), engine: engine, policy: seeded)

        await vm.load()

        XCTAssertEqual(engine.capturedPolicy, seeded)
        XCTAssertNotNil(engine.capturedPolicy?.coldStartContract)
    }

    /// With no user, the view model surfaces an empty-state message and generates nothing.
    func testLoadWithNoUserSetsError() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: nil, engine: engine)

        await vm.load()

        XCTAssertNil(vm.workout)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(engine.capturedRequestedMinutes, "the engine is never called without a user")
    }

    /// A generated session that lands within ±1 of the request (using the real engine) proves the
    /// screen shows a ~N-minute session, matching the US-I01 validation.
    func testEndToEndGeneratesRequestedLengthSession() async throws {
        let exercises = try MockExerciseService()
        let engine = MockWorkoutEngine(exerciseService: exercises)
        let users = MockUserService(user: onboardedUser(defaultMinutes: 15))
        let vm = ReadyViewModel(
            userService: users,
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()

        let workout = try XCTUnwrap(vm.workout)
        XCTAssertEqual(workout.requestedMinutes, 15)
        XCTAssertFalse(workout.blocks.isEmpty)
        XCTAssertEqual(workout.blocks.first?.category, ExerciseCategory.warmup, "a session always opens with a warm-up")
    }

    // MARK: - Duration chip (US-J01)

    /// The offered chips are the canonical ascending vocabulary (5/10/15/20/30/45/60).
    func testDurationChipsAreCanonicalVocabulary() {
        let vm = makeViewModel(user: onboardedUser())
        XCTAssertEqual(vm.durationChips, [5, 10, 15, 20, 30, 45, 60])
    }

    /// Tapping a chip regenerates the session at the new duration and updates the selection, while
    /// the existing session stays present (Start is never left waiting).
    func testSelectDurationRegeneratesAtNewDuration() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 15), engine: engine)

        await vm.load()
        XCTAssertEqual(vm.selectedMinutes, 15)

        await vm.selectDuration(30)

        XCTAssertEqual(vm.selectedMinutes, 30)
        XCTAssertEqual(vm.requestedMinutes, 30)
        XCTAssertEqual(engine.capturedRequestedMinutes, 30)
        XCTAssertNotNil(vm.workout, "the session stays present through a regeneration")
        XCTAssertNil(vm.errorMessage)
    }

    /// Regeneration reuses the cached engine inputs - it never re-fetches the user, so a chip tap
    /// stays on-device and instant.
    func testSelectDurationDoesNotRefetchUser() async {
        let users = CountingUserService(user: onboardedUser())
        let engine = CapturingWorkoutEngine()
        let vm = ReadyViewModel(
            userService: users,
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        await vm.selectDuration(45)

        let userFetches = await users.currentUserCallCount
        XCTAssertEqual(userFetches, 1, "the user is fetched once on load, not per chip tap")
        XCTAssertEqual(engine.generateCallCount, 2, "one generation on load, one per chip tap")
    }

    /// Tapping the already-selected chip is a no-op - no wasted regeneration.
    func testSelectDurationSameValueIsNoOp() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 20), engine: engine)

        await vm.load()
        XCTAssertEqual(engine.generateCallCount, 1)

        await vm.selectDuration(20)

        XCTAssertEqual(engine.generateCallCount, 1, "re-selecting the current duration does not regenerate")
    }

    /// Selecting a duration before any user has loaded is a no-op (nothing to generate against).
    func testSelectDurationWithNoUserIsNoOp() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: nil, engine: engine)

        await vm.load()
        await vm.selectDuration(30)

        XCTAssertNil(engine.capturedRequestedMinutes, "the engine is never called without a user")
    }

    /// A re-appear (load re-fires) preserves an in-session chip choice rather than snapping back to
    /// the learned default, and regenerates at the chosen duration.
    func testReappearPreservesSelectedDuration() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 15), engine: engine)

        await vm.load()
        await vm.selectDuration(30)
        XCTAssertEqual(vm.selectedMinutes, 30)

        // Simulate the Today tab re-appearing (its `.task` re-fires).
        await vm.load()

        XCTAssertEqual(vm.selectedMinutes, 30, "a refresh keeps the user's chip choice")
        XCTAssertEqual(engine.capturedRequestedMinutes, 30, "regeneration uses the preserved selection")
    }

    /// A chip-tap regeneration failure reverts the selection to the prior value and keeps the
    /// previously displayed session, so the header and highlighted chip never contradict the screen.
    func testSelectDurationFailureRevertsSelection() async {
        let engine = FlakyWorkoutEngine()
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser(defaultMinutes: 15)),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        let loaded = vm.workout
        XCTAssertNotNil(loaded)
        XCTAssertEqual(vm.selectedMinutes, 15)

        engine.shouldFail = true
        await vm.selectDuration(30)

        XCTAssertEqual(vm.selectedMinutes, 15, "a failed regeneration rolls the selection back")
        XCTAssertEqual(vm.requestedMinutes, 15)
        XCTAssertEqual(vm.workout?.requestedMinutes, loaded?.requestedMinutes, "the previous session stays displayed")
    }

    /// End-to-end (real engine): tapping 30 after a 15-min load produces a ~30-min session, matching
    /// the US-J01 validation.
    func testEndToEndChipRegeneratesToRequestedLength() async throws {
        let exercises = try MockExerciseService()
        let engine = MockWorkoutEngine(exerciseService: exercises)
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser(defaultMinutes: 15)),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        XCTAssertEqual(vm.workout?.requestedMinutes, 15)

        await vm.selectDuration(30)

        XCTAssertEqual(vm.workout?.requestedMinutes, 30)
        XCTAssertEqual(vm.workout?.blocks.first?.category, ExerciseCategory.warmup)
    }

    // MARK: - Variety Language, Consistency, note, re-program (US-J02)

    /// A single-focus strength log completed `daysAgo` before the fixed date, for the "yesterday"
    /// side of the Variety Language contrast.
    private func strengthLog(daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: fixedDate)!,
            requestedMinutes: 15,
            durationMinutes: 15,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
    }

    private func consistencyValue(score: Double, longestChain: Int, total: Int) -> Consistency {
        Consistency(
            weeklyGoal: 3,
            score: score,
            workoutsThisWeek: 1,
            longestChain: longestChain,
            totalWorkoutsCompleted: total,
            totalMinutesExercised: total * 15
        )
    }

    /// The screen surfaces the session's Variety Language line - the honest contrast between today's
    /// lead pillar and the previous session's - as a template-sourced note.
    func testLoadSurfacesVarietyLanguageLine() async {
        let engine = CapturingWorkoutEngine(focusPillar: .mobility)
        let vm = makeViewModel(user: onboardedUser(), engine: engine, logs: [strengthLog(daysAgo: 1)])

        await vm.load()

        let note = vm.varietyNote
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.source, .template)
        XCTAssertTrue(note?.text.contains("mobility") ?? false, "names today's lead pillar")
        XCTAssertTrue(note?.text.contains("strength") ?? false, "names yesterday's contrasting pillar")
    }

    /// The forgiving Consistency Score is surfaced from the log history.
    func testLoadSurfacesConsistencyScore() async {
        let engine = CapturingWorkoutEngine(focusPillar: .mobility)
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            consistencyService: StubConsistencyService(value: consistencyValue(score: 82, longestChain: 4, total: 30)),
            now: { self.fixedDate }
        )

        await vm.load()

        XCTAssertEqual(vm.consistency?.score, 82)
        XCTAssertEqual(vm.consistency?.longestChain, 4)
    }

    /// The Consistency Score reads the full log history, not the bounded engine window, so
    /// `longestChain` ("Best run") reflects runs older than the 70-day lookback.
    func testConsistencyReadsFullHistory() async {
        let recording = RecordingConsistencyService(value: consistencyValue(score: 90, longestChain: 6, total: 40))
        let logs = [strengthLog(daysAgo: 1), strengthLog(daysAgo: 100)]
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: CapturingWorkoutEngine(focusPillar: .mobility),
            workoutLogService: MockWorkoutLogService(logs: logs),
            consistencyService: recording,
            now: { self.fixedDate }
        )

        await vm.load()

        XCTAssertEqual(recording.receivedLogCount, 2, "consistency sees the 100-day-old log, not just the 70-day window")
    }

    /// The full-history Consistency Score read fires once per app open, not on every tab re-appear:
    /// the score only changes when a workout completes, and none completes on the Ready Screen (US-J02).
    func testConsistencyComputedOncePerOpen() async {
        let recording = RecordingConsistencyService(value: consistencyValue(score: 90, longestChain: 6, total: 40))
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: CapturingWorkoutEngine(focusPillar: .mobility),
            workoutLogService: MockWorkoutLogService(logs: [strengthLog(daysAgo: 1)]),
            consistencyService: recording,
            now: { self.fixedDate }
        )

        await vm.load()
        await vm.load()

        XCTAssertEqual(recording.callCount, 1, "the full-history consistency read is not re-run on a tab re-appear")
    }

    /// A duration chip that shifts today's lead pillar recomputes the Variety Language line, so the
    /// header never describes a contrast the currently-displayed session does not produce (US-J02).
    func testSelectDurationRecomputesVarietyLine() async {
        // Yesterday was strength; today is strength at 15 (no contrast) but mobility at 30 (a contrast).
        let engine = PillarByDurationEngine(pillarByMinutes: [15: .strength, 30: .mobility])
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser(defaultMinutes: 15)),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(logs: [strengthLog(daysAgo: 1)]),
            now: { self.fixedDate }
        )

        await vm.load()
        XCTAssertFalse(vm.varietyNote?.text.contains("yesterday") ?? false,
                       "same-pillar day drops the contrast clause")

        await vm.selectDuration(30)

        let note = vm.varietyNote
        XCTAssertTrue(note?.text.contains("mobility") ?? false, "the note follows the regenerated session's lead pillar")
        XCTAssertTrue(note?.text.contains("strength") ?? false, "and names yesterday's contrasting pillar")
    }

    /// The policy `note` is surfaced when the in-force policy carries one, and is `nil` otherwise.
    func testPolicyNoteSurfacedWhenPresent() async {
        var policy = SessionPolicy.default
        policy.note = SessionPolicy.Note(text: "Stepping up the challenge - you've earned it.", source: .template)
        let vm = makeViewModel(user: onboardedUser(), policy: policy)

        await vm.load()

        XCTAssertEqual(vm.policyNote?.text, "Stepping up the challenge - you've earned it.")

        let plain = makeViewModel(user: onboardedUser(), policy: .default)
        await plain.load()
        XCTAssertNil(plain.policyNote, "no note when the policy carries none")
    }

    /// On open, a due trigger kicks off a background re-program against the highest-precedence one,
    /// while the session renders immediately from the existing policy (Start never waits).
    func testReprogramFiresWhenTriggerDue() async {
        let trigger = ReprogramTrigger(kind: .weeklyBoundary, detectedAt: fixedDate)
        let policyService = RecordingPolicyService(policy: .seeded(forFitnessLevel: .beginner), triggers: [trigger])
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: policyService,
            workoutEngine: CapturingWorkoutEngine(focusPillar: .mobility),
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()

        // The session is present the moment load returns - rendering never waited on the re-program.
        XCTAssertNotNil(vm.workout)
        XCTAssertNil(vm.errorMessage)

        // The background re-program is fire-and-forget; await it to assert it ran with the trigger.
        await vm.reprogramTask?.value
        let recorded = await policyService.reprogrammedWith
        XCTAssertEqual(recorded, [trigger])
    }

    /// With no trigger due, no re-program is written.
    func testNoReprogramWhenNoTriggerDue() async {
        let policyService = RecordingPolicyService(policy: .seeded(forFitnessLevel: .beginner), triggers: [])
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: policyService,
            workoutEngine: CapturingWorkoutEngine(focusPillar: .mobility),
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        await vm.reprogramTask?.value

        let recorded = await policyService.reprogrammedWith
        XCTAssertTrue(recorded.isEmpty)
    }

    /// The on-open re-program check fires once per open, not on every tab re-appear.
    func testReprogramFiresOncePerOpen() async {
        let trigger = ReprogramTrigger(kind: .weeklyBoundary, detectedAt: fixedDate)
        let policyService = RecordingPolicyService(policy: .seeded(forFitnessLevel: .beginner), triggers: [trigger])
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser()),
            sessionPolicyService: policyService,
            workoutEngine: CapturingWorkoutEngine(focusPillar: .mobility),
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        await vm.reprogramTask?.value
        // Simulate the Today tab re-appearing.
        await vm.load()
        await vm.reprogramTask?.value

        let recorded = await policyService.reprogrammedWith
        XCTAssertEqual(recorded.count, 1, "a tab re-appear does not re-fire the on-open re-program")
    }
}

// MARK: - Test doubles

/// A workout engine that records its generation inputs and returns a canned session.
private final class CapturingWorkoutEngine: WorkoutEngineProtocol {
    private(set) var capturedRequestedMinutes: Int?
    private(set) var capturedPolicy: SessionPolicy?
    private(set) var generateCallCount = 0
    /// Lets a test give the canned session a lead pillar so the Variety Language line has a real
    /// contrast to name (US-J02); `nil` keeps the pre-J02 warm-up-only behavior.
    var focusPillar: Pillar?

    init(focusPillar: Pillar? = nil) { self.focusPillar = focusPillar }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        capturedRequestedMinutes = requestedMinutes
        capturedPolicy = sessionPolicy
        generateCallCount += 1
        return Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            shape: focusPillar == nil ? .blend : .singleFocus,
            focusPillar: focusPillar,
            requestedMinutes: requestedMinutes,
            wasReturn: false,
            blocks: []
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}

/// A workout engine that can be flipped to throw, exercising the failure/revert path.
private final class FlakyWorkoutEngine: WorkoutEngineProtocol {
    var shouldFail = false

    struct GenerationError: Error {}

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        if shouldFail { throw GenerationError() }
        return Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: requestedMinutes,
            wasReturn: false,
            blocks: []
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}

/// A user service that counts `currentUser()` calls, proving a chip regeneration reuses cached
/// inputs rather than re-fetching.
private actor CountingUserService: UserServiceProtocol {
    private let user: User?
    private(set) var currentUserCallCount = 0

    init(user: User?) { self.user = user }

    func currentUser() async throws -> User? {
        currentUserCallCount += 1
        return user
    }

    func save(_ user: User) async throws {}
    func deleteCurrentUser() async throws {}
}

/// A policy service that returns a fixed policy and no-ops the write paths.
private struct StubPolicyService: SessionPolicyServiceProtocol {
    let policy: SessionPolicy
    func currentPolicy(for user: User) async throws -> SessionPolicy { policy }
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy { policy }
    func reprogram(user: User, recentLogs: [WorkoutLog], trigger: ReprogramTrigger) async throws -> SessionPolicy { policy }
    func dueTriggers(user: User, recentLogs: [WorkoutLog], asOf: Date) async throws -> [ReprogramTrigger] { [] }
}

/// A policy service that reports configurable due triggers and records every re-program (US-J02).
/// An actor so the background re-program task records safely off the main thread.
private actor RecordingPolicyService: SessionPolicyServiceProtocol {
    let policy: SessionPolicy
    let triggers: [ReprogramTrigger]
    private(set) var reprogrammedWith: [ReprogramTrigger] = []

    init(policy: SessionPolicy, triggers: [ReprogramTrigger] = []) {
        self.policy = policy
        self.triggers = triggers
    }

    func currentPolicy(for user: User) async throws -> SessionPolicy { policy }
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy { policy }

    func reprogram(user: User, recentLogs: [WorkoutLog], trigger: ReprogramTrigger) async throws -> SessionPolicy {
        reprogrammedWith.append(trigger)
        return policy
    }

    func dueTriggers(user: User, recentLogs: [WorkoutLog], asOf: Date) async throws -> [ReprogramTrigger] {
        triggers
    }
}

/// A consistency service that hands back a fixed score, so the Ready Screen surfacing is testable
/// without depending on the real evaluator's clock.
private struct StubConsistencyService: ConsistencyServiceProtocol {
    let value: Consistency
    func consistency(for logs: [WorkoutLog], weeklyGoal: Int) async throws -> Consistency { value }
    func updatedConsistency(after log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws -> Consistency { value }
}

/// A consistency service that records the logs it was handed, proving the Ready Screen reads the
/// full history (not the bounded engine window) so `longestChain` reflects all-time runs (US-J02).
private final class RecordingConsistencyService: ConsistencyServiceProtocol {
    let value: Consistency
    private(set) var receivedLogCount = 0
    private(set) var callCount = 0

    init(value: Consistency) { self.value = value }

    func consistency(for logs: [WorkoutLog], weeklyGoal: Int) async throws -> Consistency {
        receivedLogCount = logs.count
        callCount += 1
        return value
    }
    func updatedConsistency(after log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws -> Consistency { value }
}

/// A workout engine whose canned session's lead pillar depends on the requested minutes, so a chip
/// tap that changes the session shape also changes today's lead pillar - letting a test prove the
/// Variety Language line is recomputed on regeneration (US-J02).
private final class PillarByDurationEngine: WorkoutEngineProtocol {
    let pillarByMinutes: [Int: Pillar]

    init(pillarByMinutes: [Int: Pillar]) { self.pillarByMinutes = pillarByMinutes }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            shape: .singleFocus,
            focusPillar: pillarByMinutes[requestedMinutes],
            requestedMinutes: requestedMinutes,
            wasReturn: false,
            blocks: []
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}
