import AudioToolbox
import SwiftUI

@Observable
final class WorkoutViewModel {
    var workout: Workout
    var currentBlockIndex = 0
    var currentExerciseIndex = 0
    var currentSetIndex = 0
    var isResting = false
    var restTimeRemaining = 0
    var elapsedSeconds = 0
    var isPaused = false
    var isComplete = false
    var showSwapSheet = false
    var showCompleteView = false
    var showPauseMenu = false
    var swapTargetExerciseId: String?

    private var startTime: Date?
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0

    var currentBlock: WorkoutBlock? {
        let allBlocks = flatBlocks
        guard currentBlockIndex < allBlocks.count else { return nil }
        return allBlocks[currentBlockIndex]
    }

    var currentExercise: WorkoutExercise? {
        guard let block = currentBlock,
              currentExerciseIndex < block.exercises.count else { return nil }
        return block.exercises[currentExerciseIndex]
    }

    var flatBlocks: [WorkoutBlock] {
        var blocks: [WorkoutBlock] = []
        if let warmup = workout.warmup { blocks.append(warmup) }
        blocks.append(contentsOf: workout.mainBlocks)
        if let cooldown = workout.cooldown { blocks.append(cooldown) }
        return blocks
    }

    var totalExercises: Int {
        flatBlocks.reduce(0) { $0 + $1.exercises.count }
    }

    var completedExercises: Int {
        flatBlocks.prefix(currentBlockIndex).reduce(0) { $0 + $1.exercises.count } + currentExerciseIndex
    }

    var progress: Double {
        guard totalExercises > 0 else { return 0 }
        return Double(completedExercises) / Double(totalExercises)
    }

    var elapsedFormatted: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var workoutTitle: String {
        "\(workout.requestedDurationMinutes)-Min Workout"
    }

    var restTimeFormatted: String {
        String(format: "%d", restTimeRemaining)
    }

    init(workout: Workout) {
        self.workout = workout
    }

    func start() {
        workout.status = .inProgress
        workout.startedAt = Date()
        startTime = Date()
    }

    func updateElapsedTime() {
        guard let startTime, !isPaused else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(startTime) - totalPausedDuration)
    }

    func completeSet() {
        guard var exercise = currentExercise else { return }

        let setLog = SetLog(
            setNumber: currentSetIndex + 1,
            reps: exercise.reps,
            completedAt: Date()
        )
        exercise.completedSets.append(setLog)
        updateExercise(exercise)

        currentSetIndex += 1

        if currentSetIndex >= exercise.sets {
            // Exercise done, move to next or rest
            moveToNextExercise()
        } else {
            // Rest between sets
            startRest(duration: exercise.restAfterSeconds)
        }

        HapticManager.impact(.medium)
    }

    func skipExercise() {
        guard var exercise = currentExercise else { return }
        exercise.skipped = true
        updateExercise(exercise)
        moveToNextExercise()
    }

    func requestSwap() {
        swapTargetExerciseId = currentExercise?.exerciseId
        showSwapSheet = true
    }

    func swapExercise(reason: SwapReason, using services: ServiceContainer?) async {
        guard let services, let exerciseId = currentExercise?.exerciseId else { return }
        do {
            workout = try await services.workout.swapExercise(in: workout, exerciseId: exerciseId, reason: reason)
        } catch {}
    }

    func skipRest() {
        isResting = false
        restTimeRemaining = 0
    }

    func goToPreviousExercise() {
        isResting = false
        restTimeRemaining = 0
        currentSetIndex = 0

        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
        } else if currentBlockIndex > 0 {
            currentBlockIndex -= 1
            if let block = currentBlock {
                currentExerciseIndex = max(0, block.exercises.count - 1)
            }
        }
    }

    func pauseWorkout() {
        guard !isPaused else { return }
        pauseStartTime = Date()
        isPaused = true
    }

    func resumeWorkout() {
        guard isPaused else { return }
        if let pauseStart = pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        isPaused = false
    }

    func togglePause() {
        if isPaused {
            resumeWorkout()
        } else {
            pauseWorkout()
        }
    }

    func tickRest() {
        guard isResting, !isPaused else { return }
        if restTimeRemaining > 0 {
            restTimeRemaining -= 1
            if restTimeRemaining <= 3 && restTimeRemaining > 0 {
                HapticManager.impact(.light)
            }
        }
        if restTimeRemaining <= 0 {
            isResting = false
            HapticManager.notification(.success)
            AudioServicesPlaySystemSound(1007) // Short beep, respects silent mode
        }
    }

    func handleScenePhase(_ phase: ScenePhase, services: ServiceContainer?) {
        switch phase {
        case .background, .inactive:
            saveState(services: services)
        case .active:
            break
        @unknown default:
            break
        }
    }

    func finishWorkout(rating: Int, difficulty: Workout.PerceivedDifficulty) -> Workout {
        workout.status = .completed
        workout.completedAt = Date()
        workout.userRating = rating
        workout.perceivedDifficulty = difficulty
        workout.actualDurationMinutes = elapsedSeconds / 60
        return workout
    }

    /// Save as partial — XP calculated from completed sets only
    func savePartialWorkout() -> Workout {
        workout.status = .partial
        workout.completedAt = Date()
        workout.actualDurationMinutes = elapsedSeconds / 60
        return workout
    }

    /// Discard — cancelled workouts earn no XP and don't count toward goals
    func discardWorkout() -> Workout {
        workout.status = .cancelled
        workout.completedAt = Date()
        workout.actualDurationMinutes = 0
        return workout
    }

    private func saveState(services: ServiceContainer?) {
        guard let services else { return }
        Task {
            try? await services.workout.saveWorkout(workout)
        }
    }

    private func startRest(duration: Int) {
        restTimeRemaining = duration
        isResting = true
    }

    private func moveToNextExercise() {
        currentSetIndex = 0
        currentExerciseIndex += 1

        if let block = currentBlock, currentExerciseIndex >= block.exercises.count {
            currentBlockIndex += 1
            currentExerciseIndex = 0

            if currentBlockIndex >= flatBlocks.count {
                isComplete = true
                showCompleteView = true
                return
            }
        }

        if currentExercise != nil {
            startRest(duration: 15) // Brief rest between exercises
        }
    }

    private func updateExercise(_ exercise: WorkoutExercise) {
        let blocks = flatBlocks
        guard currentBlockIndex < blocks.count,
              currentExerciseIndex < blocks[currentBlockIndex].exercises.count else { return }

        // Find which mutable array to update
        if let warmup = workout.warmup, blocks[currentBlockIndex].id == warmup.id {
            workout.warmup?.exercises[currentExerciseIndex] = exercise
        } else if let cooldown = workout.cooldown, blocks[currentBlockIndex].id == cooldown.id {
            workout.cooldown?.exercises[currentExerciseIndex] = exercise
        } else {
            let mainOffset = workout.warmup != nil ? 1 : 0
            let mainIndex = currentBlockIndex - mainOffset
            if mainIndex >= 0 && mainIndex < workout.mainBlocks.count {
                workout.mainBlocks[mainIndex].exercises[currentExerciseIndex] = exercise
            }
        }
    }
}
