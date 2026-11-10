import Foundation

/// The production workout engine: the one `WorkoutEngineProtocol` conformer, wired by both
/// `ServiceContainer.live(...)` (the shipped app) and `ServiceContainer.mock()` (previews and tests).
///
/// It is a thin adapter over the deterministic pipeline, not a stand-in for one. Generation runs
/// `SessionAssembly.assemble` and a swap runs `ExerciseSwap.swap`, both pure on-device Swift over the
/// bundled, load-validated exercise library. Nothing here reaches the network, a server, or an LLM,
/// so a session builds the same in airplane mode as online - `OfflineSessionGenerationTests` guards
/// that end to end through the production container.
final class OnDeviceWorkoutEngine: WorkoutEngineProtocol {
    /// The validated catalog is the engine's exercise source; pulling it from the exercise service
    /// keeps a single, integrity-checked source of truth rather than re-loading the library here.
    private let exerciseService: any ExerciseServiceProtocol
    /// The clock the assembler reads for pillar/pattern staleness. Defaults to the wall clock so
    /// production is unchanged, but is injectable so a test can pin it - the codebase rule is that
    /// engine logic never reads the wall clock inline, and a fixed clock keeps a hosted generation
    /// reproducible instead of drifting with the calendar (`PerSideSwapEvidenceTests`).
    private let now: () -> Date

    init(exerciseService: any ExerciseServiceProtocol, now: @escaping () -> Date = { Date() }) {
        self.exerciseService = exerciseService
        self.now = now
    }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        variation: SessionVariation
    ) async throws -> Workout {
        try await generateWorkout(
            requestedMinutes: requestedMinutes,
            user: user,
            recentLogs: recentLogs,
            history: recentLogs,
            sessionPolicy: sessionPolicy,
            variation: variation,
            trainingDay: nil
        )
    }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        history: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        variation: SessionVariation,
        trainingDay: TrainingDay?
    ) async throws -> Workout {
        // The full deterministic pipeline (US-C01…US-C07) runs through `SessionAssembly`, which
        // chains Steps 1-6 and assembles a timing-fit, fully-formed `Workout`.
        //
        // `sessionPolicy` is threaded through the assembler: its `progressionRate` paces the climb of
        // Earned Reps, its `varietyWindow` orders the bookend stretches, and its cold-start contract
        // drives Step 0. `trainingDay` nil lets the Rotation decide; the Rotation replays `history`.
        let library = try await exerciseService.exercises()
        return SessionAssembly.assemble(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            variation: variation,
            trainingDay: trainingDay,
            history: history,
            asOf: now()
        )
    }

    func trainingPlan(user: User, recentLogs: [WorkoutLog], history: [WorkoutLog], asOf: Date) async throws -> TrainingPlan {
        let library = try await exerciseService.exercises()
        return SessionAssembly.trainingPlan(user: user, library: library, recentLogs: recentLogs, history: history, asOf: asOf)
    }

    func generateRecoveryWorkout(user: User, recentLogs: [WorkoutLog]) async throws -> Workout {
        let library = try await exerciseService.exercises()
        return SessionAssembly.recoveryWorkout(user: user, library: library, recentLogs: recentLogs, asOf: now())
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> SwapOutcome {
        // The deterministic swap (US-C08) runs through `ExerciseSwap`, drawing substitutes from the
        // same validated library the assembler uses so the swap stays in lockstep with the engine.
        // `sessionPolicy` is the same program the session was generated against, so a substitute is
        // sized by the same Step 6 levers - including the cold-start Start Seed (US-O02).
        let library = try await exerciseService.exercises()
        return ExerciseSwap.swap(
            prescription,
            in: workout,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy
        )
    }
}
