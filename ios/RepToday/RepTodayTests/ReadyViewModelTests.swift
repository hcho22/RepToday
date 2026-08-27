import XCTest
@testable import RepToday

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

    // MARK: - Give-up abandonment telemetry (US-T10)

    /// A view model wired with an analytics sink and a specific store, for the give-up telemetry tests.
    private func makeViewModel(user: User?, store: any ActiveSessionStore, analytics: MockAnalyticsService) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: CapturingWorkoutEngine(),
            workoutLogService: MockWorkoutLogService(logs: []),
            activeSessionStore: store,
            analytics: analytics,
            now: { self.fixedDate }
        )
    }

    private func rep(_ id: String) -> PrescribedExercise {
        let exercise = Exercise(
            id: id, displayName: id.capitalized, pillar: .strength, movementPattern: .push,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [], isHold: false,
            defaultReps: 10, defaultDurationSeconds: nil, estimatedTimePerSetSeconds: 40, metValue: 4,
            progressionChainId: "\(id)_chain", progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "3x12", apartmentFriendly: true
        )
        return PrescribedExercise(id: UUID(), exercise: exercise, sets: 2, reps: 10, durationSeconds: nil, restSeconds: 0)
    }

    /// A three-block (warm-up/strength/cooldown) workout, so a resumable snapshot can be parked in any
    /// `abandon_point` bucket by choosing `currentStepIndex`.
    private func multiBlockWorkout() -> Workout {
        Workout(
            id: UUID(), createdAt: fixedDate, shape: .blend, focusPillar: nil,
            requestedMinutes: 20, wasReturn: false,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-up", category: .warmup, exercises: [rep("cat_cow")]),
                WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [rep("push_up")]),
                WorkoutBlock(id: UUID(), title: "Cooldown", category: .cooldown, exercises: [rep("stretch")])
            ]
        )
    }

    /// A resumable snapshot parked at `currentStepIndex`, started (so it carries an origin) and
    /// carrying `exercisedMinutes` - exactly the shape a paused player persists.
    private func multiBlockResumableState(currentStepIndex: Int, exercisedMinutes: Int) -> ActiveSessionState {
        let workout = multiBlockWorkout()
        let slots = workout.blocks.flatMap { block in
            block.exercises.map { ActiveSessionState.Slot(blockTitle: block.title, blockCategory: block.category, prescription: $0) }
        }
        return ActiveSessionState(
            workout: workout, slots: slots, currentStepIndex: currentStepIndex, currentSet: 1,
            completedSets: [:], skippedStepIDs: [], startedAt: fixedDate, rest: nil, hold: nil,
            exercisedMinutes: exercisedMinutes
        )
    }

    /// Discarding a resumable session is a *true give-up*, so it emits `session_abandoned` off the
    /// persisted snapshot - carrying the exercised minutes and the coarse `abandon_point` for where the
    /// user was - and never `session_completed`.
    func testDiscardEmitsSessionAbandoned() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.save(multiBlockResumableState(currentStepIndex: 1, exercisedMinutes: 4), for: "preview-user")
        let analytics = MockAnalyticsService()
        let vm = makeViewModel(user: onboardedUser(), store: store, analytics: analytics)
        await vm.load()
        XCTAssertNotNil(vm.resumableSession)

        await vm.discardResumableSession()

        let events = await analytics.recordedEvents
        let abandoned = try XCTUnwrap(events.first { $0.name == .sessionAbandoned })
        XCTAssertEqual(abandoned.properties["completed_minutes"], .int(4))
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("mainWork"))
        XCTAssertEqual(events.filter { $0.name == .sessionCompleted }.count, 0, "a give-up never emits completed")
    }

    /// `abandon_point` is read off the block the snapshot's current step sits in: the warm-up bookend.
    func testDiscardAbandonPointWarmup() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.save(multiBlockResumableState(currentStepIndex: 0, exercisedMinutes: 1), for: "preview-user")
        let analytics = MockAnalyticsService()
        let vm = makeViewModel(user: onboardedUser(), store: store, analytics: analytics)
        await vm.load()

        await vm.discardResumableSession()

        let events = await analytics.recordedEvents
        let abandoned = try XCTUnwrap(events.first { $0.name == .sessionAbandoned })
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("warmup"))
    }

    /// `abandon_point` for the cooldown bookend - parked on the last block, still short of completion.
    func testDiscardAbandonPointCooldown() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.save(multiBlockResumableState(currentStepIndex: 2, exercisedMinutes: 9), for: "preview-user")
        let analytics = MockAnalyticsService()
        let vm = makeViewModel(user: onboardedUser(), store: store, analytics: analytics)
        await vm.load()

        await vm.discardResumableSession()

        let events = await analytics.recordedEvents
        let abandoned = try XCTUnwrap(events.first { $0.name == .sessionAbandoned })
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("cooldown"))
    }

    /// Starting fresh over a still-resumable session overwrites it, so that paused session is given up:
    /// it emits `session_abandoned` and is dropped from the surfaced state before the fresh player runs.
    func testOverwriteEmitsSessionAbandoned() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.save(multiBlockResumableState(currentStepIndex: 1, exercisedMinutes: 6), for: "preview-user")
        let analytics = MockAnalyticsService()
        let vm = makeViewModel(user: onboardedUser(), store: store, analytics: analytics)
        await vm.load()
        XCTAssertNotNil(vm.resumableSession)

        await vm.abandonResumableSessionForOverwrite()

        XCTAssertNil(vm.resumableSession, "the paused session is dropped when the user starts fresh over it")
        let events = await analytics.recordedEvents
        let abandoned = try XCTUnwrap(events.first { $0.name == .sessionAbandoned })
        XCTAssertEqual(abandoned.properties["completed_minutes"], .int(6))
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("mainWork"))
    }

    /// An ordinary fresh start - nothing paused to overwrite - emits no abandonment.
    func testOverwriteWithNothingResumableEmitsNothing() async {
        let analytics = MockAnalyticsService()
        let vm = makeViewModel(user: onboardedUser(), store: InMemoryActiveSessionStore(), analytics: analytics)
        await vm.load()

        await vm.abandonResumableSessionForOverwrite()

        let abandoned = (await analytics.recordedEvents).filter { $0.name == .sessionAbandoned }
        XCTAssertTrue(abandoned.isEmpty, "an ordinary fresh start with nothing paused emits no abandonment")
    }

    /// The whole give-up path across the physical session: the player emits `session_started` and is
    /// paused (no terminal event), then the Ready Screen's Discard emits `session_abandoned`. Both share
    /// one sink, so the physical session lands exactly one started and one abandoned, never a completed.
    func testPauseThenDiscardEmitsExactlyOneAbandonedAcrossThePhysicalSession() async throws {
        let store = InMemoryActiveSessionStore()
        let analytics = MockAnalyticsService()

        let player = ActiveSessionViewModel(
            workout: multiBlockWorkout(), store: store, userId: "preview-user",
            analytics: analytics, now: { self.fixedDate }
        )
        player.start()            // session_started + persists a resumable snapshot
        player.completeSet()      // advance into the strength block, still mid-session
        player.recordSessionEnd() // a resumable pause: no terminal event
        await player.persistenceTask?.value
        await player.analyticsTask?.value

        let vm = makeViewModel(user: onboardedUser(), store: store, analytics: analytics)
        await vm.load()
        XCTAssertNotNil(vm.resumableSession, "the paused session is offered back")

        await vm.discardResumableSession() // true give-up

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.filter { $0.name == .sessionStarted }.count, 1, "started fires once for the physical session")
        XCTAssertEqual(events.filter { $0.name == .sessionAbandoned }.count, 1, "the give-up abandons exactly once")
        XCTAssertEqual(events.filter { $0.name == .sessionCompleted }.count, 0, "a given-up session never completes")
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

    /// Regeneration reuses the cached logs and policy so a chip tap stays on-device and instant - but
    /// it deliberately re-reads the *profile*, because that is where the injury safety filters live
    /// (US-AC08) and they are editable from Settings and the coach's route while this screen is alive.
    /// A chip tap must not hand the engine a profile that still permits what the user just asked to
    /// work around.
    func testSelectDurationRegeneratesAgainstTheCurrentProfile() async throws {
        let users = MutableUserService(user: onboardedUser())
        let engine = CapturingWorkoutEngine()
        let logs = CountingWorkoutLogService()
        let vm = ReadyViewModel(
            userService: users,
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: logs,
            now: { self.fixedDate }
        )

        await vm.load()
        let before = try XCTUnwrap(engine.capturedUser?.profile.injuries)
        XCTAssertFalse(before.contains(InjuryOption.knees.tag), "no knee flag set yet")
        let fetchesAfterLoad = await logs.fetchCount

        // The user flags a knee from Settings while the Ready tab is alive.
        await users.update { $0.profile.injuries.append(InjuryOption.knees.tag) }
        await vm.selectDuration(45)

        XCTAssertEqual(engine.generateCallCount, 2, "one generation on load, one per chip tap")
        XCTAssertEqual(engine.capturedUser?.profile.injuries, before + [InjuryOption.knees.tag],
                       "the regenerated session is built against the safety filter the user just set")
        XCTAssertEqual(vm.user?.profile.injuries, before + [InjuryOption.knees.tag],
                       "and the surfaced user - handed to the player - reflects it too")
        let fetchesAfterTap = await logs.fetchCount
        XCTAssertEqual(fetchesAfterTap, fetchesAfterLoad, "the log scan stays cached across a chip tap")
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

    // MARK: - Ready Screen telemetry (US-T09)

    /// A view model whose injected clock is the shared, advanceable clock the engine mutates during
    /// generation, so `generation_ms` is deterministic and can be asserted exactly.
    private func makeTelemetryViewModel(
        analytics: any AnalyticsServiceProtocol,
        clock: ReadyMutableClock,
        engine: any WorkoutEngineProtocol,
        user: User? = nil
    ) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user ?? onboardedUser(defaultMinutes: 15)),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(logs: []),
            activeSessionStore: InMemoryActiveSessionStore(),
            analytics: analytics,
            now: { clock.now }
        )
    }

    /// The first load emits exactly one `ready_screen_shown` carrying the `generation_ms` measured
    /// around the engine call - the whole-millisecond delta the clock advanced across generation.
    func testFirstLoadEmitsReadyScreenShownWithMeasuredGenerationMs() async {
        let analytics = MockAnalyticsService()
        let clock = ReadyMutableClock(fixedDate)
        // The engine advances the shared clock by 0.25s (exactly representable) inside the call, so the
        // measured span is exactly 250 whole milliseconds.
        let engine = ClockAdvancingWorkoutEngine(clock: clock, advanceBy: 0.25)
        let vm = makeTelemetryViewModel(analytics: analytics, clock: clock, engine: engine)

        await vm.load()

        let shown = await analytics.recordedEvents.filter { $0.name == .readyScreenShown }
        XCTAssertEqual(shown.count, 1, "exactly one ready_screen_shown on the first load")
        XCTAssertEqual(shown[0].properties, ["generation_ms": .int(250)])
        XCTAssertEqual(vm.lastGenerationMs, 250, "the engine call span is measured, not the view work")
    }

    /// A duration-chip regeneration does not re-emit `ready_screen_shown` (that would inflate the
    /// count), but `generation_ms` is still measured on that path for internal debugging.
    func testChipRegenerationDoesNotReEmitButStillMeasures() async {
        let analytics = MockAnalyticsService()
        let clock = ReadyMutableClock(fixedDate)
        let engine = ClockAdvancingWorkoutEngine(clock: clock, advanceBy: 0.25)
        let vm = makeTelemetryViewModel(analytics: analytics, clock: clock, engine: engine)

        await vm.load()
        await vm.selectDuration(30) // a chip tap: regenerates, measures, but must not re-emit

        let shown = await analytics.recordedEvents.filter { $0.name == .readyScreenShown }
        XCTAssertEqual(shown.count, 1, "a chip-tap regeneration does not re-emit ready_screen_shown")
        XCTAssertEqual(engine.generateCallCount, 2, "one generation on load, one on the chip tap")
        XCTAssertEqual(vm.lastGenerationMs, 250, "generation_ms is still measured on the chip-tap path")
    }

    /// A tab re-appear (`load()` re-fires) does not re-emit `ready_screen_shown`: the one-shot guard is
    /// scoped to the first load and survives a refresh, so the funnel counts one open, not every appear.
    func testReappearDoesNotReEmitReadyScreenShown() async {
        let analytics = MockAnalyticsService()
        let clock = ReadyMutableClock(fixedDate)
        let engine = ClockAdvancingWorkoutEngine(clock: clock, advanceBy: 0.25)
        let vm = makeTelemetryViewModel(analytics: analytics, clock: clock, engine: engine)

        await vm.load()
        await vm.load() // the Today tab re-appearing

        let shown = await analytics.recordedEvents.filter { $0.name == .readyScreenShown }
        XCTAssertEqual(shown.count, 1, "a tab re-appear does not re-fire ready_screen_shown")
    }

    /// The emission is optional: a view model built with no analytics sink loads the Ready Screen
    /// without trapping.
    func testReadyScreenTelemetryIsOptional() async {
        let vm = makeViewModel(user: onboardedUser())

        await vm.load()

        XCTAssertNotNil(vm.workout, "the Ready Screen loads with no analytics sink wired")
    }
}

// MARK: - Test doubles

/// A workout engine that records its generation inputs and returns a canned session.
private final class CapturingWorkoutEngine: WorkoutEngineProtocol {
    private(set) var capturedRequestedMinutes: Int?
    private(set) var capturedPolicy: SessionPolicy?
    /// The profile the most recent generation ran against, so a test can pin that a regeneration sees
    /// the *current* safety filters rather than the snapshot the screen loaded with (US-AC08).
    private(set) var capturedUser: User?
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
        capturedUser = user
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
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
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
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}

/// A user service that counts `currentUser()` calls, proving a chip regeneration reuses cached
/// inputs rather than re-fetching.
/// A user service whose stored profile can be changed mid-test, so a screen that re-reads the profile
/// can be told apart from one holding a stale snapshot.
private actor MutableUserService: UserServiceProtocol {
    private var user: User?
    private(set) var currentUserCallCount = 0

    init(user: User?) { self.user = user }

    func currentUser() async throws -> User? {
        currentUserCallCount += 1
        return user
    }

    /// Mutate the stored profile the way another surface (the injury control) would.
    func update(_ transform: (inout User) -> Void) {
        guard var user else { return }
        transform(&user)
        self.user = user
    }

    func save(_ user: User) async throws { self.user = user }
    func deleteCurrentUser() async throws { user = nil }
}

/// A log service that counts its reads, so a test can pin that the expensive history scan stays
/// cached across a chip-tap regeneration.
private actor CountingWorkoutLogService: WorkoutLogServiceProtocol {
    private(set) var fetchCount = 0

    func workoutLogs(from: Date?, to: Date?) async throws -> [WorkoutLog] {
        fetchCount += 1
        return []
    }

    func save(_ log: WorkoutLog) async throws {}
    func deleteLog(id: UUID) async throws {}
    func deleteAllLogs() async throws {}
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
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}

// MARK: - Ready Screen telemetry doubles (US-T09)

/// An advanceable clock the view model reads through its injected `now`, so a test can pin the exact
/// span an engine call takes and assert the `generation_ms` measured around it.
private final class ReadyMutableClock {
    var now: Date
    init(_ start: Date) { now = start }
    func advance(_ interval: TimeInterval) { now += interval }
}

/// A workout engine that advances a shared clock by a fixed interval *inside* `generateWorkout`, so
/// the wall-time delta the view model measures around the engine call (US-T09) is deterministic and
/// exactly assertable. It advances only during the call, so surrounding view work reads a still clock.
private final class ClockAdvancingWorkoutEngine: WorkoutEngineProtocol {
    private let clock: ReadyMutableClock
    private let advanceBy: TimeInterval
    private(set) var generateCallCount = 0

    init(clock: ReadyMutableClock, advanceBy: TimeInterval) {
        self.clock = clock
        self.advanceBy = advanceBy
    }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        generateCallCount += 1
        clock.advance(advanceBy)
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
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}
