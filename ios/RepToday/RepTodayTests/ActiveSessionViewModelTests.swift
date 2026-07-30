import XCTest
@testable import RepToday

/// Tests the active-session player view model (US-K01).
///
/// The player's promise is that the user never loses their place: it walks through each prescribed
/// exercise in order, tracks the set they are on, keeps elapsed time accurate, and records what was
/// done toward the eventual log. These tests drive that walk-through deterministically with an
/// injected clock - no real time passes.
final class ActiveSessionViewModelTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 760_000_000)

    // MARK: - Fixtures

    private func repExercise(id: String, pattern: MovementPattern = .push, pillar: Pillar = .strength) -> Exercise {
        Exercise(
            id: id,
            displayName: id.capitalized,
            pillar: pillar,
            movementPattern: pattern,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: false,
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "\(id)_chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x12 clean reps",
            apartmentFriendly: true
        )
    }

    private func holdExercise(id: String, pattern: MovementPattern = .core) -> Exercise {
        Exercise(
            id: id,
            displayName: id.capitalized,
            pillar: .strength,
            movementPattern: pattern,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: true,
            defaultReps: nil,
            defaultDurationSeconds: 30,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "\(id)_chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x45s hold",
            apartmentFriendly: true
        )
    }

    /// The same fixture marked `isPerSide`, so the player's target copy can be exercised against the
    /// flag the timing model actually reads.
    private func perSide(_ exercise: Exercise) -> Exercise {
        var copy = exercise
        copy.isPerSide = true
        return copy
    }

    private func repPrescription(_ id: String, sets: Int, reps: Int) -> PrescribedExercise {
        PrescribedExercise(id: UUID(), exercise: repExercise(id: id), sets: sets, reps: reps, durationSeconds: nil, restSeconds: 30)
    }

    private func holdPrescription(_ id: String, sets: Int, seconds: Int) -> PrescribedExercise {
        PrescribedExercise(id: UUID(), exercise: holdExercise(id: id), sets: sets, reps: nil, durationSeconds: seconds, restSeconds: 30)
    }

    /// A two-block session: a one-exercise warm-up, then a two-exercise strength block.
    private func sampleWorkout() -> Workout {
        let warmup = WorkoutBlock(
            id: UUID(),
            title: "Warm-up",
            category: .warmup,
            exercises: [holdPrescription("cat_cow", sets: 1, seconds: 30)]
        )
        let strength = WorkoutBlock(
            id: UUID(),
            title: "Strength",
            category: .strength,
            exercises: [
                repPrescription("push_up", sets: 3, reps: 12),
                repPrescription("squat", sets: 2, reps: 15)
            ]
        )
        return Workout(
            id: UUID(),
            createdAt: start,
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: 15,
            wasReturn: false,
            blocks: [warmup, strength]
        )
    }

    private func makeViewModel(
        _ workout: Workout? = nil,
        clock: @escaping () -> Date,
        feedback: RestTimerFeedback = SpyRestFeedback()
    ) -> ActiveSessionViewModel {
        ActiveSessionViewModel(workout: workout ?? sampleWorkout(), now: clock, feedback: feedback)
    }

    /// Counts rest-completion cues so the tests can assert the haptic/audio fires exactly when a rest
    /// runs out - and never on a skip.
    private final class SpyRestFeedback: RestTimerFeedback {
        private(set) var completions = 0
        func restDidComplete() { completions += 1 }
    }

    // MARK: - Flattening

    /// The player flattens every block's exercises into one ordered list, tagged with block context
    /// and a 1-based overall position.
    func testFlattensBlocksInOrder() {
        let vm = makeViewModel(clock: { self.start })

        XCTAssertEqual(vm.steps.count, 3)
        XCTAssertEqual(vm.steps.map(\.prescription.exercise.id), ["cat_cow", "push_up", "squat"])
        XCTAssertEqual(vm.steps.map(\.position), [1, 2, 3])
        XCTAssertTrue(vm.steps.allSatisfy { $0.total == 3 })
        XCTAssertEqual(vm.steps.first?.blockTitle, "Warm-up")
        XCTAssertEqual(vm.steps.last?.blockCategory, .strength)
        XCTAssertFalse(vm.isComplete)
    }

    /// An empty session (no exercises) is immediately complete rather than stranding the player.
    func testEmptyWorkoutIsComplete() {
        let empty = Workout(id: UUID(), createdAt: start, shape: .singleFocus, focusPillar: .strength, requestedMinutes: 5, wasReturn: false, blocks: [])
        let vm = ActiveSessionViewModel(workout: empty, now: { self.start })

        XCTAssertTrue(vm.isComplete)
        XCTAssertNil(vm.currentStep)
        XCTAssertEqual(vm.progress, 1)
    }

    // MARK: - Set tracking & advancing

    /// Completing a set within an exercise advances the set counter but stays on the same exercise.
    func testCompleteSetAdvancesWithinExercise() {
        let vm = makeViewModel(clock: { self.start })
        // Move past the single-set warm-up onto the 3-set push-up.
        vm.completeSet()
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up")
        XCTAssertEqual(vm.currentSet, 1)

        vm.completeSet()
        XCTAssertEqual(vm.currentSet, 2, "still on the push-up, now the second set")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up")
    }

    /// Completing the last set of an exercise advances to the next exercise and resets the set count.
    func testCompletingLastSetAdvancesExercise() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet() // finishes cat_cow (1 set) -> push_up
        vm.completeSet() // push_up set 1
        vm.completeSet() // push_up set 2
        vm.completeSet() // push_up set 3 -> squat

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")
        XCTAssertEqual(vm.currentSet, 1)
        XCTAssertFalse(vm.isComplete)
    }

    /// Finishing the final set of the final exercise completes the session.
    func testCompletingAllSetsFinishesSession() {
        let vm = makeViewModel(clock: { self.start })
        // 1 + 3 + 2 = 6 sets in total.
        for _ in 0..<6 { vm.completeSet() }

        XCTAssertTrue(vm.isComplete)
        XCTAssertNil(vm.currentStep)
        XCTAssertEqual(vm.completedSetCount, 6)
        XCTAssertEqual(vm.progress, 1)
    }

    /// Completing a set records the prescribed target as performed, toward the eventual log.
    func testCompletedSetsRecordPrescribedTargets() {
        let vm = makeViewModel(clock: { self.start })
        let catCow = vm.steps[0].id
        let pushUp = vm.steps[1].id

        vm.completeSet() // cat_cow: one 30s hold
        vm.completeSet() // push_up set 1: 12 reps

        XCTAssertEqual(vm.completedSets[catCow], [CompletedSet(reps: nil, durationSeconds: 30)])
        XCTAssertEqual(vm.completedSets[pushUp], [CompletedSet(reps: 12, durationSeconds: nil)])
    }

    /// `completeSet` is a no-op once the session is complete.
    func testCompleteSetNoOpWhenComplete() {
        let vm = makeViewModel(clock: { self.start })
        for _ in 0..<6 { vm.completeSet() }
        XCTAssertEqual(vm.completedSetCount, 6)

        vm.completeSet()
        XCTAssertEqual(vm.completedSetCount, 6, "no extra set recorded after completion")
    }

    // MARK: - Skipping

    /// Skipping an exercise records no sets, flags it skipped, and advances.
    func testSkipExerciseAdvancesAndFlags() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet() // onto push_up
        let pushUpID = vm.currentStep!.id

        vm.skipExercise()

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")
        XCTAssertTrue(vm.skippedStepIDs.contains(pushUpID))
        XCTAssertNil(vm.completedSets[pushUpID], "a skipped exercise records no sets")
    }

    /// Skipping after completing part of an exercise discards the partial sets, so a skipped
    /// exercise never carries completed sets into the eventual log.
    func testSkipAfterPartialSetsDiscardsRecordedSets() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet() // cat_cow done -> push_up
        let pushUpID = vm.currentStep!.id
        vm.completeSet() // push_up set 1 of 3 recorded
        XCTAssertEqual(vm.completedSets[pushUpID]?.count, 1)

        vm.skipExercise() // abandon push_up mid-exercise

        XCTAssertTrue(vm.skippedStepIDs.contains(pushUpID))
        XCTAssertNil(vm.completedSets[pushUpID], "partial sets are discarded on skip")

        let pushUp = vm.loggedExercises().first { $0.exerciseId == "push_up" }
        XCTAssertTrue(pushUp?.skipped ?? false)
        XCTAssertEqual(pushUp?.completedSets.count, 0)
    }

    /// Skipping the last exercise finishes the session.
    func testSkipLastExerciseFinishes() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet() // cat_cow done -> push_up
        vm.skipExercise() // push_up -> squat
        vm.skipExercise() // squat -> complete

        XCTAssertTrue(vm.isComplete)
    }

    // MARK: - Logged handoff

    /// The eventual-log rows carry each exercise's completed sets, pillar/pattern, and skip flag.
    func testLoggedExercisesReflectTracking() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet() // cat_cow
        vm.completeSet() // push_up 1
        vm.completeSet() // push_up 2
        vm.completeSet() // push_up 3 -> squat
        vm.skipExercise() // squat skipped -> complete

        let logged = vm.loggedExercises()
        XCTAssertEqual(logged.count, 3)

        let pushUp = logged.first { $0.exerciseId == "push_up" }
        XCTAssertEqual(pushUp?.completedSets.count, 3)
        XCTAssertEqual(pushUp?.pillar, .strength)
        XCTAssertEqual(pushUp?.movementPattern, .push)
        XCTAssertFalse(pushUp?.skipped ?? true)

        let squat = logged.first { $0.exerciseId == "squat" }
        XCTAssertTrue(squat?.skipped ?? false)
        XCTAssertEqual(squat?.completedSets.count, 0)
    }

    // MARK: - Elapsed time

    /// Elapsed time is measured from `start()` against the injected clock, and reads zero before start.
    func testElapsedMeasuredFromStart() {
        var clock = start
        let vm = makeViewModel(clock: { clock })

        XCTAssertEqual(vm.elapsed(asOf: clock), 0, "no start yet")

        vm.start()
        clock = start.addingTimeInterval(65)
        XCTAssertEqual(vm.elapsed(asOf: clock), 65)
    }

    /// `start()` is idempotent - a second call keeps the original start, so elapsed never resets.
    func testStartIsIdempotent() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        vm.start()
        let firstStart = vm.startedAt

        clock = start.addingTimeInterval(30)
        vm.start()
        XCTAssertEqual(vm.startedAt, firstStart, "the start time is captured only once")
        XCTAssertEqual(vm.elapsed(asOf: clock), 30)
    }

    /// Once complete, elapsed time freezes at the finish instant instead of ticking onward.
    func testElapsedFreezesAtCompletion() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        vm.start()

        clock = start.addingTimeInterval(120)
        for _ in 0..<6 { vm.completeSet() } // finishes at t+120
        XCTAssertTrue(vm.isComplete)

        clock = start.addingTimeInterval(600) // ten minutes later
        XCTAssertEqual(vm.elapsed(asOf: clock), 120, "the clock stops at completion")
    }

    // MARK: - Progress

    /// Progress reflects completed sets over total sets, weighting longer exercises more.
    func testProgressByCompletedSets() {
        let vm = makeViewModel(clock: { self.start })
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.totalSets, 6)

        vm.completeSet() // 1/6
        vm.completeSet() // 2/6
        vm.completeSet() // 3/6
        XCTAssertEqual(vm.progress, 0.5, accuracy: 0.0001)
    }

    // MARK: - Rest timer (US-K02)

    /// Completing a set opens a rest for the just-completed prescription's `restSeconds`, counting
    /// down from that value against the injected clock.
    func testCompleteSetStartsRest() {
        var clock = start
        let vm = makeViewModel(clock: { clock })

        vm.completeSet() // cat_cow done -> push_up; the 30s rest begins
        XCTAssertTrue(vm.isResting)
        XCTAssertEqual(vm.restTotalSeconds, 30)
        XCTAssertEqual(vm.restRemaining(asOf: clock), 30)

        clock = start.addingTimeInterval(10)
        XCTAssertEqual(vm.restRemaining(asOf: clock), 20, "counts down with the clock")
    }

    /// When the rest reaches zero the session auto-advances (the rest ends) and the completion cue
    /// fires exactly once - not before it elapses, and not again on repeated ticks.
    func testRestCompletionFiresCueOnce() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        vm.completeSet() // 30s rest

        clock = start.addingTimeInterval(10)
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isResting, "still resting - 20s to go")
        XCTAssertEqual(spy.completions, 0)

        clock = start.addingTimeInterval(30)
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertFalse(vm.isResting, "rest ended at zero")
        XCTAssertEqual(spy.completions, 1)

        vm.completeRestIfElapsed(asOf: clock) // idempotent - the overlay ticks repeatedly
        XCTAssertEqual(spy.completions, 1, "the cue fires once, not per tick")
    }

    /// Skipping the rest ends it immediately and does not fire the completion cue (the user chose to
    /// move on), revealing the already-advanced next set.
    func testSkipRestEndsWithoutCue() {
        let clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        vm.completeSet()
        XCTAssertTrue(vm.isResting)

        vm.skipRest()
        XCTAssertFalse(vm.isResting)
        XCTAssertEqual(vm.restRemaining(asOf: clock), 0)
        XCTAssertEqual(spy.completions, 0, "skipping is not a completion")
    }

    /// Extending the rest adds time to both the remaining countdown and the total the ring measures.
    func testExtendRestAddsTime() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        vm.completeSet() // 30s rest, deadline at t+30

        clock = start.addingTimeInterval(10) // 20s remaining
        vm.extendRest(by: 15)
        XCTAssertEqual(vm.restTotalSeconds, 45)
        XCTAssertEqual(vm.restRemaining(asOf: clock), 35)
    }

    /// Backgrounding pauses the rest: the remaining freezes while away and resumes from that remainder
    /// on return, so the countdown never blows past.
    func testPauseFreezesAndResumeReschedules() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        vm.completeSet() // 30s rest, deadline at t+30

        clock = start.addingTimeInterval(10) // 20s remaining
        vm.pauseRest(asOf: clock)
        XCTAssertTrue(vm.isRestPaused)

        clock = start.addingTimeInterval(120) // two minutes in the background
        XCTAssertEqual(vm.restRemaining(asOf: clock), 20, "frozen while paused")

        vm.resumeRest(asOf: clock)
        XCTAssertFalse(vm.isRestPaused)
        XCTAssertEqual(vm.restRemaining(asOf: clock), 20, "resumes from the captured remainder")

        clock = start.addingTimeInterval(125) // 5s after resuming
        XCTAssertEqual(vm.restRemaining(asOf: clock), 15)
    }

    /// A paused rest never auto-completes even once its captured remainder would have hit zero in
    /// wall-clock terms - the app is away, so the countdown is frozen.
    func testPausedRestDoesNotAutoComplete() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        vm.completeSet() // 30s rest

        clock = start.addingTimeInterval(10)
        vm.pauseRest(asOf: clock)
        clock = start.addingTimeInterval(600)
        vm.completeRestIfElapsed(asOf: clock)

        XCTAssertTrue(vm.isResting, "paused rest stays up")
        XCTAssertEqual(spy.completions, 0)
    }

    /// No rest opens after the final set of the session - the session is over, not paced.
    func testNoRestAfterFinalSet() {
        let vm = makeViewModel(clock: { self.start })
        for _ in 0..<6 { vm.completeSet() }

        XCTAssertTrue(vm.isComplete)
        XCTAssertFalse(vm.isResting)
    }

    /// A prescription with no configured rest opens no rest overlay - the next set shows immediately.
    func testZeroRestSecondsOpensNoRest() {
        let prescription = PrescribedExercise(
            id: UUID(), exercise: repExercise(id: "push_up"), sets: 2, reps: 10, durationSeconds: nil, restSeconds: 0
        )
        let block = WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [prescription])
        let workout = Workout(
            id: UUID(), createdAt: start, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 5, wasReturn: false, blocks: [block]
        )
        let vm = ActiveSessionViewModel(workout: workout, now: { self.start })

        vm.completeSet() // set 1 -> set 2, no rest configured
        XCTAssertFalse(vm.isResting)
        XCTAssertEqual(vm.currentSet, 2)
    }

    /// Skipping the exercise drops any active rest without firing its cue.
    func testSkipExerciseEndsActiveRest() {
        let clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        vm.completeSet() // cat_cow -> push_up, rest active
        XCTAssertTrue(vm.isResting)

        vm.skipExercise()
        XCTAssertFalse(vm.isResting)
        XCTAssertEqual(spy.completions, 0)
    }

    // MARK: - Hold timer (US-O03)

    /// A per-side hold slot, so the two-leg path can be driven against the same `isPerSide` flag the
    /// engine's timing model charges both sides against.
    private func perSideHoldPrescription(_ id: String, sets: Int, seconds: Int) -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(), exercise: perSide(holdExercise(id: id)),
            sets: sets, reps: nil, durationSeconds: seconds, restSeconds: 30
        )
    }

    /// A session leading with a per-side hold, followed by a rep movement so the hold has somewhere to
    /// advance to.
    private func perSideHoldWorkout(sets: Int = 1, seconds: Int = 20) -> Workout {
        let block = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [
                perSideHoldPrescription("side_plank", sets: sets, seconds: seconds),
                repPrescription("push_up", sets: 1, reps: 10)
            ]
        )
        return Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [block]
        )
    }

    /// The Hold Timer is offered on a timed movement and withheld on a rep-based one, which keeps the
    /// unchanged manual set tracker + "Complete set" flow.
    func testHoldTimerIsOfferedOnlyForTimedExercises() {
        let vm = makeViewModel(clock: { self.start }) // leads with the 30s cat_cow hold

        XCTAssertEqual(vm.holdSecondsPerSide, 30)
        XCTAssertEqual(vm.holdSidesPerSet, 1)
        XCTAssertTrue(vm.canStartHold)

        vm.completeSet() // -> push_up, rep-based
        vm.skipRest()

        XCTAssertNil(vm.holdSecondsPerSide, "a rep-based movement has no hold to time")
        XCTAssertFalse(vm.canStartHold)
    }

    /// Starting a hold counts the prescribed seconds down against the injected clock.
    func testStartHoldCountsDownThePrescribedSeconds() {
        var clock = start
        let vm = makeViewModel(clock: { clock })

        vm.startHold()
        XCTAssertTrue(vm.isHolding)
        XCTAssertEqual(vm.holdTotalSeconds, 30)
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 30)

        clock = start.addingTimeInterval(12)
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 18)
    }

    /// At zero the hold fires the completion cue exactly once - never before it elapses, never again on
    /// repeated ticks - records the set, and hands off to the rest, so a timed exercise advances without
    /// the user touching the screen.
    func testHoldCompletionFiresCueOnceAndRecordsTheSet() throws {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        let holdStepID = try XCTUnwrap(vm.currentStep?.id)

        vm.startHold() // 30s

        clock = start.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isHolding, "still holding - 10s to go")
        XCTAssertEqual(spy.completions, 0, "the cue never fires early")
        XCTAssertEqual(vm.completedSetCount, 0)

        clock = start.addingTimeInterval(30)
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertFalse(vm.isHolding)
        XCTAssertEqual(spy.completions, 1)
        XCTAssertEqual(vm.completedSets[holdStepID], [CompletedSet(reps: nil, durationSeconds: 30)], "the set records itself")
        XCTAssertTrue(vm.isResting, "and hands off to the rest")

        vm.completeHoldIfElapsed(asOf: clock) // the view's ticker keeps calling
        XCTAssertEqual(spy.completions, 1, "the cue fires once, not per tick")
        XCTAssertEqual(vm.completedSetCount, 1)
    }

    /// A per-side hold is one leg per *side*, because the engine charges both: the first leg cues the
    /// switch and parks on side 2 without recording anything, and only the last leg records the set. A
    /// single countdown that recorded the set after one side would quietly halve the prescribed work.
    func testPerSideHoldRunsOneLegPerSideAndRecordsOneSet() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { clock }, feedback: spy)

        XCTAssertEqual(vm.holdSidesPerSet, 2)
        XCTAssertEqual(vm.holdSide, 1)
        XCTAssertEqual(vm.holdSecondsPerSide, 20, "each leg is the prescribed per-side hold, not the pair")

        vm.startHold()
        clock = start.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock)

        XCTAssertEqual(spy.completions, 1, "the cue marks the switch")
        XCTAssertEqual(vm.holdSide, 2, "parked on the second side")
        XCTAssertFalse(vm.isHolding, "the next leg waits for the user's tap - time to change position")
        XCTAssertEqual(vm.completedSetCount, 0, "half the set is not a set")
        XCTAssertFalse(vm.isResting)

        vm.startHold()
        clock = start.addingTimeInterval(40)
        vm.completeHoldIfElapsed(asOf: clock)

        XCTAssertEqual(spy.completions, 2)
        XCTAssertEqual(vm.completedSetCount, 1, "both sides make exactly one set")
        XCTAssertTrue(vm.isResting)
        XCTAssertEqual(vm.holdSide, 1, "the next set opens back on side 1")
    }

    /// Stopping a hold early records nothing and fires no cue - the user chose to come out of it - and
    /// leaves the same side ready to re-start.
    func testCancelHoldRecordsNothingAndFiresNoCue() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { clock }, feedback: spy)

        vm.startHold()
        clock = start.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock) // side 1 done, parked on side 2
        vm.startHold()
        clock = start.addingTimeInterval(25)
        vm.cancelHold()

        XCTAssertFalse(vm.isHolding)
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 0)
        XCTAssertEqual(vm.completedSetCount, 0)
        XCTAssertEqual(spy.completions, 1, "only the completed first side cued")
        XCTAssertEqual(vm.holdSide, 2, "the abandoned side is still the one they owe")
        XCTAssertTrue(vm.canStartHold, "and can be started again")
    }

    /// Backgrounding freezes the hold rather than letting it blow past, and a frozen hold never
    /// auto-completes - so its cue can never fire at a screen the user is away from. Foregrounding
    /// reschedules from the captured remainder.
    func testPausedHoldFreezesAndNeverAutoCompletes() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        vm.startHold() // 30s

        clock = start.addingTimeInterval(10) // 20s remaining
        vm.pauseHold(asOf: clock)
        XCTAssertTrue(vm.isHoldPaused)

        clock = start.addingTimeInterval(600) // ten minutes away
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 20, "frozen while paused")
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isHolding, "a paused hold stays up")
        XCTAssertEqual(spy.completions, 0)
        XCTAssertEqual(vm.completedSetCount, 0)

        vm.resumeHold(asOf: clock)
        XCTAssertFalse(vm.isHoldPaused)
        clock = start.addingTimeInterval(615)
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 5, "resumes from the captured remainder")
    }

    /// A hold cannot start on top of a rest - the rest overlay owns the screen, and a countdown behind
    /// it would run unseen.
    func testHoldCannotStartDuringRest() {
        let vm = makeViewModel(perSideHoldWorkout(sets: 2, seconds: 20), clock: { self.start })
        vm.completeSet() // set 1 of 2 recorded manually -> 30s rest opens

        XCTAssertTrue(vm.isResting)
        XCTAssertFalse(vm.canStartHold)
        vm.startHold()
        XCTAssertFalse(vm.isHolding, "start is a no-op during rest")

        vm.skipRest()
        XCTAssertTrue(vm.canStartHold)
    }

    /// Skipping the exercise drops a running hold without firing its cue and clears the side, so the
    /// next timed movement opens on side 1.
    func testSkipExerciseClearsARunningHold() {
        let spy = SpyRestFeedback()
        let vm = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { self.start }, feedback: spy)

        vm.startHold()
        vm.completeHoldIfElapsed(asOf: start.addingTimeInterval(20)) // side 1 done -> parked on side 2
        vm.startHold()

        vm.skipExercise()

        XCTAssertFalse(vm.isHolding)
        XCTAssertEqual(vm.holdSide, 1, "the abandoned side does not follow the user to the next movement")
        XCTAssertEqual(spy.completions, 1, "skipping is not a completion - only the finished first side cued")
        XCTAssertEqual(vm.skippedStepIDs.count, 1)
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up")
    }

    /// A swap reshapes the slot the countdown was timing, so it drops the running hold and - on an
    /// actual substitution - the side too: a different movement is a different set of legs.
    func testSwapClearsARunningHold() async {
        let substitute = substitutePrescription("dips", sets: 3, reps: 10, rest: 45)
        let vm = swappableHoldViewModel(StubSwapEngine(outcome: .substituted(substitute)))
        vm.startHold()
        vm.completeHoldIfElapsed(asOf: start.addingTimeInterval(20)) // parked on side 2
        vm.startHold()

        await vm.swapCurrentExercise()

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "dips")
        XCTAssertFalse(vm.isHolding)
        XCTAssertEqual(vm.holdSide, 1)
        XCTAssertNil(vm.holdSecondsPerSide, "the substitute is rep-based, so no hold is offered")
    }

    /// A swap that finds nothing leaves the original movement in place, so it must also leave the side
    /// the user has already held. Clearing it would charge them a side for a substitution that never
    /// happened - they would hold side 1 of the same stretch twice.
    func testSwapWithNoAlternativeKeepsTheSideAlreadyHeld() async {
        let vm = swappableHoldViewModel(StubSwapEngine(outcome: .noAlternative))
        vm.startHold()
        vm.completeHoldIfElapsed(asOf: start.addingTimeInterval(20)) // parked on side 2

        await vm.swapCurrentExercise()

        XCTAssertTrue(vm.noSwapAlternative)
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "side_plank", "the original slot stays")
        XCTAssertEqual(vm.holdSide, 2, "and so does the side they still owe")
    }

    /// A hold started while a swap is in flight must never end up timing - let alone recording - the
    /// movement that replaces it. The countdown is offered against the prescription on screen, and a
    /// substitution makes that prescription the wrong one, so the leg is refused while the swap is
    /// awaiting and cleared outright by the substitution that lands.
    func testHoldStartedDuringAnInFlightSwapNeverRecordsAgainstTheSubstitute() async {
        var clock = start
        let spy = SpyRestFeedback()
        let substitute = substitutePrescription("dips", sets: 3, reps: 10, rest: 45)
        let engine = StubSwapEngine(outcome: .substituted(substitute))
        let vm = ActiveSessionViewModel(
            workout: perSideHoldWorkout(seconds: 20),
            swapEngine: engine, user: makeUser(), recentLogs: [], sessionPolicy: .default,
            now: { clock }, feedback: spy
        )
        // The user taps "Start hold" in the window between requesting the swap and the engine answering.
        engine.onSwap = { vm.startHold() }

        await vm.swapCurrentExercise()

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "dips")
        XCTAssertFalse(vm.isHolding, "no countdown survives onto the substitute")
        XCTAssertEqual(vm.holdSide, 1)

        // Long past any deadline the refused leg could have carried: the ticker's check records nothing.
        clock = start.addingTimeInterval(600)
        vm.completeHoldIfElapsed(asOf: clock)

        XCTAssertEqual(vm.completedSetCount, 0, "no set is logged for a movement the user never performed")
        XCTAssertEqual(spy.completions, 0, "and no cue fires for a leg that never ran")
        XCTAssertFalse(vm.isResting)
    }

    /// The timer is the offer, not the only way through a timed movement: a user who held it off-timer,
    /// or who is stopping part-way through a multi-set plank, can record the set by hand. This is the
    /// only path that banks their work - a skip discards the exercise's sets entirely.
    func testAHoldsSetCanBeRecordedWithoutEverStartingTheTimer() throws {
        let spy = SpyRestFeedback()
        let vm = makeViewModel(perSideHoldWorkout(sets: 2, seconds: 20), clock: { self.start }, feedback: spy)
        let holdStepID = try XCTUnwrap(vm.currentStep?.id)

        vm.completeSet()

        XCTAssertFalse(vm.isHolding)
        XCTAssertEqual(vm.completedSets[holdStepID], [CompletedSet(reps: nil, durationSeconds: 20)],
                       "the set is banked at its prescribed target, as a rep-based one would be")
        XCTAssertEqual(vm.currentSet, 2, "and the exercise advances to its next set")
        XCTAssertEqual(vm.holdSide, 1, "which opens back on side 1")
        XCTAssertEqual(spy.completions, 0, "a manual completion is not a countdown reaching zero")
        XCTAssertTrue(vm.isResting, "and it paces the next effort like any other completed set")
    }

    /// Recording a hold by hand from the second side of a per-side set banks the whole set once - the
    /// side counter is bookkeeping for the timer, never a second set the user still owes.
    func testManualCompletionFromTheSecondSideRecordsOneSet() {
        var clock = start
        let vm = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { clock })

        vm.startHold()
        clock = start.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock) // side 1 done -> parked on side 2
        XCTAssertEqual(vm.holdSide, 2)

        vm.completeSet()

        XCTAssertEqual(vm.completedSetCount, 1, "one set, not one per side")
        XCTAssertEqual(vm.holdSide, 1)
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up", "the single-set hold is done")
    }

    private func swappableHoldViewModel(_ engine: StubSwapEngine) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            workout: perSideHoldWorkout(seconds: 20),
            swapEngine: engine, user: makeUser(), recentLogs: [], sessionPolicy: .default,
            now: { self.start }
        )
    }

    /// A hold leg **never** survives the player being torn down, however little time had passed and
    /// whatever the snapshot says: the user stopped holding when they left the screen. It comes back
    /// idle, owing the same side, for them to start again deliberately.
    ///
    /// This is the rule that closed a defect three separate guards could not. Restoring the countdown -
    /// running, frozen, or frozen-at-zero - always ended the same way: the player's ticker reached zero
    /// moments after the screen appeared, fired the cue, and banked a `CompletedSet` for work nobody
    /// did. The cause was modelling a hold on the rest timer, and the two are not alike here: resting
    /// continues while you are away from the screen, planking does not.
    func testAHoldLegNeverSurvivesARelaunch() async throws {
        let store = InMemoryActiveSessionStore()
        let spy = SpyRestFeedback()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.startHold() // 30s, deadline start+30

        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)
        XCTAssertNil(saved.hold, "a bilateral leg on side 1 leaves nothing to carry at all")

        // Relaunched 8 seconds later - well inside the leg the user was mid-way through.
        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(8) }, feedback: spy)

        XCTAssertFalse(resumed.isHolding, "the leg does not come back counting")
        XCTAssertFalse(resumed.isHoldPaused, "nor frozen, waiting to be un-frozen")
        XCTAssertEqual(resumed.holdRemaining(asOf: start.addingTimeInterval(8)), 0)
        XCTAssertTrue(resumed.canStartHold, "the player offers Start hold again")

        // The player's ticker runs from the moment the resumed session is on screen, and the on-appear
        // rest resume runs with it. Neither may complete a leg that was never restarted.
        resumed.resumeHold(asOf: start.addingTimeInterval(8))
        resumed.completeHoldIfElapsed(asOf: start.addingTimeInterval(8))

        XCTAssertEqual(resumed.completedSetCount, 0, "no set is banked for work nobody did")
        XCTAssertEqual(spy.completions, 0, "and no cue fires")
        XCTAssertFalse(resumed.isResting)
    }

    /// The same holds for a leg frozen on the way out (backgrounding, or closing the player) and resumed
    /// much later - the door the previous guard left open, since a frozen remainder has no deadline to
    /// test against.
    func testAFrozenHoldLegDoesNotComeBackEither() async throws {
        let store = InMemoryActiveSessionStore()
        let spy = SpyRestFeedback()
        let original = ActiveSessionViewModel(
            workout: perSideHoldWorkout(seconds: 20), store: store, userId: "u1", now: { self.start }
        )
        original.start()
        original.startHold()
        original.completeHoldIfElapsed(asOf: start.addingTimeInterval(20)) // side 1 done -> owes side 2
        original.startHold()
        original.pauseHold(asOf: start.addingTimeInterval(25)) // frozen with 15s left
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(
            state: saved, now: { self.start.addingTimeInterval(86_400) }, feedback: spy
        )
        resumed.start()
        resumed.resumeHold(asOf: start.addingTimeInterval(86_400)) // what onAppear used to do

        XCTAssertFalse(resumed.isHolding)
        XCTAssertEqual(resumed.holdSide, 2, "but the side they still owe is preserved")
        XCTAssertEqual(resumed.completedSetCount, 0)
        XCTAssertEqual(spy.completions, 0)
    }

    /// Within a live session a hold still pauses and resumes across backgrounding - the interruption the
    /// user is actually present for. Only the teardown boundary drops the leg.
    func testBackgroundingWithinTheSessionStillFreezesAndResumesTheLeg() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        vm.startHold() // 30s

        clock = start.addingTimeInterval(10)
        vm.pauseHold(asOf: clock)
        XCTAssertTrue(vm.isHoldPaused)

        clock = start.addingTimeInterval(200) // a long banner, or a glance at another app
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 20, "frozen, not drawn down")

        vm.resumeHold(asOf: clock)
        XCTAssertFalse(vm.isHoldPaused)
        XCTAssertEqual(vm.holdRemaining(asOf: start.addingTimeInterval(205)), 15)
    }

    /// A rest that ran out while the app was gone is simply over: restoring it would have the overlay's
    /// first tick fire a completion cue for a rest the user is not in. The same class as the hold's
    /// phantom set, and the reason both timers now share one `Countdown` - the fix lands on both.
    func testRestoreDropsARestThatAlreadyRanOut() async throws {
        let store = InMemoryActiveSessionStore()
        let spy = SpyRestFeedback()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.completeSet() // opens a 30s rest, deadline start+30
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        // Relaunched long after that rest would have ended.
        let resumed = ActiveSessionViewModel(
            state: saved, now: { self.start.addingTimeInterval(600) }, feedback: spy
        )
        resumed.completeRestIfElapsed(asOf: start.addingTimeInterval(600))

        XCTAssertFalse(resumed.isResting, "an expired rest is over, not waiting to fire")
        XCTAssertEqual(spy.completions, 0, "no cue for a rest the user is not in")
        XCTAssertEqual(resumed.currentStep?.prescription.exercise.id, "push_up", "the position is unchanged")
    }

    /// A per-side set the user is *between* the sides of survives a relaunch: the snapshot carries the
    /// side even with nothing running, so they come back owing side 2 rather than silently repeating
    /// side 1 and doing three legs of a two-leg set.
    func testRestoreKeepsTheSideOfAPerSideHoldBetweenLegs() async throws {
        let store = InMemoryActiveSessionStore()
        let original = ActiveSessionViewModel(
            workout: perSideHoldWorkout(seconds: 20), store: store, userId: "u1", now: { self.start }
        )
        original.start()
        original.startHold()
        original.completeHoldIfElapsed(asOf: start.addingTimeInterval(20)) // side 1 done, nothing running
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(60) })

        XCTAssertFalse(resumed.isHolding)
        XCTAssertEqual(resumed.holdSide, 2)
        XCTAssertEqual(resumed.completedSetCount, 0)
        XCTAssertTrue(resumed.canStartHold)
    }

    /// The session clock is still measured (US-O03 hides it, it does not remove it), so the completion
    /// summary the user finally sees still reports the total they worked.
    func testTotalDurationStillReachesTheCompletionSummary() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        vm.start()

        clock = start.addingTimeInterval(11 * 60)
        while !vm.isComplete { vm.completeSet() }

        XCTAssertEqual(vm.summary?.durationMinutes, 11)
    }

    // MARK: - Swap (US-K03)

    /// A stub engine so the swap's view-model behavior is driven deterministically, decoupled from the
    /// deterministic swap step (which `ExerciseSwapTests` owns). It records what it was handed - the
    /// slot and the session snapshot - and returns a configurable outcome.
    private final class StubSwapEngine: WorkoutEngineProtocol {
        var outcome: SwapOutcome
        private(set) var swapCallCount = 0
        private(set) var lastPrescriptionID: UUID?
        private(set) var lastSnapshotExerciseIDs: [String] = []
        /// The whole snapshot, so a test can assert the block structure the swap step needs to tell a
        /// set-adjustable training block from a structural bookend.
        private(set) var lastSnapshot: Workout?
        /// The policy the player handed the engine, so a test can prove the session's program - and
        /// with it the cold-start Start Seed (US-O02) - reaches the swap step.
        private(set) var lastSessionPolicy: SessionPolicy?
        /// Runs inside `swapExercise` before the outcome returns, so a test can mutate the view model
        /// mid-await (e.g. advance off the exercise) and exercise the stale-result guard.
        var onSwap: (() -> Void)?

        init(outcome: SwapOutcome) { self.outcome = outcome }

        func generateWorkout(
            requestedMinutes: Int, user: User, recentLogs: [WorkoutLog], sessionPolicy: SessionPolicy
        ) async throws -> Workout {
            fatalError("the swap tests never generate")
        }

        func swapExercise(
            _ prescription: PrescribedExercise,
            in workout: Workout,
            user: User,
            recentLogs: [WorkoutLog],
            sessionPolicy: SessionPolicy
        ) async throws -> SwapOutcome {
            swapCallCount += 1
            lastPrescriptionID = prescription.id
            lastSnapshotExerciseIDs = workout.blocks.flatMap(\.exercises).map(\.exercise.id)
            lastSnapshot = workout
            lastSessionPolicy = sessionPolicy
            onSwap?()
            return outcome
        }
    }

    /// A minimal discipline-phase user for the swap seam (the stub ignores it; the end-to-end test
    /// exercises the real engine's filtering with it).
    private func makeUser() -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: start,
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: false, injuries: [], typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 1,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            )
        )
    }

    /// A substitute prescription the stub can hand back, so a swap's replacement is assertable.
    private func substitutePrescription(_ id: String, sets: Int = 3, reps: Int = 10, rest: Int = 45) -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(), exercise: repExercise(id: id), sets: sets, reps: reps, durationSeconds: nil, restSeconds: rest
        )
    }

    private func makeSwapViewModel(
        engine: StubSwapEngine,
        sessionPolicy: SessionPolicy = .default
    ) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            workout: sampleWorkout(),
            swapEngine: engine,
            user: makeUser(),
            recentLogs: [],
            sessionPolicy: sessionPolicy,
            now: { self.start }
        )
    }

    /// The player hands the swap step the policy the session was generated against, so a substitute is
    /// sized by the same Step 6 levers as the rest of the lineup - including the cold-start Start Seed
    /// (US-O02) - instead of the engine silently re-deriving it at the neutral defaults.
    func testSwapCarriesTheSessionsPolicy() async {
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let engine = StubSwapEngine(outcome: .noAlternative)
        let vm = makeSwapViewModel(engine: engine, sessionPolicy: policy)

        await vm.swapCurrentExercise()

        XCTAssertEqual(engine.lastSessionPolicy, policy)
    }

    /// A substitute replaces the current slot in place: the current step becomes the substitute, at
    /// whatever set count and rest the engine sized it with, and the set counter resets to 1.
    func testSwapReplacesCurrentExercise() async {
        let substitute = substitutePrescription("dips", sets: 3, reps: 10, rest: 45)
        let engine = StubSwapEngine(outcome: .substituted(substitute))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // cat_cow done -> push_up is current

        await vm.swapCurrentExercise()

        XCTAssertEqual(engine.swapCallCount, 1)
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "dips")
        XCTAssertEqual(vm.currentStep?.prescription.sets, 3, "the substitute keeps the slot's set count")
        XCTAssertEqual(vm.currentStep?.prescription.restSeconds, 45, "the substitute keeps the slot's rest")
        XCTAssertEqual(vm.currentSet, 1)
        XCTAssertFalse(vm.noSwapAlternative)
        // The rest of the session is untouched.
        XCTAssertEqual(vm.steps.map(\.prescription.exercise.id), ["cat_cow", "dips", "squat"])
    }

    /// A substitute may legitimately carry a *different* set count - the swap step spends the set-count
    /// lever to keep a capacity-grown slot inside its time budget - so the player must land the user at
    /// set 1 of the new count rather than wherever they had reached in the old one. Without the reset, a
    /// user on set 3 of 3 handed a 2-set substitute would be stranded past the end of their own slot.
    func testSwapToAFewerSetSubstituteResetsThePositionInsteadOfStrandingTheUser() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips", sets: 2)))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // cat_cow -> push_up (3 sets)
        vm.completeSet() // push_up set 1
        vm.completeSet() // push_up set 2
        XCTAssertEqual(vm.currentSet, 3, "the user is on the last set of the 3-set slot")

        await vm.swapCurrentExercise()

        XCTAssertEqual(vm.currentStep?.prescription.sets, 2, "the substitute carries its own set count")
        XCTAssertEqual(vm.currentSet, 1, "the user restarts the slot rather than sitting past its end")
        XCTAssertLessThanOrEqual(vm.currentSet, vm.currentStep!.prescription.sets)
    }

    /// The snapshot the swap step reads keeps the session's block structure, because the block decides
    /// whether the set-count lever is available at all - the assembler never adjusts the warm-up or the
    /// cooldown, so neither may a swap. Collapsing every step into one strength block would have quietly
    /// handed a warm-up stretch the training rails.
    func testSwapSnapshotPreservesBlockStructure() async {
        let engine = StubSwapEngine(outcome: .noAlternative)
        let vm = makeSwapViewModel(engine: engine)

        await vm.swapCurrentExercise() // the warm-up's cat_cow is current

        let snapshot = try? XCTUnwrap(engine.lastSnapshot)
        XCTAssertEqual(snapshot?.blocks.map(\.category), [.warmup, .strength])
        XCTAssertEqual(
            snapshot?.blocks.first?.exercises.map(\.exercise.id), ["cat_cow"],
            "the warm-up stays its own block, so the swap step can tell it is a bookend"
        )
        XCTAssertEqual(snapshot?.blocks.last?.exercises.map(\.exercise.id), ["push_up", "squat"])
    }

    /// The view model hands the swap step the *current* lineup, so a movement swapped in earlier is
    /// visible to the duplicate check and a later swap can never re-introduce it (or a still-present
    /// original) as a duplicate.
    func testSwapSnapshotReflectsCurrentLineup() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips")))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // onto push_up

        await vm.swapCurrentExercise() // push_up -> dips
        engine.outcome = .substituted(substitutePrescription("pike_push"))
        await vm.swapCurrentExercise() // dips -> pike_push

        XCTAssertTrue(engine.lastSnapshotExerciseIDs.contains("dips"), "the swapped-in movement is in the snapshot")
        XCTAssertFalse(engine.lastSnapshotExerciseIDs.contains("push_up"), "the replaced movement is gone from the snapshot")
    }

    /// Swapping after completing part of an exercise discards the recorded sets - the movement is
    /// being replaced entirely, so it never carries completed sets into the eventual log.
    func testSwapDiscardsPartialSets() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips")))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // cat_cow -> push_up
        let pushUpID = vm.currentStep!.id
        vm.completeSet() // push_up set 1 recorded; a rest opens
        XCTAssertEqual(vm.completedSets[pushUpID]?.count, 1)

        await vm.swapCurrentExercise()

        XCTAssertNil(vm.completedSets[pushUpID], "the replaced movement's partial sets are discarded")
        XCTAssertFalse(vm.isResting, "the swap ends any lingering rest")
        let dips = vm.loggedExercises().first { $0.exerciseId == "dips" }
        XCTAssertEqual(dips?.completedSets.count, 0)
    }

    /// If the user advances off the exercise while the swap is in flight (Complete set / Skip stay
    /// tappable during the await), the stale substitute is discarded entirely - it never resets the
    /// now-current exercise's set counter or resurrects the already-passed slot into the lineup.
    func testSwapDiscardsStaleResultWhenUserAdvancesMidFlight() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips")))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // cat_cow -> push_up (the slot being swapped)

        // Mid-await, the user skips past push_up onto squat.
        engine.onSwap = { vm.skipExercise() }
        await vm.swapCurrentExercise()

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "the user's advance stands")
        XCTAssertEqual(vm.currentSet, 1, "squat's set counter is untouched by the stale swap")
        XCTAssertEqual(vm.steps.map(\.prescription.exercise.id), ["cat_cow", "push_up", "squat"],
                       "no resurrected or substituted slot - the stale result is dropped")
        XCTAssertFalse(vm.steps.contains { $0.prescription.exercise.id == "dips" },
                       "the stale substitute never enters the lineup")
    }

    /// If the user finishes the session on the final exercise while its swap is in flight (Complete
    /// set stays tappable, and finishing the last exercise leaves `currentStepIndex` unchanged so the
    /// slot's id still matches), the stale substitute is discarded - it never overwrites the completed
    /// final exercise's recorded sets or mutates state after the session ended.
    func testSwapDiscardsStaleResultWhenSessionFinishesMidFlight() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips")))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // cat_cow -> push_up
        vm.completeSet(); vm.completeSet(); vm.completeSet() // push_up (3 sets) -> squat, the final slot
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")

        // Mid-await, the user completes squat's two sets, finishing the session.
        engine.onSwap = { vm.completeSet(); vm.completeSet() }
        await vm.swapCurrentExercise()

        XCTAssertTrue(vm.isComplete, "the session stays finished")
        XCTAssertEqual(vm.steps.map(\.prescription.exercise.id), ["cat_cow", "push_up", "squat"],
                       "no substituted slot - the stale result is dropped")
        XCTAssertFalse(vm.steps.contains { $0.prescription.exercise.id == "dips" },
                       "the stale substitute never enters the lineup")
        let squatLog = vm.loggedExercises().first { $0.exerciseId == "squat" }
        XCTAssertEqual(squatLog?.completedSets.count, 2,
                       "the finished exercise's recorded sets are intact - not wiped by an un-performed substitute")
        XCTAssertEqual(squatLog?.skipped, false)
    }

    /// When the engine finds no safe, in-budget peer, the original slot stays and the honest
    /// "no alternative" flag flips so the UI can say so rather than forcing an unsafe substitution.
    func testSwapNoAlternativeKeepsSlotAndFlags() async {
        let engine = StubSwapEngine(outcome: .noAlternative)
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // onto push_up

        await vm.swapCurrentExercise()

        XCTAssertTrue(vm.noSwapAlternative)
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up", "the original slot is kept")
        XCTAssertEqual(vm.steps.map(\.prescription.exercise.id), ["cat_cow", "push_up", "squat"])
    }

    /// The "no alternative" notice is about the slot the user is on, so advancing off it clears the flag.
    func testNoAlternativeClearsOnAdvance() async {
        let engine = StubSwapEngine(outcome: .noAlternative)
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // onto push_up
        await vm.swapCurrentExercise()
        XCTAssertTrue(vm.noSwapAlternative)

        vm.skipExercise() // move to squat
        XCTAssertFalse(vm.noSwapAlternative)
    }

    /// With no engine wired (e.g. a preview), swap is unavailable and calling it is a harmless no-op.
    func testSwapUnavailableWithoutEngine() async {
        let vm = makeViewModel(clock: { self.start }) // no swap engine
        vm.completeSet() // onto push_up

        XCTAssertFalse(vm.canSwap)
        await vm.swapCurrentExercise()
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up", "unchanged - swap is a no-op")
    }

    /// End-to-end through the real deterministic engine and bundled library (the PRD validation at the
    /// player level): swapping a real movement yields a same-pillar, same-pattern peer that preserves
    /// the slot's set count and rest, never the same movement.
    func testSwapEndToEndYieldsSamePillarPatternPeer() async throws {
        let exerciseService = try MockExerciseService()
        let library = try await exerciseService.exercises()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        // At the movement's own default, the target Step 6 gives a user with no history of it - so the
        // slot's budget is the one the assembler would really have sized this session with.
        let slot = PrescribedExercise(
            id: UUID(), exercise: target, sets: 3, reps: try XCTUnwrap(target.defaultReps),
            durationSeconds: nil, restSeconds: SessionAssembly.strengthRestSeconds
        )
        let block = WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [slot])
        let workout = Workout(
            id: UUID(), createdAt: start, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 15, wasReturn: false, blocks: [block]
        )
        let engine = MockWorkoutEngine(exerciseService: exerciseService)
        let vm = ActiveSessionViewModel(workout: workout, swapEngine: engine, user: makeUser(), recentLogs: [], now: { self.start })

        await vm.swapCurrentExercise()

        let swapped = try XCTUnwrap(vm.currentStep?.prescription)
        XCTAssertNotEqual(swapped.exercise.id, "push_standard", "a swap returns a different movement")
        XCTAssertEqual(swapped.exercise.pillar, .strength, "same pillar")
        XCTAssertEqual(swapped.exercise.movementPattern, .push, "same movement pattern")
        XCTAssertEqual(swapped.sets, slot.sets, "a default-sized slot is in budget at its own set count")
        XCTAssertEqual(swapped.restSeconds, slot.restSeconds, "rest preserved")
        XCTAssertTrue(swapped.reps != nil || swapped.durationSeconds != nil, "a fresh capacity-relative target")
        XCTAssertFalse(vm.noSwapAlternative)
    }

    // MARK: - Background & resume (US-K04)

    /// A helper VM wired to persist to `store` under `userId`, so the background/resume tests can
    /// drive the player and then inspect what was saved.
    private func persistingViewModel(
        _ store: InMemoryActiveSessionStore,
        userId: String = "u1",
        workout: Workout? = nil,
        clock: @escaping () -> Date
    ) -> ActiveSessionViewModel {
        ActiveSessionViewModel(workout: workout ?? sampleWorkout(), store: store, userId: userId, now: clock)
    }

    /// The snapshot captures the exact play state - current position, completed work, and the
    /// session-clock origin - so it can be restored later.
    func testSnapshotCapturesPlayState() {
        let vm = makeViewModel(clock: { self.start })
        vm.start()
        vm.completeSet() // finish the 1-set warm-up -> onto push_up, set 1

        let snapshot = vm.snapshot()

        XCTAssertEqual(snapshot.currentStepIndex, 1)
        XCTAssertEqual(snapshot.currentSet, 1)
        XCTAssertEqual(snapshot.slots.map(\.prescription.exercise.id), ["cat_cow", "push_up", "squat"])
        XCTAssertEqual(snapshot.startedAt, start)
        XCTAssertEqual(snapshot.completedSets.values.reduce(0) { $0 + $1.count }, 1)
    }

    /// Every meaningful change is persisted, so a session interrupted by a relaunch is recoverable.
    func testCompleteSetPersistsSnapshot() async throws {
        let store = InMemoryActiveSessionStore()
        let vm = persistingViewModel(store, clock: { self.start })
        vm.start()
        vm.completeSet() // onto push_up, set 1

        await vm.persistenceTask?.value
        let saved = try await store.load(for: "u1")

        XCTAssertEqual(saved?.currentStepIndex, 1)
        XCTAssertEqual(saved?.currentSet, 1)
        XCTAssertEqual(saved?.completedSets.values.reduce(0) { $0 + $1.count }, 1)
    }

    /// Restoring from a saved snapshot resumes the exact position and preserves completed work.
    func testRestoreResumesExactPosition() async throws {
        let store = InMemoryActiveSessionStore()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.completeSet() // warm-up done -> push_up set 1 (rest opens)
        original.completeSet() // push_up set 1 done -> set 2
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.start })

        XCTAssertFalse(resumed.isComplete)
        XCTAssertEqual(resumed.currentStepIndex, 1)
        XCTAssertEqual(resumed.currentSet, 2)
        XCTAssertEqual(resumed.currentStep?.prescription.exercise.id, "push_up")
        XCTAssertEqual(resumed.completedSetCount, 2, "cat_cow set + push_up set 1 carry over")
        XCTAssertEqual(resumed.steps.map(\.prescription.exercise.id), ["cat_cow", "push_up", "squat"])
    }

    /// Elapsed time is measured from the persisted origin, so it survives a relaunch that happened at
    /// an unknown-later moment rather than restarting from zero.
    func testRestorePreservesElapsedAcrossRelaunch() async throws {
        let store = InMemoryActiveSessionStore()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.completeSet()
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        // Relaunch 90 seconds later.
        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(90) })
        resumed.start() // idempotent: keeps the restored origin rather than resetting

        XCTAssertEqual(resumed.elapsed(asOf: start.addingTimeInterval(90)), 90)
    }

    /// A rest that was still running when the app was killed resumes counting from its absolute
    /// deadline after a relaunch.
    func testRestoreResumesRunningRest() async throws {
        let store = InMemoryActiveSessionStore()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.completeSet() // opens a 30s rest, deadline start+30
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(5) })

        XCTAssertTrue(resumed.isResting)
        XCTAssertFalse(resumed.isRestPaused)
        XCTAssertEqual(resumed.restRemaining(asOf: start.addingTimeInterval(5)), 25)
    }

    /// A rest paused on backgrounding is persisted with its frozen remainder, so a relaunch resumes it
    /// from exactly where it stopped rather than blowing past.
    func testRestoreResumesPausedRest() async throws {
        let store = InMemoryActiveSessionStore()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.completeSet() // 30s rest, deadline start+30
        original.pauseRest(asOf: start.addingTimeInterval(10)) // freeze with 20s remaining
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(60) })
        XCTAssertTrue(resumed.isResting)
        XCTAssertTrue(resumed.isRestPaused)
        XCTAssertEqual(resumed.restRemaining(asOf: start.addingTimeInterval(60)), 20, "frozen remainder held across relaunch")

        // Foregrounding reschedules from the remainder.
        resumed.resumeRest(asOf: start.addingTimeInterval(100))
        XCTAssertEqual(resumed.restRemaining(asOf: start.addingTimeInterval(105)), 15)
    }

    /// When a resumed player is presented while the app is already active, no scene-phase change fires,
    /// so the player's on-appear (start() then resumeRest) is the only thing that un-freezes a restored
    /// paused rest. Proves that path reschedules the deadline and the countdown resumes.
    func testOnAppearResumeUnfreezesRestoredPausedRest() async throws {
        let store = InMemoryActiveSessionStore()
        let original = persistingViewModel(store, clock: { self.start })
        original.start()
        original.completeSet() // 30s rest, deadline start+30
        original.pauseRest(asOf: start.addingTimeInterval(10)) // freeze with 20s remaining
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(200) })
        XCTAssertTrue(resumed.isRestPaused, "restored rest starts frozen")

        // Mirror ActiveSessionView.onAppear on an already-active app: start() then resumeRest.
        resumed.start()
        resumed.resumeRest(asOf: start.addingTimeInterval(200))

        XCTAssertFalse(resumed.isRestPaused, "on-appear resume un-freezes the rest")
        XCTAssertEqual(resumed.restRemaining(asOf: start.addingTimeInterval(205)), 15, "countdown resumes rather than holding the frozen remainder")
    }

    /// Completing the session clears the persisted snapshot - a finished session is not resumable.
    func testCompletionClearsPersistedSession() async throws {
        let store = InMemoryActiveSessionStore()
        let vm = persistingViewModel(store, clock: { self.start })
        vm.start()
        while !vm.isComplete { vm.completeSet() }
        await vm.persistenceTask?.value

        XCTAssertTrue(vm.isComplete)
        let saved = try await store.load(for: "u1")
        XCTAssertNil(saved, "a completed session is cleared, not left resumable")
    }

    /// A swap persists the new lineup, so a resume after a swap restores the substitute rather than
    /// the movement the user replaced.
    func testSwapPersistsNewLineup() async throws {
        let store = InMemoryActiveSessionStore()
        let substitute = substitutePrescription("dips", sets: 3, reps: 10, rest: 45)
        let engine = StubSwapEngine(outcome: .substituted(substitute))
        let vm = ActiveSessionViewModel(
            workout: sampleWorkout(), swapEngine: engine, user: makeUser(), recentLogs: [],
            store: store, userId: "u1", now: { self.start }
        )
        vm.completeSet() // onto push_up

        await vm.swapCurrentExercise()
        await vm.persistenceTask?.value

        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.slots.map(\.prescription.exercise.id), ["cat_cow", "dips", "squat"])
        XCTAssertEqual(saved.currentStepIndex, 1)
        XCTAssertEqual(saved.currentSet, 1)
    }

    /// Without a store wired (previews), persistence is a harmless no-op and never traps.
    func testNoPersistenceWithoutStore() {
        let vm = makeViewModel(clock: { self.start }) // no store/userId
        vm.start()
        vm.completeSet()

        XCTAssertNil(vm.persistenceTask, "no store means no persistence task is launched")
    }

    /// A truncated or corrupt snapshot (an out-of-range index) resumes safely, clamped into range,
    /// rather than trapping on an out-of-bounds access.
    func testRestoreClampsOutOfRangeIndex() {
        let base = ActiveSessionState(fresh: sampleWorkout())
        let corrupt = ActiveSessionState(
            workout: base.workout, slots: base.slots,
            currentStepIndex: 99, currentSet: 0,
            completedSets: [:], skippedStepIDs: [], startedAt: start, rest: nil
        )

        let resumed = ActiveSessionViewModel(state: corrupt, now: { self.start })

        XCTAssertEqual(resumed.currentStepIndex, resumed.steps.count - 1)
        XCTAssertEqual(resumed.currentSet, 1, "a non-positive set clamps up to the first set")
        XCTAssertFalse(resumed.isComplete)
    }

    // MARK: - Completion recording & summary (US-L01)

    /// Captures the completion recordings so a test can assert the written log and its context. Also
    /// records perceived-difficulty rating updates (US-L02) - keyed by log id, in call order - so a test
    /// can assert the rating landed on the right record.
    private actor SpyCompletionService: SessionCompletionServiceProtocol {
        private(set) var recorded: [WorkoutLog] = []
        private(set) var lastRecentLogs: [WorkoutLog] = []
        private(set) var ratings: [(logId: UUID, difficulty: PerceivedDifficulty?)] = []

        func recordCompletedSession(_ log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws {
            recorded.append(log)
            lastRecentLogs = recentLogs
        }

        func recordPerceivedDifficulty(_ difficulty: PerceivedDifficulty?, forLog log: WorkoutLog) async throws {
            ratings.append((log.id, difficulty))
        }
    }

    /// A session tagged as a single-focus Return at 20 requested minutes, so the completion log's
    /// copied shape/focus/return facts are all assertable and distinct from the defaults.
    private func completionWorkout() -> Workout {
        Workout(
            id: UUID(), createdAt: start, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 20, wasReturn: true, blocks: sampleWorkout().blocks
        )
    }

    /// On completion the player writes a `WorkoutLog` with the requested-vs-completed minutes and the
    /// session facts copied straight off the played `Workout` (US-L01 validation: requested 20,
    /// completed ~14).
    func testCompletionWritesLogWithSessionFacts() async throws {
        var clock = start
        let spy = SpyCompletionService()
        let priorLog = completionWorkout() // reused only for its id below; a throwaway context log
        let context = [WorkoutLog(
            id: UUID(), workoutId: priorLog.id, completedAt: start, requestedMinutes: 10,
            durationMinutes: 10, wasReturn: false, shape: .blend, focusPillar: nil,
            perceivedDifficulty: nil, exercises: []
        )]
        let vm = ActiveSessionViewModel(
            workout: completionWorkout(), user: makeUser(), recentLogs: context,
            completionService: spy, now: { clock }
        )
        vm.start()

        clock = start.addingTimeInterval(14 * 60) // finish 14 minutes after starting
        while !vm.isComplete { vm.completeSet() }
        await vm.completionTask?.value

        let recorded = await spy.recorded
        XCTAssertEqual(recorded.count, 1, "the completion is recorded exactly once")
        let log = try XCTUnwrap(recorded.first)
        XCTAssertEqual(log.workoutId, vm.workout.id)
        XCTAssertEqual(log.requestedMinutes, 20)
        XCTAssertEqual(log.durationMinutes, 14, "the actually-completed duration, not the requested 20")
        XCTAssertEqual(log.shape, .singleFocus)
        XCTAssertEqual(log.focusPillar, .strength)
        XCTAssertTrue(log.wasReturn, "the Return flag is copied off the session, not re-derived")
        XCTAssertEqual(log.exercises.count, 3)
        XCTAssertNil(log.perceivedDifficulty, "the rating is collected by US-L02")

        let seenRecentLogs = await spy.lastRecentLogs
        XCTAssertEqual(seenRecentLogs.count, 1, "the recorder is handed the history for the consistency fold")
    }

    /// A long backgrounded stretch keeps the wall-clock session clock running (US-K01/K04), but the
    /// logged completed duration is capped at the session's requestedMinutes so a distraction can't
    /// inflate Default Duration learning's EWMA (US-F04) toward the 60-min cap.
    func testCompletedDurationCappedAtRequestedMinutes() async throws {
        var clock = start
        let spy = SpyCompletionService()
        let vm = ActiveSessionViewModel(
            workout: completionWorkout(), user: makeUser(), recentLogs: [],
            completionService: spy, now: { clock }
        )
        vm.start()

        clock = start.addingTimeInterval(80 * 60) // finish 80 minutes after starting (backgrounded)
        while !vm.isComplete { vm.completeSet() }
        await vm.completionTask?.value

        let recorded = await spy.recorded
        let log = try XCTUnwrap(recorded.first)
        XCTAssertEqual(log.durationMinutes, 20, "capped at the requested 20, not the raw 80 wall-clock minutes")
        XCTAssertEqual(vm.summary?.durationMinutes, 20, "the celebration summary is capped too")
    }

    /// With no completion service wired (previews), completing the session records nothing and never
    /// traps.
    func testNoCompletionRecordingWithoutService() async {
        let vm = makeViewModel(clock: { self.start }) // no completion service / user
        vm.start()
        while !vm.isComplete { vm.completeSet() }

        XCTAssertTrue(vm.isComplete)
        XCTAssertNil(vm.completionTask, "no completion service means no recording task is launched")
    }

    /// The template summary reflects the finished session: its completed duration, set count, and the
    /// muscle/mobility coverage it actually produced.
    func testSummaryReflectsCompletedSession() {
        var clock = start
        let vm = makeViewModel(clock: { clock })
        XCTAssertNil(vm.summary, "no summary before completion")

        vm.start()
        clock = start.addingTimeInterval(10 * 60) // ten minutes
        while !vm.isComplete { vm.completeSet() }

        let summary = vm.summary
        XCTAssertEqual(summary?.durationMinutes, 10)
        XCTAssertEqual(summary?.completedSetCount, 6)
        XCTAssertEqual(summary?.completedExerciseCount, 3)
        // sampleWorkout is all strength (cat_cow core-hold, push_up push, squat push).
        XCTAssertEqual(summary?.pillars, [.strength])
        XCTAssertEqual(summary?.movementPatterns, [.push, .core])
    }

    /// A skipped exercise is excluded from the summary's coverage but the session still records and
    /// completes.
    func testSummaryExcludesSkippedFromCoverage() {
        let vm = makeViewModel(clock: { self.start })
        vm.start()
        vm.completeSet() // cat_cow (core) done -> push_up
        vm.skipExercise() // skip push_up -> squat
        while !vm.isComplete { vm.completeSet() } // finish squat

        let summary = vm.summary
        XCTAssertEqual(summary?.skippedExerciseCount, 1)
        // push_up (push) was skipped; cat_cow (core) and squat (push) remain -> patterns push, core.
        XCTAssertEqual(summary?.completedExerciseCount, 2)
        XCTAssertEqual(summary?.movementPatterns, [.push, .core])
    }

    // MARK: - Perceived-difficulty rating (US-L02)

    /// Rating the finished session records the value on the view model and persists it - via the
    /// completion service - onto the *same* log id the initial completion write used, so the next
    /// session's Asymmetric Ramp reads it (US-L02 validation).
    func testRatingPersistsOntoTheCompletedLog() async throws {
        var clock = start
        let spy = SpyCompletionService()
        let vm = ActiveSessionViewModel(
            workout: completionWorkout(), user: makeUser(), recentLogs: [],
            completionService: spy, now: { clock }
        )
        vm.start()
        clock = start.addingTimeInterval(14 * 60)
        while !vm.isComplete { vm.completeSet() }
        await vm.completionTask?.value

        let recorded = await spy.recorded
        let writtenLog = try XCTUnwrap(recorded.first)
        XCTAssertNil(writtenLog.perceivedDifficulty, "the initial completion write is unrated")

        vm.rate(.tooHard)
        await vm.completionTask?.value

        XCTAssertEqual(vm.perceivedDifficulty, .tooHard)
        let ratings = await spy.ratings
        XCTAssertEqual(ratings.count, 1, "the rating is persisted exactly once")
        XCTAssertEqual(ratings.first?.logId, writtenLog.id, "onto the same log the completion wrote")
        XCTAssertEqual(ratings.first?.difficulty, .tooHard)
        let recordedCount = await spy.recorded.count
        XCTAssertEqual(recordedCount, 1, "rating does not re-run the full completion recording")
    }

    /// Re-tapping a different rating overwrites the last; the newest value is what persists.
    func testRatingCanBeChanged() async throws {
        let spy = SpyCompletionService()
        let vm = ActiveSessionViewModel(
            workout: completionWorkout(), user: makeUser(), recentLogs: [],
            completionService: spy, now: { self.start }
        )
        vm.start()
        while !vm.isComplete { vm.completeSet() }
        await vm.completionTask?.value

        vm.rate(.tooEasy)
        vm.rate(.justRight)
        await vm.completionTask?.value

        XCTAssertEqual(vm.perceivedDifficulty, .justRight)
        let ratings = await spy.ratings
        XCTAssertEqual(ratings.map(\.difficulty), [.tooEasy, .justRight], "both taps persist, newest last")
    }

    /// Rating is only possible once the session completes - a mid-session call is a no-op.
    func testRatingBeforeCompletionIsNoOp() async {
        let spy = SpyCompletionService()
        let vm = ActiveSessionViewModel(
            workout: completionWorkout(), user: makeUser(), recentLogs: [],
            completionService: spy, now: { self.start }
        )
        vm.start()

        vm.rate(.tooHard)

        XCTAssertNil(vm.perceivedDifficulty, "no rating is recorded before the session is complete")
        await vm.completionTask?.value
        let ratings = await spy.ratings
        XCTAssertTrue(ratings.isEmpty)
    }

    /// Skipping the rating leaves the session unrated - the log the completion wrote keeps its nil
    /// rating and nothing extra is persisted.
    func testUnratedSessionPersistsNothingExtra() async throws {
        let spy = SpyCompletionService()
        let vm = ActiveSessionViewModel(
            workout: completionWorkout(), user: makeUser(), recentLogs: [],
            completionService: spy, now: { self.start }
        )
        vm.start()
        while !vm.isComplete { vm.completeSet() }
        await vm.completionTask?.value

        XCTAssertNil(vm.perceivedDifficulty)
        let ratings = await spy.ratings
        XCTAssertTrue(ratings.isEmpty, "no rating write without a tap")
    }

    /// With no completion service wired (previews), rating is kept in memory for the UI but persists
    /// nothing and never traps.
    func testRatingWithoutServiceIsMemoryOnly() {
        let vm = makeViewModel(clock: { self.start }) // no completion service / user
        vm.start()
        while !vm.isComplete { vm.completeSet() }

        vm.rate(.justRight)

        XCTAssertEqual(vm.perceivedDifficulty, .justRight, "the UI still reflects the tap")
        XCTAssertNil(vm.completionTask, "but nothing is persisted")
    }

    // MARK: - The player states a per-side target as per side

    /// The engine charges a per-side movement for both sides, so the player has to say so. A user handed
    /// a 30s per-side hold who holds it once does half the work per set the session was planned around -
    /// over three sets that is the whole ±1 minute budget from a single slot.
    func testTargetTextSaysPerSideForAPerSideMovement() {
        let hold = PrescribedExercise(
            id: UUID(), exercise: perSide(holdExercise(id: "side_plank")),
            sets: 3, reps: nil, durationSeconds: 30, restSeconds: 30
        )
        XCTAssertEqual(ActiveSessionView.targetText(hold), "3 × 0:30 per side")
        XCTAssertEqual(
            ActiveSessionView.targetAccessibilityText(hold),
            "3 sets of 30 second holds per side"
        )

        let reps = PrescribedExercise(
            id: UUID(), exercise: perSide(repExercise(id: "split_squat")),
            sets: 3, reps: 8, durationSeconds: nil, restSeconds: 30
        )
        XCTAssertEqual(ActiveSessionView.targetText(reps), "3 × 8 per side")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(reps), "3 sets of 8 reps per side")
    }

    /// ...and only for a per-side movement, so a two-sided target is never described as one-sided work.
    func testTargetTextOmitsPerSideForABilateralMovement() {
        let hold = holdPrescription("plank", sets: 3, seconds: 30)
        XCTAssertEqual(ActiveSessionView.targetText(hold), "3 × 0:30")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(hold), "3 sets of 30 second holds")

        let reps = repPrescription("pushup", sets: 3, reps: 8)
        XCTAssertEqual(ActiveSessionView.targetText(reps), "3 × 8")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(reps), "3 sets of 8 reps")
    }

    // MARK: - The spoken target is grammatical at every count

    /// Warm-up and cooldown slots are single-set, so VoiceOver reads the singular case on the first and
    /// last step of *every* session - the two slots a screen-reader user meets no matter how short the
    /// session is. The visual target ("1 × 0:45") is unaffected because it never spells the nouns out.
    func testSpokenTargetIsSingularForASingleSetSlot() {
        let hold = holdPrescription("cat_cow", sets: 1, seconds: 45)
        XCTAssertEqual(ActiveSessionView.targetText(hold), "1 × 0:45")
        XCTAssertEqual(
            ActiveSessionView.targetAccessibilityText(hold),
            "1 set of a 45 second hold",
            "a single-set hold reads as one set of one hold, not \"1 sets of 45 second holds\""
        )

        let reps = repPrescription("pushup", sets: 1, reps: 12)
        XCTAssertEqual(ActiveSessionView.targetText(reps), "1 × 12")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(reps), "1 set of 12 reps")
    }

    /// The rep noun pluralises on its own count, independently of the set count - a one-rep set is
    /// reachable at the bottom of a hard chain's Adaptive Overload.
    func testSpokenTargetIsSingularForASingleRep() {
        XCTAssertEqual(
            ActiveSessionView.targetAccessibilityText(repPrescription("archer", sets: 3, reps: 1)),
            "3 sets of 1 rep"
        )
        XCTAssertEqual(
            ActiveSessionView.targetAccessibilityText(repPrescription("archer", sets: 1, reps: 1)),
            "1 set of 1 rep"
        )
    }

    /// Pluralisation and the per-side suffix compose, so a single-set per-side warm-up stretch - the
    /// common bookend shape - is spoken correctly on both axes at once.
    func testSpokenTargetComposesSingularWithPerSide() {
        let hold = PrescribedExercise(
            id: UUID(), exercise: perSide(holdExercise(id: "pigeon")),
            sets: 1, reps: nil, durationSeconds: 30, restSeconds: 15
        )
        XCTAssertEqual(ActiveSessionView.targetText(hold), "1 × 0:30 per side")
        XCTAssertEqual(
            ActiveSessionView.targetAccessibilityText(hold),
            "1 set of a 30 second hold per side"
        )
    }
}
