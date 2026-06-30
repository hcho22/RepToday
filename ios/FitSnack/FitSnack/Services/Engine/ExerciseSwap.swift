import Foundation

/// Deterministic in-session exercise swap (US-C08): given a workout and one of its prescribed
/// slots, hand back an equivalent substitute the user can do instead - same pillar, same movement
/// pattern, comparable difficulty, fitting the same time slot - so the user stays in control of a
/// movement they dislike or cannot do without breaking the session the engine built.
///
/// This is the engine's one *interactive* step (Steps 1-7 build the session up front; this reshapes
/// a single slot on request), but it obeys the same contract as the rest of the pipeline:
/// - **Equivalence** - a substitute must match the swapped exercise's `pillar` and `movementPattern`
///   and sit within `difficultyBandWidth` of its `difficulty`, so the session keeps the same shape
///   and the slot stays "the same kind of work" rather than turning a push slot into a stretch.
/// - **Safety** - candidates are drawn from `ExercisePoolFilter.eligiblePool`, so every substitute
///   already respects the user's phase, injuries, fitness-level difficulty cap, recent-skip history,
///   and the Zero-Equipment Floor. The swap step never re-derives those rules and never relaxes
///   them: if the only same-pattern options are gated, over-cap, or hard on an injury, there is no
///   safe substitute and the step says so rather than reaching for an unsafe pick.
/// - **Timing fidelity** - the substitute keeps the original slot's set count and rest, so the only
///   wall-clock change is the difference in per-set time between the two movements; a candidate whose
///   best-fit slot would move the session by more than `slotToleranceSeconds` is rejected as
///   out-of-budget. The per-set target itself (reps or hold seconds) is recomputed capacity-relative
///   for the substitute via `AdaptiveOverload`, exactly as assembly would have.
///
/// Like every other engine step this is a pure function of its inputs - the slot, the `Workout`, the
/// `User`, the full `library`, and `recentLogs` - with no hidden clock or library lookup, so a given
/// request always yields the same outcome and is unit-testable, mirroring `ExercisePoolFilter`,
/// `ProgressionChainSelection`, and `AdaptiveOverload`. Only the substitute's fresh `UUID` varies run
/// to run; the chosen movement and its targets are fully determined by the inputs.

// MARK: - SwapOutcome

/// The result of a swap request: either an equivalent substitute, or an honest "no alternative" when
/// no safe, in-band, in-budget movement exists for the slot.
///
/// "No alternative" is a legitimate, expected outcome (a pattern whose only peers are Strength-Phase
/// skills, ruled out by an injury, or all outside the time budget), not an error - so the UI (US-G03)
/// can show a friendly message and keep the original slot rather than the engine substituting
/// something unsafe or off-pattern.
enum SwapOutcome: Equatable {
    /// A valid substitute, ready to drop into the slot in place of the original.
    case substituted(PrescribedExercise)
    /// No safe, equivalent, in-budget substitute exists; the caller keeps the original slot.
    case noAlternative
}

// MARK: - ExerciseSwap

/// Resolves a deterministic, constraint-respecting substitute for one prescribed slot (US-C08).
enum ExerciseSwap {

    // MARK: Tuning constants

    /// How far a substitute's `difficulty` may sit from the swapped exercise's and still count as
    /// "similar" - the difficulty *band* the substitute must fall within. A band of 1 lets a
    /// difficulty-2 movement swap for a 1, 2, or 3 (still subject to the user's fitness-level cap,
    /// which the eligible pool enforces), so the substitute is comparable, never a leap in either
    /// direction. Tunable.
    static let difficultyBandWidth = 1

    /// The most a swap may move the session's wall-clock: the substitute keeps the slot's set count
    /// and rest, so the slot's time changes only by `sets × |Δ est-per-set|`; a candidate whose
    /// change exceeds this is rejected so a swap never meaningfully alters the session length. Tunable.
    static let slotToleranceSeconds = 30

    // MARK: Entry point

    /// The substitute for `prescription` within `workout`, or `.noAlternative` when none qualifies.
    ///
    /// `prescription` is the slot the user asked to replace; `library` is the full catalog (the
    /// substitute pool is the eligible subset of it). The returned `PrescribedExercise`, when present,
    /// is a different movement in the same pillar and pattern, within the difficulty band and the time
    /// budget, with its own capacity-relative per-set target and the original slot's set count and
    /// rest preserved.
    static func swap(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog]
    ) -> SwapOutcome {
        let target = prescription.exercise

        // Draw substitutes from the eligible pool: that single filter already guarantees phase,
        // injury, difficulty-cap, recent-skip, and Zero-Equipment-Floor safety, so the swap step
        // never has to (and never gets to) relax any of them.
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs)

        // Movements already in the session, so a swap never hands back a duplicate of something the
        // user is already doing. The original slot is excluded explicitly below, so its presence here
        // is harmless.
        let inSessionIds = Set(workout.blocks.flatMap(\.exercises).map(\.exercise.id))

        let originalSlotSeconds = slotSeconds(
            estPerSet: target.estimatedTimePerSetSeconds,
            sets: prescription.sets,
            rest: prescription.restSeconds
        )

        // Same pillar + pattern, within the difficulty band, not the original, not already in the
        // session, and close enough in per-set time to keep the slot inside the budget.
        let candidates = pool.compactMap { candidate -> (exercise: Exercise, drift: Int)? in
            guard
                candidate.id != target.id,
                candidate.pillar == target.pillar,
                candidate.movementPattern == target.movementPattern,
                abs(candidate.difficulty - target.difficulty) <= difficultyBandWidth,
                !inSessionIds.contains(candidate.id)
            else { return nil }

            let candidateSlot = slotSeconds(
                estPerSet: candidate.estimatedTimePerSetSeconds,
                sets: prescription.sets,
                rest: prescription.restSeconds
            )
            let drift = abs(candidateSlot - originalSlotSeconds)
            guard drift <= slotToleranceSeconds else { return nil }
            return (candidate, drift)
        }
        guard !candidates.isEmpty else { return .noAlternative }

        let recentlyUsed = recentlyUsedIds(recentLogs: recentLogs)
        let chosen = candidates.min { lhs, rhs in
            // 1. Closest difficulty to the original (a true peer beats a band-edge option).
            let lhsGap = abs(lhs.exercise.difficulty - target.difficulty)
            let rhsGap = abs(rhs.exercise.difficulty - target.difficulty)
            if lhsGap != rhsGap { return lhsGap < rhsGap }
            // 2. Smallest change to the session's wall-clock.
            if lhs.drift != rhs.drift { return lhs.drift < rhs.drift }
            // 3. Variety: prefer a movement the user has not done in the last few sessions.
            let lhsRecent = recentlyUsed.contains(lhs.exercise.id)
            let rhsRecent = recentlyUsed.contains(rhs.exercise.id)
            if lhsRecent != rhsRecent { return !lhsRecent }
            // 4. Deterministic final tie-break.
            return lhs.exercise.id < rhs.exercise.id
        }!.exercise

        return .substituted(materialize(chosen, like: prescription, recentLogs: recentLogs))
    }

    // MARK: Helpers

    /// Builds the substitute prescription: the chosen movement at the original slot's set count and
    /// rest (so timing is preserved), with a fresh capacity-relative per-set target from Step 6. The
    /// target is reps for a rep-based movement and hold seconds for a hold, matched to the
    /// substitute's `isHold`, so a rep↔hold swap within a pattern still yields a well-formed slot.
    private static func materialize(
        _ exercise: Exercise,
        like prescription: PrescribedExercise,
        recentLogs: [WorkoutLog]
    ) -> PrescribedExercise {
        let overload = AdaptiveOverload.target(for: exercise, recentLogs: recentLogs)
        return PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: prescription.sets,
            reps: exercise.isHold ? nil : overload.reps,
            durationSeconds: exercise.isHold ? overload.durationSeconds : nil,
            restSeconds: prescription.restSeconds
        )
    }

    /// Planned wall-clock of one slot in isolation: `sets × estPerSet + (sets - 1) × rest`. The same
    /// formula the assembly step's `plannedSeconds` sums over every slot, so a swap's slot-level
    /// budget check is consistent with how the session was sized.
    private static func slotSeconds(estPerSet: Int, sets: Int, rest: Int) -> Int {
        sets * estPerSet + max(0, sets - 1) * rest
    }

    /// Ids worked (non-skipped) in the most recent few sessions, so a swap can prefer a movement the
    /// user has not just done. The window mirrors Step 5's variety window.
    private static func recentlyUsedIds(recentLogs: [WorkoutLog]) -> Set<String> {
        let recentSessions = recentLogs
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(ProgressionChainSelection.recentSessionWindow)
        return recentSessions.reduce(into: Set<String>()) { ids, log in
            for logged in log.exercises where !logged.skipped {
                ids.insert(logged.exerciseId)
            }
        }
    }
}
