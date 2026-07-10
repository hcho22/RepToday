import XCTest
@testable import FitSnack

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

    private func makeViewModel(_ workout: Workout? = nil, clock: @escaping () -> Date) -> ActiveSessionViewModel {
        ActiveSessionViewModel(workout: workout ?? sampleWorkout(), now: clock)
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
}
