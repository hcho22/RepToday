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

    /// A session whose strength block is a genuine even circuit - exactly three rep-based exercises at a
    /// uniform round count - bracketed by single-set warm-up and cooldown bookends, so US-CC02's rotation
    /// and "Round N of M" label can be driven end to end (the PRD's validation shape at `rounds: 3`).
    private func circuitWorkout(rounds: Int) -> Workout {
        let warmup = WorkoutBlock(
            id: UUID(), title: "Warm-up", category: .warmup,
            exercises: [holdPrescription("cat_cow", sets: 1, seconds: 30)]
        )
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [
                repPrescription("push_up", sets: rounds, reps: 12),
                repPrescription("squat", sets: rounds, reps: 15),
                repPrescription("hinge", sets: rounds, reps: 10)
            ]
        )
        let cooldown = WorkoutBlock(
            id: UUID(), title: "Cooldown", category: .cooldown,
            exercises: [holdPrescription("forward_fold", sets: 1, seconds: 30)]
        )
        return Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 20, wasReturn: false, blocks: [warmup, strength, cooldown]
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

    /// Inside a training-block circuit, completing a set rotates to the *next station* in the round
    /// rather than staying on the same exercise for its next set (US-CC02): the strength block plays one
    /// set of each exercise per round, not all sets of one exercise before the next.
    func testCompleteSetRotatesToTheNextStationInTheRound() {
        let vm = makeViewModel(clock: { self.start })
        // Move past the single-set warm-up onto the strength circuit's first station.
        vm.completeSet()
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up")
        XCTAssertEqual(vm.currentSet, 1)

        vm.completeSet()
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "the rotation moves to the next station")
        XCTAssertEqual(vm.currentSet, 1, "still round 1 - the round has not advanced")
    }

    /// Finishing the last station of a round wraps back to the first station of the next round (US-CC02),
    /// stepping the round rather than the exercise. The sample block is non-uniform (push_up 3, squat 2),
    /// so its round count is 3 and squat simply drops out of round 3.
    func testCompletingARoundWrapsToTheNextRound() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet() // finishes cat_cow (1 set) -> push_up round 1
        vm.completeSet() // push_up round 1 -> squat round 1
        vm.completeSet() // squat round 1 (round 1 done) -> back to push_up, round 2

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up")
        XCTAssertEqual(vm.currentSet, 2, "the second round starts on the first station")
        XCTAssertEqual(vm.currentRound, 2)
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

    /// Skipping an exercise after it has banked sets across earlier rounds discards those sets, so a
    /// skipped exercise never carries completed sets into the eventual log (US-CC02: the skip also
    /// removes it from the remaining rounds).
    func testSkipAfterPartialSetsDiscardsRecordedSets() {
        let vm = makeViewModel(circuitWorkout(rounds: 3), clock: { self.start })
        vm.completeSet() // warm-up -> push_up round 1
        let pushUpID = vm.currentStep!.id
        vm.completeSet() // push_up round 1 recorded -> squat round 1
        vm.completeSet() // squat round 1 -> hinge round 1
        vm.completeSet() // hinge round 1 -> back to push_up, round 2 (push_up carries its round-1 set)
        XCTAssertEqual(vm.currentStep?.id, pushUpID)
        XCTAssertEqual(vm.completedSets[pushUpID]?.count, 1)

        vm.skipExercise() // abandon push_up mid-circuit

        XCTAssertTrue(vm.skippedStepIDs.contains(pushUpID))
        XCTAssertNil(vm.completedSets[pushUpID], "the already-recorded sets are discarded on skip")

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

    /// The eventual-log rows carry each exercise's completed sets, pillar/pattern, and skip flag - and
    /// the rotation order never changes the aggregate: push_up still logs its full set count and the
    /// skipped squat logs none.
    func testLoggedExercisesReflectTracking() {
        let vm = makeViewModel(clock: { self.start })
        vm.completeSet()  // cat_cow -> push_up round 1
        vm.completeSet()  // push_up round 1 -> squat round 1
        vm.skipExercise() // skip squat: it drops from every round, push_up finishes its rounds
        while !vm.isComplete { vm.completeSet() } // push_up rounds 2 and 3 -> complete

        let logged = vm.loggedExercises()
        XCTAssertEqual(logged.count, 3)

        let pushUp = logged.first { $0.exerciseId == "push_up" }
        XCTAssertEqual(pushUp?.completedSets.count, 3, "push_up logs all three rounds despite the rotation")
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

    // MARK: - Circuit rotation (US-CC02)

    /// The US-CC02 validation test: a strength block of exactly three exercises at a uniform three sets
    /// plays A, B, C, A, B, C, A, B, C across three rounds, each labelled "Round N of 3", and by the end
    /// every exercise has logged exactly three completed sets - the rotation order never changes the
    /// aggregate. This is the failure indicator the PRD names, inverted: not A, A, A, B, B, B, C, C, C.
    func testStrengthBlockRotatesABCAcrossRoundsWithRoundLabels() {
        let vm = makeViewModel(circuitWorkout(rounds: 3), clock: { self.start })
        vm.completeSet() // past the single-set warm-up onto the strength circuit

        var visited: [(id: String, round: Int, rounds: Int)] = []
        var guardCount = 0
        while let round = vm.currentRound, let rounds = vm.circuitRoundCount, guardCount < 20 {
            guardCount += 1
            visited.append((vm.currentStep!.prescription.exercise.id, round, rounds))
            vm.completeSet()
        }

        XCTAssertEqual(
            visited.map(\.id),
            ["push_up", "squat", "hinge", "push_up", "squat", "hinge", "push_up", "squat", "hinge"],
            "the block rotates one set of each exercise per round, not all sets of one before the next"
        )
        XCTAssertEqual(visited.map(\.round), [1, 1, 1, 2, 2, 2, 3, 3, 3])
        XCTAssertTrue(visited.allSatisfy { $0.rounds == 3 }, "M is the block's uniform round count")

        while !vm.isComplete { vm.completeSet() } // flow through the cooldown to completion
        let logged = vm.loggedExercises()
        for id in ["push_up", "squat", "hinge"] {
            XCTAssertEqual(
                logged.first { $0.exerciseId == id }?.completedSets.count, 3,
                "\(id) logged its three sets by the end, whatever the rotation order"
            )
        }
    }

    /// Warm-up and cooldown bookends are not circuits (US-CC02): they carry no round and flow linearly;
    /// only the training block in between rotates as rounds.
    func testBookendsAreNotCircuitsOnlyTrainingBlocks() {
        let vm = makeViewModel(circuitWorkout(rounds: 3), clock: { self.start })

        XCTAssertNil(vm.currentRound, "the warm-up bookend has no round")
        XCTAssertNil(vm.circuitRoundCount)

        vm.completeSet() // -> strength
        XCTAssertEqual(vm.currentRound, 1, "the training block is a circuit")
        XCTAssertEqual(vm.circuitRoundCount, 3)

        while vm.currentRound != nil, !vm.isComplete { vm.completeSet() } // rotate the whole block
        XCTAssertEqual(vm.currentStep?.blockCategory, .cooldown)
        XCTAssertNil(vm.currentRound, "the cooldown bookend has no round")
        XCTAssertNil(vm.circuitRoundCount)
    }

    /// The rotation crosses two distinct rest gaps (US-CC04): a short between-station transition inside a
    /// round, and the longer between-round rest at a round boundary. Both flow through the US-K02 rest
    /// overlay so the session stays hands-free.
    func testCircuitCrossesTransitionBetweenStationsAndRoundRestBetweenRounds() {
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [
                PrescribedExercise(id: UUID(), exercise: repExercise(id: "push_up"), sets: 2, reps: 12, durationSeconds: nil, restSeconds: 45),
                PrescribedExercise(id: UUID(), exercise: repExercise(id: "squat", pattern: .squat), sets: 2, reps: 12, durationSeconds: nil, restSeconds: 45)
            ]
        )
        let workout = Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [strength]
        )
        let vm = makeViewModel(workout, clock: { self.start })

        // push_up round 1 -> squat round 1: a between-station transition.
        vm.completeSet()
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")
        XCTAssertEqual(vm.currentRound, 1)
        XCTAssertEqual(vm.restTotalSeconds, SessionAssembly.transitionSeconds, "between stations is the short fixed transition")
        vm.skipRest()

        // squat round 1 -> push_up round 2: the bounded between-round rest the engine sized.
        vm.completeSet()
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "push_up")
        XCTAssertEqual(vm.currentRound, 2)
        XCTAssertEqual(vm.restTotalSeconds, 45, "between rounds is the round rest")
    }

    /// A skip inside the circuit removes the exercise from every remaining round (US-CC02): the rotation
    /// never returns to it, it logs not-done with no completed sets, and the other stations still finish
    /// their full round count.
    func testSkipInsideCircuitRemovesExerciseFromRemainingRounds() {
        let vm = makeViewModel(circuitWorkout(rounds: 3), clock: { self.start })
        vm.completeSet() // warm-up -> push_up round 1
        vm.completeSet() // push_up round 1 -> squat round 1
        vm.skipExercise() // skip squat mid-circuit

        var seen: Set<String> = []
        var guardCount = 0
        while vm.currentRound != nil, !vm.isComplete, guardCount < 20 {
            guardCount += 1
            seen.insert(vm.currentStep!.prescription.exercise.id)
            vm.completeSet()
        }
        XCTAssertFalse(seen.contains("squat"), "the skipped station never reappears in a later round")

        while !vm.isComplete { vm.completeSet() }
        let logged = vm.loggedExercises()
        XCTAssertTrue(logged.first { $0.exerciseId == "squat" }?.skipped ?? false)
        XCTAssertEqual(logged.first { $0.exerciseId == "squat" }?.completedSets.count, 0)
        XCTAssertEqual(logged.first { $0.exerciseId == "push_up" }?.completedSets.count, 3, "the other stations still finish their rounds")
        XCTAssertEqual(logged.first { $0.exerciseId == "hinge" }?.completedSets.count, 3)
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

    /// A single-station per-side hold block, so a multi-set hold's *own* set-to-set progression can be
    /// exercised without the circuit rotation interleaving another station (a single-station circuit
    /// block plays its rounds as that one exercise's successive sets - US-CC02).
    private func singleHoldWorkout(sets: Int, seconds: Int = 20) -> Workout {
        let block = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [perSideHoldPrescription("side_plank", sets: sets, seconds: seconds)]
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
    /// it would run unseen. A single-station hold block, so round 2 of the same hold is what the rest
    /// paces toward (US-CC02).
    func testHoldCannotStartDuringRest() {
        let vm = makeViewModel(singleHoldWorkout(sets: 2), clock: { self.start })
        vm.completeSet() // round 1 recorded manually -> the between-round rest opens

        XCTAssertTrue(vm.isResting)
        XCTAssertFalse(vm.canStartHold)
        vm.startHold()
        XCTAssertFalse(vm.isHolding, "start is a no-op during rest")

        vm.skipRest()
        XCTAssertTrue(vm.canStartHold, "round 2 of the same hold is reachable once the rest ends")
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
        let vm = makeViewModel(singleHoldWorkout(sets: 2), clock: { self.start }, feedback: spy)
        let holdStepID = try XCTUnwrap(vm.currentStep?.id)

        vm.completeSet()

        XCTAssertFalse(vm.isHolding)
        XCTAssertEqual(vm.completedSets[holdStepID], [CompletedSet(reps: nil, durationSeconds: 20)],
                       "the set is banked at its prescribed target, as a rep-based one would be")
        XCTAssertEqual(vm.currentSet, 2, "and the hold advances to its next round")
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

    /// Banking the set by hand *while* a leg is running is the non-destructive way out of a hold, and
    /// the only one: "Stop hold" records nothing and "Skip" discards every set already banked for the
    /// exercise. It takes the countdown down without firing the cue - the user came out of it early,
    /// which is not the timer's verdict - records exactly one set, and opens the rest like any other
    /// completed set.
    func testCompletingASetByHandMidLegBanksItOnceAndEndsTheCountdown() throws {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(singleHoldWorkout(sets: 3), clock: { clock }, feedback: spy)
        let holdStepID = try XCTUnwrap(vm.currentStep?.id)

        vm.startHold()
        clock = start.addingTimeInterval(8) // 12s still on the clock
        XCTAssertTrue(vm.isHolding)

        vm.completeSet()

        XCTAssertFalse(vm.isHolding, "the running leg comes down with the tap")
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 0)
        XCTAssertEqual(spy.completions, 0, "coming out early is the user's choice, not the timer's verdict")
        XCTAssertEqual(vm.completedSets[holdStepID], [CompletedSet(reps: nil, durationSeconds: 20)],
                       "exactly one set, banked at its prescribed target")
        XCTAssertEqual(vm.currentSet, 2, "and the set counter advances as it does when the timer runs out")
        XCTAssertEqual(vm.holdSide, 1, "the next set opens back on side 1, never parked mid-set")
        XCTAssertTrue(vm.isResting, "which opens the rest")

        // The ticker keeps firing at the view's cadence; the abandoned deadline must record nothing.
        clock = start.addingTimeInterval(600)
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertEqual(vm.completedSetCount, 1)
        XCTAssertEqual(spy.completions, 0)
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
        // A single-station strength circuit, so its rounds are the one exercise's successive sets and
        // the user can be driven onto the last round cleanly (US-CC02).
        let block = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [repPrescription("push_up", sets: 3, reps: 10)]
        )
        let workout = Workout(
            id: UUID(), createdAt: start, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 15, wasReturn: false, blocks: [block]
        )
        let vm = ActiveSessionViewModel(
            workout: workout, swapEngine: engine, user: makeUser(), recentLogs: [],
            sessionPolicy: .default, now: { self.start }
        )
        vm.completeSet() // push_up round 1 -> round 2
        vm.completeSet() // push_up round 2 -> round 3
        XCTAssertEqual(vm.currentSet, 3, "the user is on the last round of the 3-round slot")

        await vm.swapCurrentExercise()

        XCTAssertEqual(vm.currentStep?.prescription.sets, 2, "the substitute carries its own set count")
        XCTAssertEqual(vm.currentSet, 2, "clamps to the substitute's last round rather than stranding the user")
        XCTAssertLessThanOrEqual(vm.currentSet, vm.currentStep!.prescription.sets)
    }

    /// A mid-circuit swap keeps the current round rather than restarting it: it must not send the
    /// rotation back to round 1, which would re-offer - and, through `recordSet`, double-count - the peer
    /// stations already completed in earlier rounds (US-CC02 OPT1). Full swap-across-rounds
    /// reconciliation stays US-CC07; here the guarantee is only that no peer station over-logs.
    func testSwapMidCircuitDoesNotReplayCompletedPeerStations() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips", sets: 3)))
        let vm = ActiveSessionViewModel(
            workout: circuitWorkout(rounds: 3), swapEngine: engine, user: makeUser(),
            recentLogs: [], sessionPolicy: .default, now: { self.start }
        )
        vm.completeSet() // warm-up cat_cow -> push_up round 1
        vm.completeSet() // push_up round 1 -> squat round 1
        vm.completeSet() // squat round 1 -> hinge round 1
        vm.completeSet() // hinge round 1 -> push_up round 2
        vm.completeSet() // push_up round 2 -> squat round 2
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "on squat")
        XCTAssertEqual(vm.currentSet, 2, "round 2 of the circuit")

        await vm.swapCurrentExercise() // swap squat mid-circuit for a 3-set substitute

        XCTAssertEqual(vm.currentSet, 2, "the swap keeps the current round rather than restarting at 1")
        while !vm.isComplete { vm.completeSet() } // finish the block hands-free

        let logged = vm.loggedExercises()
        let pushUp = logged.first { $0.exerciseId == "push_up" }
        let hinge = logged.first { $0.exerciseId == "hinge" }
        XCTAssertEqual(pushUp?.completedSets.count, 3, "push_up logs exactly its three rounds, never four")
        XCTAssertEqual(hinge?.completedSets.count, 3, "hinge logs exactly its three rounds, never four")
        XCTAssertTrue(
            logged.allSatisfy { $0.completedSets.count <= 3 },
            "no station over-logs past the block's uniform round count"
        )
    }

    // MARK: - Skip & swap across remaining rounds (US-CC07)

    /// The US-CC07 skip validation shape: a skip inside a circuit removes the exercise from **every**
    /// remaining round, not just the current one, and logs it not-done (US-CC09). Skipping B (squat) in
    /// round 1 leaves the rotation cycling A, C across rounds 2 and 3, with A and C each completing all
    /// three rounds and B logged skipped with zero completed sets.
    func testSkipInsideCircuitRemovesExerciseFromAllRemainingRounds() {
        let vm = makeViewModel(circuitWorkout(rounds: 3), clock: { self.start })
        vm.completeSet() // warm-up cat_cow -> push_up round 1
        vm.completeSet() // push_up round 1 -> squat round 1
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")
        XCTAssertEqual(vm.currentRound, 1)

        vm.skipExercise() // skip B (squat) mid-circuit, in round 1

        // From here the rotation only ever visits A and C, across every remaining round.
        var visited: [(id: String, round: Int)] = []
        var guardCount = 0
        while let round = vm.currentRound, guardCount < 20 {
            guardCount += 1
            visited.append((vm.currentStep!.prescription.exercise.id, round))
            vm.completeSet()
        }
        XCTAssertFalse(visited.contains { $0.id == "squat" }, "squat does not reappear in any later round")
        XCTAssertEqual(
            visited.map { "\($0.id):\($0.round)" },
            ["hinge:1", "push_up:2", "hinge:2", "push_up:3", "hinge:3"],
            "rounds 2 and 3 rotate only the surviving A, C"
        )

        while !vm.isComplete { vm.completeSet() } // flow through the cooldown
        let logged = vm.loggedExercises()
        XCTAssertEqual(logged.first { $0.exerciseId == "push_up" }?.completedSets.count, 3)
        XCTAssertEqual(logged.first { $0.exerciseId == "hinge" }?.completedSets.count, 3)
        let squat = logged.first { $0.exerciseId == "squat" }
        XCTAssertEqual(squat?.completedSets.count, 0, "B logs zero completed sets")
        XCTAssertTrue(squat?.skipped ?? false, "B logs not-done (US-CC09)")
    }

    /// A mid-circuit swap holds for **all remaining rounds** and keeps the block structurally uniform
    /// (US-CC03/US-CC07): the substitute replaces the original in the one slot every round rotates
    /// through, so every later round presents the substitute, and every station in the training block is
    /// still prescribed the block's uniform round count M. Peers are untouched - they each still complete
    /// M rounds and never over-log.
    func testSwapAppliesToAllRemainingRoundsAndKeepsBlockStructurallyUniform() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips", sets: 3)))
        let vm = ActiveSessionViewModel(
            workout: circuitWorkout(rounds: 3), swapEngine: engine, user: makeUser(),
            recentLogs: [], sessionPolicy: .default, now: { self.start }
        )
        vm.completeSet() // warm-up -> push_up round 1
        vm.completeSet() // push_up round 1 -> squat round 1
        vm.completeSet() // squat round 1 -> hinge round 1
        vm.completeSet() // hinge round 1 -> push_up round 2
        vm.completeSet() // push_up round 2 -> squat round 2
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")
        XCTAssertEqual(vm.currentRound, 2)

        await vm.swapCurrentExercise() // swap squat (B) mid-circuit, in round 2

        // The substitute took over B's slot and the training block is still uniform in its prescribed
        // round count: every strength station carries M = 3 sets, so "Round N of M" stays well-defined.
        let trainingSets = vm.steps.filter { $0.blockCategory == .strength }.map(\.prescription.sets)
        XCTAssertEqual(trainingSets, [3, 3, 3], "the swap keeps the block's uniform prescribed round count")
        XCTAssertFalse(vm.steps.contains { $0.prescription.exercise.id == "squat" }, "B is gone from the lineup")

        // The substitute is present in every remaining round (round 3 as well as the current round 2).
        var substituteRounds: Set<Int> = []
        var guardCount = 0
        while let round = vm.currentRound, guardCount < 20 {
            guardCount += 1
            if vm.currentStep?.prescription.exercise.id == "dips" { substituteRounds.insert(round) }
            vm.completeSet()
        }
        XCTAssertEqual(substituteRounds, [2, 3], "the swapped-in peer plays every remaining round, not just the current one")

        while !vm.isComplete { vm.completeSet() }
        let logged = vm.loggedExercises()
        XCTAssertEqual(logged.first { $0.exerciseId == "push_up" }?.completedSets.count, 3, "peer A completes all 3 rounds")
        XCTAssertEqual(logged.first { $0.exerciseId == "hinge" }?.completedSets.count, 3, "peer C completes all 3 rounds")
        XCTAssertTrue(logged.allSatisfy { $0.completedSets.count <= 3 }, "no station over-logs past M")
        // Option A (US-CC07): the substitute is an honest late entrant - it logs only the rounds it
        // actually played (it joined in round 2), never a fabricated round-1 set. Its pre-swap rounds
        // were done as B and are discarded with B, keeping the log faithful to what the user performed.
        XCTAssertEqual(logged.first { $0.exerciseId == "dips" }?.completedSets.count, 2,
                       "the substitute logs only rounds 2 and 3 - the rounds it was actually in the session for")
    }

    /// A `.noAlternative` swap mid-circuit changes nothing: the original exercise stays in its slot and
    /// therefore still plays every remaining round, and the honest no-alternative flag flips (unchanged
    /// US-K03 semantics carried across the rotation, US-CC07).
    func testSwapNoAlternativeMidCircuitKeepsExerciseInAllRemainingRounds() async {
        let engine = StubSwapEngine(outcome: .noAlternative)
        let vm = ActiveSessionViewModel(
            workout: circuitWorkout(rounds: 3), swapEngine: engine, user: makeUser(),
            recentLogs: [], sessionPolicy: .default, now: { self.start }
        )
        vm.completeSet() // warm-up -> push_up round 1
        vm.completeSet() // push_up round 1 -> squat round 1
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat")

        await vm.swapCurrentExercise()

        XCTAssertTrue(vm.noSwapAlternative, "the honest no-alternative state shows")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "the exercise stays in place")

        while !vm.isComplete { vm.completeSet() }
        let logged = vm.loggedExercises()
        for id in ["push_up", "squat", "hinge"] {
            XCTAssertEqual(logged.first { $0.exerciseId == id }?.completedSets.count, 3,
                           "\(id) still completes all 3 rounds - the block stays even")
        }
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

    /// Swapping an exercise that has banked sets across earlier rounds discards those recorded sets -
    /// the movement is being replaced entirely, so it never carries completed sets into the eventual log.
    func testSwapDiscardsPartialSets() async {
        let engine = StubSwapEngine(outcome: .substituted(substitutePrescription("dips")))
        let vm = makeSwapViewModel(engine: engine)
        vm.completeSet() // cat_cow -> push_up round 1
        let pushUpID = vm.currentStep!.id
        vm.completeSet() // push_up round 1 recorded -> squat round 1
        vm.completeSet() // squat round 1 -> back to push_up, round 2 (push_up carries its round-1 set)
        XCTAssertEqual(vm.currentStep?.id, pushUpID)
        XCTAssertEqual(vm.completedSets[pushUpID]?.count, 1)

        await vm.swapCurrentExercise()

        XCTAssertNil(vm.completedSets[pushUpID], "the replaced movement's recorded sets are discarded")
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
        original.completeSet() // warm-up done -> push_up round 1 (rest opens)
        original.completeSet() // push_up round 1 -> squat round 1 (rotation)
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.start })

        XCTAssertFalse(resumed.isComplete)
        XCTAssertEqual(resumed.currentStepIndex, 2)
        XCTAssertEqual(resumed.currentSet, 1)
        XCTAssertEqual(resumed.currentStep?.prescription.exercise.id, "squat")
        XCTAssertEqual(resumed.completedSetCount, 2, "cat_cow set + push_up round-1 set carry over")
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

    // MARK: - Auto-advancing work window (US-CC01)

    /// A strength-only session (no bookends), so the player opens directly on a rep-based training set -
    /// which is where the auto-advancing work window lives. Two exercises, two sets each, so the flow
    /// exercises set-to-set and exercise-to-exercise advances through the rest.
    private func strengthWorkout(sets: Int = 2, reps: Int = 12, rest: Int = 30) -> Workout {
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [
                PrescribedExercise(id: UUID(), exercise: repExercise(id: "push_up"), sets: sets, reps: reps, durationSeconds: nil, restSeconds: rest),
                PrescribedExercise(id: UUID(), exercise: repExercise(id: "squat", pattern: .squat), sets: sets, reps: reps, durationSeconds: nil, restSeconds: rest)
            ]
        )
        return Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [strength]
        )
    }

    /// The screen window is the engine's own planned per-set seconds, not a second number - the single
    /// source of truth US-CC08 rests on, so the window can never be roomier or tighter than what the fit
    /// budgeted. Asserted against `SessionAssembly.workSecondsPerSet(of:)` for the very slot on screen.
    func testWorkWindowSecondsEqualTheEnginePlannedPerSetSeconds() throws {
        let vm = makeViewModel(strengthWorkout(sets: 2, reps: 12), clock: { self.start })
        let step = try XCTUnwrap(vm.currentStep)
        let planned = SessionAssembly.workSecondsPerSet(of: step.prescription)
        XCTAssertGreaterThan(planned, 0)
        XCTAssertEqual(vm.workWindowSecondsPerSet, planned,
                       "the player's window is the very value the engine budgeted the set at (US-CC08)")
    }

    /// A per-side rep movement prices its window exactly as planning does - the player reads planning's
    /// own function, so whatever per-side handling the plan applies carries through by construction
    /// rather than by a second copy that could drift.
    func testWorkWindowMatchesPlannedSecondsForAPerSideRepMovement() {
        let perSideRep = PrescribedExercise(
            id: UUID(), exercise: perSide(repExercise(id: "archer_push")),
            sets: 2, reps: 8, durationSeconds: nil, restSeconds: 30
        )
        let block = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [perSideRep, repPrescription("squat", sets: 1, reps: 10)]
        )
        let workout = Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false, blocks: [block]
        )
        let vm = makeViewModel(workout, clock: { self.start })
        XCTAssertEqual(vm.workWindowSecondsPerSet, SessionAssembly.workSecondsPerSet(of: perSideRep),
                       "the player reads planning's per-set seconds, so per-side handling matches by construction")
    }

    /// A rep-based training set counts down hands-free: the window auto-starts on `start()`, no
    /// Start-hold-style tap required, unlike the US-O03 hold.
    func testWorkWindowAutoStartsForARepTrainingSet() {
        let vm = makeViewModel(strengthWorkout(sets: 2, reps: 12), clock: { self.start })
        XCTAssertTrue(vm.currentStepAutoAdvances)
        XCTAssertFalse(vm.isRunningWorkWindow, "no window until the session starts")

        vm.start()

        XCTAssertTrue(vm.isRunningWorkWindow, "the work window auto-starts hands-free on start()")
        XCTAssertEqual(vm.workWindowRemaining(asOf: start), vm.workWindowSecondsPerSet)
    }

    /// At zero the window records the set completed - prescribed reps as performed, identical to a
    /// tapped completion (US-CC09) - flows into the existing rest, and fires the cue exactly once: never
    /// before zero, never again on a later tick.
    func testWorkWindowAutoAdvancesAtZeroRecordingTheSetCompleted() throws {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(strengthWorkout(sets: 2, reps: 12), clock: { clock }, feedback: spy)
        let stepID = try XCTUnwrap(vm.currentStep?.id)
        vm.start()
        let window = try XCTUnwrap(vm.workWindowSecondsPerSet)

        // Before zero, nothing fires.
        clock = start.addingTimeInterval(TimeInterval(window - 1))
        vm.completeWorkWindowIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isRunningWorkWindow, "still counting down a second before zero")
        XCTAssertEqual(vm.completedSetCount, 0)
        XCTAssertEqual(spy.completions, 0)

        // At zero it records and rotates to the next station, firing the cue once.
        clock = start.addingTimeInterval(TimeInterval(window))
        vm.completeWorkWindowIfElapsed(asOf: clock)
        XCTAssertFalse(vm.isRunningWorkWindow)
        XCTAssertEqual(vm.completedSets[stepID], [CompletedSet(reps: 12, durationSeconds: nil)],
                       "the prescribed reps record as performed, exactly like a tapped completion")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "the rotation moved to the next station")
        XCTAssertEqual(vm.currentSet, 1, "still round 1")
        XCTAssertTrue(vm.isResting, "flowed into the existing rest with no tap")
        XCTAssertEqual(spy.completions, 1, "the completion cue fired exactly once")
        XCTAssertFalse(vm.skippedStepIDs.contains(stepID), "an auto-advanced set is never a skip")

        // Idempotent: the view's ticker keeps calling the check.
        vm.completeWorkWindowIfElapsed(asOf: clock)
        XCTAssertEqual(spy.completions, 1, "the cue never fires a second time for the same window")
    }

    /// **Done** ends the window early and advances immediately, recording the set completed (prescribed
    /// = performed) with no cue and no skip - being caught mid-rep at zero carries no penalty.
    func testDoneAdvancesEarlyRecordingCompletedWithoutACue() throws {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(strengthWorkout(sets: 2, reps: 12), clock: { clock }, feedback: spy)
        let stepID = try XCTUnwrap(vm.currentStep?.id)
        vm.start()
        XCTAssertTrue(vm.isRunningWorkWindow)

        // Well before the countdown reaches zero.
        clock = start.addingTimeInterval(3)
        vm.finishWorkWindowEarly()

        XCTAssertFalse(vm.isRunningWorkWindow, "Done ends the window")
        XCTAssertEqual(vm.completedSets[stepID], [CompletedSet(reps: 12, durationSeconds: nil)],
                       "the set records completed, prescribed = performed")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "and rotates to the next station immediately")
        XCTAssertEqual(vm.currentSet, 1)
        XCTAssertTrue(vm.isResting)
        XCTAssertEqual(spy.completions, 0, "coming out early is the user's choice - no cue, no penalty")
        XCTAssertFalse(vm.skippedStepIDs.contains(stepID), "Done is never a skip")
    }

    /// Backgrounding freezes the window rather than letting it blow past, and a frozen window never
    /// auto-completes however long the app is away - the same `Countdown` pause semantics as the rest
    /// and hold timers.
    func testBackgroundingFreezesTheWorkWindow() {
        var clock = start
        let vm = makeViewModel(strengthWorkout(sets: 1, reps: 12), clock: { clock })
        vm.start()

        clock = start.addingTimeInterval(5)
        vm.pauseWorkWindow(asOf: clock)
        XCTAssertTrue(vm.isWorkWindowPaused)
        let frozen = vm.workWindowRemaining(asOf: clock)

        // Two minutes in the background: the countdown does not draw down and never auto-advances.
        clock = start.addingTimeInterval(120)
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), frozen, "frozen while backgrounded")
        vm.completeWorkWindowIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isRunningWorkWindow, "a paused window never auto-advances while the app is away")

        vm.resumeWorkWindow(asOf: clock)
        XCTAssertFalse(vm.isWorkWindowPaused)
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), frozen, "resumes from the captured remainder")
    }

    /// The work window is withheld on a timed movement (the US-O03 Hold Timer owns it) so retiring the
    /// manual "Complete set" for strength never touches the hold path.
    func testWorkWindowIsNotOfferedForAHold() {
        let vm = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { self.start })
        XCTAssertFalse(vm.currentStepAutoAdvances, "a timed movement uses the Hold Timer, not the work window")
        XCTAssertNil(vm.workWindowSecondsPerSet)
        vm.start()
        XCTAssertFalse(vm.isRunningWorkWindow, "no work window auto-starts on a hold")
        XCTAssertTrue(vm.canStartHold, "the manual Hold Timer path is untouched")
    }

    /// The gate is the block category, not just the movement kind: a rep-based movement placed in a
    /// warm-up block keeps the manual path, so retiring "Complete set" for strength leaves the bookend
    /// flow (US-CC05) alone. Completing the warm-up by hand then reaches the strength set, whose window
    /// auto-starts as the flow arrives.
    func testWorkWindowIsGatedToTrainingBlocksNotBookends() {
        let warmup = WorkoutBlock(
            id: UUID(), title: "Warm-up", category: .warmup,
            exercises: [repPrescription("reach", sets: 1, reps: 8)]
        )
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [repPrescription("push_up", sets: 1, reps: 10)]
        )
        let workout = Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 10, wasReturn: false, blocks: [warmup, strength]
        )
        let vm = makeViewModel(workout, clock: { self.start })

        XCTAssertFalse(vm.currentStepAutoAdvances, "a rep-based warm-up keeps the manual Complete set")
        XCTAssertNil(vm.workWindowSecondsPerSet)
        vm.start()
        XCTAssertFalse(vm.isRunningWorkWindow)

        // Bank the warm-up by hand, clear its rest, and arrive at the strength set.
        vm.completeSet()
        vm.skipRest()
        XCTAssertTrue(vm.currentStepAutoAdvances, "the strength set auto-advances")
        XCTAssertTrue(vm.isRunningWorkWindow, "and its work window auto-starts as the flow reaches it")
    }

    /// The whole flow: a window at zero opens the rest, and as the rest ends the next set's window
    /// auto-starts - hands-free from one set to the next, no window ever running behind the rest overlay.
    func testWorkWindowFlowsThroughTheRestIntoTheNextSetsWindow() throws {
        var clock = start
        let vm = makeViewModel(strengthWorkout(sets: 2, reps: 12, rest: 30), clock: { clock })
        vm.start()
        let window = try XCTUnwrap(vm.workWindowSecondsPerSet)

        clock = start.addingTimeInterval(TimeInterval(window))
        vm.completeWorkWindowIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isResting)
        XCTAssertFalse(vm.isRunningWorkWindow, "no window runs behind the rest overlay")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "squat", "rotated to the next station")

        clock = clock.addingTimeInterval(TimeInterval(vm.restTotalSeconds))
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertFalse(vm.isResting)
        XCTAssertTrue(vm.isRunningWorkWindow, "the next station's work window auto-starts as the rest ends")
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), window)
    }

    /// The end-to-end promise (US-CC01/US-CC09): a whole strength block completes hands-free - every
    /// window and rest driven to zero, not a single manual completion - and every exercise logs its full
    /// set count as completed, none skipped.
    func testAWholeStrengthBlockCompletesHandsFreeLoggingEverySetCompleted() {
        var clock = start
        let vm = makeViewModel(strengthWorkout(sets: 2, reps: 12, rest: 30), clock: { clock })
        vm.start()

        var guardCount = 0
        while !vm.isComplete && guardCount < 40 {
            guardCount += 1
            if vm.isResting {
                clock = clock.addingTimeInterval(TimeInterval(vm.restTotalSeconds))
                vm.completeRestIfElapsed(asOf: clock)
            } else if vm.isRunningWorkWindow {
                clock = clock.addingTimeInterval(TimeInterval(vm.workWindowTotalSeconds))
                vm.completeWorkWindowIfElapsed(asOf: clock)
            } else {
                XCTFail("a rep training set should always be resting or running its window")
                break
            }
        }

        XCTAssertTrue(vm.isComplete, "the block finished hands-free, no tap")
        for logged in vm.loggedExercises() {
            XCTAssertFalse(logged.skipped, "\(logged.exerciseId) auto-advanced, so it is never skipped")
            XCTAssertEqual(logged.completedSets.count, 2, "each exercise logged its full set count as completed")
        }
    }

    /// A swap reshapes the slot the window was timing, so it drops the running window without a cue; the
    /// substitute - itself a rep training set - re-arms a fresh window sized to its own prescription.
    func testSwapClearsARunningWorkWindowAndReArmsForTheSubstitute() async {
        let substitute = substitutePrescription("dips", sets: 3, reps: 10, rest: 45)
        let spy = SpyRestFeedback()
        let engine = StubSwapEngine(outcome: .substituted(substitute))
        let vm = ActiveSessionViewModel(
            workout: strengthWorkout(sets: 2, reps: 12), swapEngine: engine, user: makeUser(),
            recentLogs: [], sessionPolicy: .default, now: { self.start }, feedback: spy
        )
        vm.start()
        XCTAssertTrue(vm.isRunningWorkWindow)

        await vm.swapCurrentExercise()

        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "dips")
        XCTAssertFalse(vm.isRunningWorkWindow, "the running window does not survive onto the substitute")
        XCTAssertEqual(spy.completions, 0, "dropping the window for a swap fires no completion cue")

        // The view re-arms the window once the swap settles; the model does it directly here.
        vm.startWorkWindow()
        XCTAssertTrue(vm.isRunningWorkWindow, "a fresh window starts for the substitute")
        XCTAssertEqual(vm.workWindowSecondsPerSet, SessionAssembly.workSecondsPerSet(of: substitute))
    }

    // MARK: - Hands-free bookend holds (US-CC05)

    /// A warm-up with a single per-side stretch hold, then a strength set so the stretch has somewhere to
    /// advance to. The stretch sits in a `.warmup` block, so it is a *bookend* hold (auto-start), not a
    /// timed *training* hold (manual Start-hold) - the distinction the whole story turns on.
    private func perSideBookendWorkout(seconds: Int = 20) -> Workout {
        let warmup = WorkoutBlock(
            id: UUID(), title: "Warm-up", category: .warmup,
            exercises: [
                PrescribedExercise(
                    id: UUID(), exercise: perSide(holdExercise(id: "hip_opener")),
                    sets: 1, reps: nil, durationSeconds: seconds, restSeconds: 15
                )
            ]
        )
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [repPrescription("push_up", sets: 1, reps: 10)]
        )
        return Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 20, wasReturn: false, blocks: [warmup, strength]
        )
    }

    /// A warm-up of two single-side stretch holds, so the station-to-station hands-free flow between two
    /// bookend holds can be driven.
    private func twoStretchWarmupWorkout() -> Workout {
        let warmup = WorkoutBlock(
            id: UUID(), title: "Warm-up", category: .warmup,
            exercises: [
                holdPrescription("cat_cow", sets: 1, seconds: 20),
                holdPrescription("forward_fold", sets: 1, seconds: 20)
            ]
        )
        let strength = WorkoutBlock(
            id: UUID(), title: "Strength", category: .strength,
            exercises: [repPrescription("push_up", sets: 1, reps: 10)]
        )
        return Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: 20, wasReturn: false, blocks: [warmup, strength]
        )
    }

    /// The gate is the block category, matching the work-window gate's complement: a warm-up / cooldown
    /// stretch hold is a *bookend* hold that auto-starts hands-free; a strength / primal timed hold is a
    /// *training* hold that keeps the manual Start-hold path (US-CC02's circuit player, untouched here).
    func testBookendHoldGateDistinguishesBookendFromTrainingHold() {
        let bookend = makeViewModel(perSideBookendWorkout(seconds: 20), clock: { self.start })
        XCTAssertTrue(bookend.currentStepIsBookendHold, "a warm-up stretch hold is a bookend hold")
        XCTAssertTrue(bookend.canAutoStartHold, "so it is eligible to auto-start hands-free")

        let training = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { self.start })
        XCTAssertFalse(training.currentStepIsBookendHold, "a strength hold is a training hold, not a bookend")
        XCTAssertFalse(training.canAutoStartHold, "so it keeps the manual Start-hold path")
    }

    /// A warm-up stretch hold auto-starts hands-free on `start()` - no Start-hold tap, unlike a timed
    /// *training* hold, which stays parked until the user taps.
    func testBookendHoldAutoStartsHandsFreeOnStart() throws {
        let vm = makeViewModel(perSideBookendWorkout(seconds: 20), clock: { self.start })
        XCTAssertTrue(vm.currentStepIsBookendHold)
        XCTAssertFalse(vm.isHolding, "no leg until the session starts")

        vm.start()

        XCTAssertTrue(vm.isHolding, "the bookend hold auto-starts hands-free on start()")
        XCTAssertEqual(vm.holdSide, 1)
        XCTAssertEqual(vm.holdRemaining(asOf: start), try XCTUnwrap(vm.holdSecondsPerSide))
    }

    /// The heart of US-CC05: a per-side bookend runs side 1 -> a brief "Switch sides" beat -> side 2 with
    /// no tap anywhere, records exactly one set, and fires the completion cue exactly once per hold *leg*
    /// (two legs, two cues) - the beat itself is a quiet get-ready pause that fires none.
    func testPerSideBookendRunsSide1ThenSwitchSidesThenSide2HandsFree() throws {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(perSideBookendWorkout(seconds: 20), clock: { clock }, feedback: spy)
        let stretchID = try XCTUnwrap(vm.currentStep?.id)
        XCTAssertEqual(vm.holdSidesPerSet, 2)

        // Side 1 auto-starts on start().
        vm.start()
        XCTAssertTrue(vm.isHolding)
        XCTAssertEqual(vm.holdSide, 1)

        // Side 1 elapses: cue once, no set yet, and a brief hands-free "Switch sides" beat opens - no tap.
        clock = start.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertEqual(spy.completions, 1, "side 1 leg cues once")
        XCTAssertFalse(vm.isHolding, "the leg is down while the beat runs")
        XCTAssertTrue(vm.isSwitchingSides, "a Switch sides beat bridges the two legs")
        XCTAssertEqual(vm.restTotalSeconds, ActiveSessionViewModel.switchSidesSeconds, "and it is brief")
        XCTAssertEqual(vm.holdSide, 2, "owing side 2")
        XCTAssertEqual(vm.completedSetCount, 0, "half a set is not a set")

        // The beat ends: side 2 auto-starts hands-free, and the beat itself fired no cue.
        clock = clock.addingTimeInterval(TimeInterval(ActiveSessionViewModel.switchSidesSeconds))
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertFalse(vm.isSwitchingSides)
        XCTAssertTrue(vm.isHolding, "side 2 auto-starts with no tap")
        XCTAssertEqual(vm.holdSide, 2)
        XCTAssertEqual(spy.completions, 1, "the Switch sides beat fires no cue - the cue is the leg's, once each")

        // Side 2 elapses: the set records, the second leg cues, and the stretch is done.
        clock = clock.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertEqual(vm.completedSets[stretchID], [CompletedSet(reps: nil, durationSeconds: 20)],
                       "both legs make exactly one set")
        XCTAssertEqual(spy.completions, 2, "exactly one cue per hold leg - two legs, two cues, none for the beat")
    }

    /// Two bookend stretches in a row flow hands-free: the first records and opens the ordinary
    /// between-stretch transition (a plain rest, not a switch-sides beat), and as it ends the next
    /// stretch's hold auto-starts with no tap.
    func testBookendHoldsFlowStationToStationHandsFree() {
        var clock = start
        let vm = makeViewModel(twoStretchWarmupWorkout(), clock: { clock })
        vm.start()
        XCTAssertTrue(vm.isHolding, "the first stretch auto-starts")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "cat_cow")

        clock = start.addingTimeInterval(20)
        vm.completeHoldIfElapsed(asOf: clock) // single-side stretch -> records, advances, transition opens
        XCTAssertTrue(vm.isResting, "a between-stretch transition opens")
        XCTAssertFalse(vm.isSwitchingSides, "it is an ordinary transition, not a switch-sides beat")
        XCTAssertEqual(vm.currentStep?.prescription.exercise.id, "forward_fold")

        clock = clock.addingTimeInterval(TimeInterval(vm.restTotalSeconds))
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertFalse(vm.isResting)
        XCTAssertTrue(vm.isHolding, "the next stretch's hold auto-starts as the transition ends")
    }

    /// Scope guard: a timed *training* hold (strength / primal) is deliberately left on its manual path -
    /// it does not auto-start on `start()`, and a per-side one parks on side 2 for a tap with no
    /// switch-sides beat. US-CC05 owns only the bookends.
    func testTrainingHoldStaysManualNotAutoStarted() {
        let vm = makeViewModel(perSideHoldWorkout(seconds: 20), clock: { self.start }) // strength block
        vm.start()
        XCTAssertFalse(vm.isHolding, "a training hold keeps the manual Start-hold path - no auto-start")

        vm.startHold()
        vm.completeHoldIfElapsed(asOf: start.addingTimeInterval(20)) // side 1 done
        XCTAssertEqual(vm.holdSide, 2)
        XCTAssertFalse(vm.isHolding, "parks on side 2 for a tap")
        XCTAssertFalse(vm.isSwitchingSides, "and opens no switch-sides beat on a training hold")
        XCTAssertFalse(vm.isResting)
    }

    /// A resumed bookend re-opens idle (a hold leg never survives a relaunch, US-O03) and then auto-starts
    /// the owed side fresh on `start()` - no phantom set, no cue on the restored/expired leg (US-CC05
    /// resume rule).
    func testResumedBookendHoldReopensIdleAndAutoStartsFresh() async throws {
        let store = InMemoryActiveSessionStore()
        let spy = SpyRestFeedback()
        let original = ActiveSessionViewModel(
            workout: perSideBookendWorkout(seconds: 20), store: store, userId: "u1", now: { self.start }
        )
        original.start()                                                    // auto-starts side 1
        original.completeHoldIfElapsed(asOf: start.addingTimeInterval(20))  // side 1 done -> owes side 2
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.hold?.side, 2, "the side owed is carried; the running leg is not")

        // Relaunch long after: the beat (a rest) has expired and is dropped, and the leg was never restored.
        let resumed = ActiveSessionViewModel(state: saved, now: { self.start.addingTimeInterval(600) }, feedback: spy)
        XCTAssertFalse(resumed.isHolding, "a hold leg never survives the relaunch")
        XCTAssertFalse(resumed.isResting, "the expired switch-sides beat is dropped, not waiting to fire")
        XCTAssertEqual(resumed.holdSide, 2)

        resumed.start()
        XCTAssertTrue(resumed.isHolding, "the bookend re-opens idle and auto-starts the owed side fresh")
        XCTAssertEqual(resumed.completedSetCount, 0, "no phantom set for work nobody did")
        XCTAssertEqual(spy.completions, 0, "and no cue fires until the fresh leg actually elapses")
    }

    /// A bookend hold still honours **Stop hold**: tapping it comes out of the leg without re-arming
    /// itself, so stopping is a real escape and the manual Start-hold is the way back (never a surprise
    /// auto-restart under the user's thumb).
    func testStopHoldOnABookendDoesNotImmediatelyReArm() {
        let vm = makeViewModel(perSideBookendWorkout(seconds: 20), clock: { self.start })
        vm.start()
        XCTAssertTrue(vm.isHolding)

        vm.cancelHold()
        XCTAssertFalse(vm.isHolding, "Stop hold comes out of the leg")
        XCTAssertTrue(vm.canStartHold, "and the manual Start-hold is offered as the way back")
        XCTAssertEqual(vm.holdSide, 1, "the same side is still owed")
    }

    // MARK: - User pause (US-CC06)

    /// An explicit user Pause freezes the running work window and resumes from the *exact* remainder,
    /// like the background pause - the difference is only what triggers it (a user tap, in the
    /// foreground), never the timer mechanism.
    func testUserPauseFreezesTheWorkWindowAndResumesFromTheExactRemainder() {
        var clock = start
        let vm = makeViewModel(strengthWorkout(sets: 1, reps: 12), clock: { clock })
        vm.start()
        XCTAssertTrue(vm.canUserPause, "a live work window can be paused")
        XCTAssertTrue(vm.isCountingDown)

        clock = start.addingTimeInterval(5)
        vm.pause(asOf: clock)
        XCTAssertTrue(vm.isUserPaused)
        XCTAssertTrue(vm.isWorkWindowPaused)
        XCTAssertFalse(vm.canUserPause, "already paused - the control now offers Resume, not Pause")
        let frozen = vm.workWindowRemaining(asOf: clock)

        // Two minutes elapse on the wall clock; the frozen remainder does not draw down.
        clock = start.addingTimeInterval(125)
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), frozen, "frozen while the user holds pause")

        vm.resume(asOf: clock)
        XCTAssertFalse(vm.isUserPaused)
        XCTAssertFalse(vm.isWorkWindowPaused)
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), frozen, "resumes from the exact remainder")

        clock = clock.addingTimeInterval(3)
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), frozen - 3, "and counts down again from there")
    }

    /// The cue is frozen with the countdown: a user-paused work window never auto-advances and never
    /// fires the completion cue, however long the wall clock runs past its remainder, because a paused
    /// `Countdown` never reports `hasElapsed`. This is the acceptance criterion that Pause freezes the
    /// *audio-cue timing*, not just the visible ring.
    func testUserPausedWorkWindowNeverAutoAdvancesOrFiresTheCue() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(strengthWorkout(sets: 1, reps: 12), clock: { clock }, feedback: spy)
        vm.start()

        clock = start.addingTimeInterval(3)
        vm.pause(asOf: clock)

        // Long past where the window would have hit zero unpaused - the ticker keeps calling the check.
        clock = start.addingTimeInterval(600)
        vm.completeWorkWindowIfElapsed(asOf: clock)

        XCTAssertTrue(vm.isRunningWorkWindow, "a paused window never auto-advances")
        XCTAssertEqual(vm.completedSetCount, 0, "no set is banked for work frozen mid-window")
        XCTAssertEqual(spy.completions, 0, "and the audio/haptic cue is frozen with the countdown")

        // Resuming re-arms the deadline from the remainder, so the cue fires once when it truly elapses.
        vm.resume(asOf: clock)
        clock = clock.addingTimeInterval(TimeInterval(vm.workWindowRemaining(asOf: clock)))
        vm.completeWorkWindowIfElapsed(asOf: clock)
        XCTAssertEqual(spy.completions, 1, "the cue fires exactly once, at the real remainder after resume")
        XCTAssertEqual(vm.completedSetCount, 1)
    }

    /// Pause also freezes a between-set rest and its cue, resuming from the exact remainder (the rest is
    /// one of the three countdowns the single Pause control covers).
    func testUserPauseFreezesARestAndItsCue() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(clock: { clock }, feedback: spy)
        vm.completeSet() // 30s rest opens
        XCTAssertTrue(vm.isResting)
        XCTAssertTrue(vm.canUserPause)

        clock = start.addingTimeInterval(10) // 20s left
        vm.pause(asOf: clock)
        XCTAssertTrue(vm.isUserPaused)
        XCTAssertTrue(vm.isRestPaused)

        clock = start.addingTimeInterval(600)
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isResting, "a user-paused rest never auto-completes")
        XCTAssertEqual(spy.completions, 0, "and its cue is frozen too")

        vm.resume(asOf: clock)
        XCTAssertEqual(vm.restRemaining(asOf: clock), 20, "resumes from the exact remainder")
    }

    /// Pause also freezes a running hold leg and its cue.
    func testUserPauseFreezesAHoldLeg() {
        var clock = start
        let spy = SpyRestFeedback()
        let vm = makeViewModel(singleHoldWorkout(sets: 1, seconds: 20), clock: { clock }, feedback: spy)
        vm.start()
        vm.startHold()
        XCTAssertTrue(vm.isHolding)
        XCTAssertTrue(vm.canUserPause)

        clock = start.addingTimeInterval(5) // 15s left
        vm.pause(asOf: clock)
        XCTAssertTrue(vm.isHoldPaused)

        clock = start.addingTimeInterval(600)
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isHolding, "a user-paused hold never auto-completes")
        XCTAssertEqual(vm.completedSetCount, 0)
        XCTAssertEqual(spy.completions, 0, "the hold cue is frozen with the countdown")

        vm.resume(asOf: clock)
        XCTAssertEqual(vm.holdRemaining(asOf: clock), 15, "resumes from the exact remainder")
    }

    /// The core interaction rule (US-CC06): a *user* pause is a foreground state, so backgrounding and
    /// returning to the foreground must **not** un-freeze it. Only the user's own Resume clears it -
    /// otherwise a notification banner would silently un-pause a session the user deliberately held.
    func testForegroundingDoesNotUnfreezeAUserPause() {
        var clock = start
        let vm = makeViewModel(strengthWorkout(sets: 1, reps: 12), clock: { clock })
        vm.start()

        clock = start.addingTimeInterval(5)
        vm.pause(asOf: clock) // user pause, in the foreground
        let frozen = vm.workWindowRemaining(asOf: clock)

        // App goes to the background and comes back - the scene-phase path, not the user.
        vm.pauseForBackground(asOf: clock)
        clock = start.addingTimeInterval(90)
        vm.resumeFromForeground(asOf: clock)

        XCTAssertTrue(vm.isUserPaused, "the user pause outlives a background/foreground cycle")
        XCTAssertTrue(vm.isWorkWindowPaused, "so the countdown stays frozen")
        XCTAssertEqual(vm.workWindowRemaining(asOf: clock), frozen, "at the exact remainder the user left")

        // Only the user's own Resume lets it run again.
        vm.resume(asOf: clock)
        XCTAssertFalse(vm.isUserPaused)
        XCTAssertFalse(vm.isWorkWindowPaused)
    }

    /// The complement: with no user pause, foregrounding resumes a plain background pause as before, so
    /// US-CC06 does not regress the US-K02/O03/CC01 background behaviour.
    func testForegroundingStillResumesAPlainBackgroundPause() {
        var clock = start
        let vm = makeViewModel(strengthWorkout(sets: 1, reps: 12), clock: { clock })
        vm.start()

        clock = start.addingTimeInterval(5)
        vm.pauseForBackground(asOf: clock)
        XCTAssertTrue(vm.isWorkWindowPaused)
        XCTAssertFalse(vm.isUserPaused, "backgrounding is not a user pause")

        vm.resumeFromForeground(asOf: clock)
        XCTAssertFalse(vm.isWorkWindowPaused, "a plain background pause resumes on return")
    }

    /// Pause is offered only when there is a live countdown to freeze (US-CC06): not on an idle
    /// Start-hold training step, and not once the session is complete.
    func testPauseIsUnavailableWithNoLiveCountdown() {
        // An idle training hold - the user is getting into position, no countdown is running.
        let holdVM = makeViewModel(singleHoldWorkout(sets: 1, seconds: 20), clock: { self.start })
        holdVM.start()
        XCTAssertFalse(holdVM.isCountingDown, "a training hold waits for a Start-hold tap - nothing counts down")
        XCTAssertFalse(holdVM.canUserPause, "so Pause is not offered")

        // A completed session has no countdown either.
        let vm = makeViewModel(clock: { self.start })
        for _ in 0..<6 { vm.completeSet() }
        XCTAssertTrue(vm.isComplete)
        XCTAssertFalse(vm.canUserPause, "the completion screen offers no Pause")
    }

    /// Taking an advancing escape hatch while paused (Done, Skip, Swap, Skip rest, Stop hold) clears the
    /// user pause, because the frozen countdown is being torn down and a fresh one re-arms un-paused -
    /// so the flow never lands running-but-showing-Resume.
    func testAdvancingWhilePausedClearsTheUserPause() {
        // Done on a work window.
        var clock = start
        let doneVM = makeViewModel(strengthWorkout(sets: 2, reps: 12), clock: { clock })
        doneVM.start()
        clock = start.addingTimeInterval(3)
        doneVM.pause(asOf: clock)
        XCTAssertTrue(doneVM.isUserPaused)
        doneVM.finishWorkWindowEarly()
        XCTAssertFalse(doneVM.isUserPaused, "Done cleared the stale pause and advanced")

        // Skip on a work window.
        let skipVM = makeViewModel(strengthWorkout(sets: 2, reps: 12), clock: { self.start })
        skipVM.start()
        skipVM.pause(asOf: self.start)
        skipVM.skipExercise()
        XCTAssertFalse(skipVM.isUserPaused, "Skip cleared the stale pause")

        // Skip rest during a paused rest.
        let restVM = makeViewModel(clock: { self.start })
        restVM.completeSet()
        restVM.pause(asOf: self.start)
        XCTAssertTrue(restVM.isUserPaused)
        restVM.skipRest()
        XCTAssertFalse(restVM.isUserPaused, "Skip rest cleared the stale pause")

        // Stop hold during a paused hold returns to idle with nothing left to resume.
        let holdVM = makeViewModel(singleHoldWorkout(sets: 1, seconds: 20), clock: { self.start })
        holdVM.start()
        holdVM.startHold()
        holdVM.pause(asOf: self.start)
        XCTAssertTrue(holdVM.isUserPaused)
        holdVM.cancelHold()
        XCTAssertFalse(holdVM.isUserPaused, "Stop hold cleared the pause - the leg is gone")
    }
}
