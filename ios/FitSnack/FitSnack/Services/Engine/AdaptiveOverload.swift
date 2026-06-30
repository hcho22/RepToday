import Foundation

/// Pipeline Step 6 of the deterministic engine (US-C06): once Step 5 has chosen the exact exercise
/// to prescribe, decide *how much* of it the user should do - sets, and either reps-per-set
/// (rep-based) or hold seconds (hold) - matched to what they have actually demonstrated.
///
/// The promise is "challenging but never absurd": every target is **capacity-relative**, computed
/// from the user's own logged performance, never a fixed heroic number ("100 squats"). The lever is
/// the per-set target (reps or seconds); the set count tracks what the user already sustains.
///
/// - **Demonstrated capacity** - read back from the most recent *usable* (non-skipped, non-empty)
///   logged performance of this exact exercise: the number of sets worked and the rounded average
///   per-set value. A freshly-advanced exercise (Step 5 moved the user up a tier) has no history of
///   its own, so it falls back to the exercise's `defaultReps`/`defaultDurationSeconds`.
/// - **Feedback within one cycle** - that same log's `perceivedDifficulty` steers the next target:
///   `tooHard` eases it below capacity, `tooEasy` pushes it above, `justRight`/no rating nudges it
///   progressively up by at least one. The step per signal is a small percentage (see the tuning
///   constants), so the change is a nudge, never a leap.
/// - **Safety rails** - per-set targets and set counts are clamped to sane floors and ceilings, so
///   even a runaway log can never produce an absurd ("heroic") prescription.
///
/// Like the earlier steps this is a pure function of its inputs - the selected `exercise` and
/// `recentLogs` - with no hidden clock and no UUIDs (the playable `PrescribedExercise`, with its
/// identity and rest, is assembled in Step 7), so it stays deterministic and unit-testable,
/// mirroring `PillarBalance`, `MovementPatternFocus`, `ExercisePoolFilter`, and
/// `ProgressionChainSelection`.

// MARK: - OverloadTarget

/// The capacity-relative prescription Step 6 computes for one exercise: how many `sets`, and either
/// `reps` per set (rep-based movement) or `durationSeconds` per set (hold). Exactly one of
/// `reps`/`durationSeconds` is non-nil, matching the exercise's `isHold`. This is the volume Step 7
/// turns into a full `PrescribedExercise` once it adds rest, identity, and ordering.
struct OverloadTarget: Equatable {
    /// Number of sets to prescribe.
    let sets: Int
    /// Target reps per set (rep-based movements); nil for holds.
    let reps: Int?
    /// Target hold seconds per set (holds); nil for rep-based movements.
    let durationSeconds: Int?
}

// MARK: - AdaptiveOverload

/// Computes capacity-relative rep/set/hold targets (pipeline Step 6).
enum AdaptiveOverload {

    // MARK: Tuning constants

    /// The per-cycle bump curve (the PRD's open question made concrete). Each multiplier is applied
    /// to demonstrated capacity, then rounded; direction is then guaranteed (every signal - easier,
    /// harder, or the progressive nudge - always moves the target by at least one), so a small
    /// capacity can never stall.
    ///
    /// - `progressiveStep` (`justRight` / no rating): nudge just above capacity.
    /// - `easyStep` (`tooEasy`): intensify.
    /// - `hardStep` (`tooHard`): ease.
    static let progressiveStep = 1.05
    static let easyStep = 1.15
    static let hardStep = 0.85

    /// Floors and ceilings for the per-set target. The ceilings are deliberately generous - they
    /// are a safety rail against an absurd prescription, not a normal-range limiter - and the floors
    /// keep a target meaningful after repeated easing.
    static let minReps = 3
    static let maxReps = 50
    static let minHoldSeconds = 10
    static let maxHoldSeconds = 180

    /// Set-count bounds, and the default when the user has no history for the exercise. The exercise
    /// carries a default *per-set* value (`defaultReps`/`defaultDurationSeconds`) but no default set
    /// count, so `defaultSets` supplies it; once there is history the set count tracks what the user
    /// actually sustained.
    static let minSets = 1
    static let maxSets = 4
    static let defaultSets = 3

    // MARK: Target selection

    /// The capacity-relative target for `exercise`, derived from the user's most recent usable
    /// performance of it in `recentLogs` and that session's `perceivedDifficulty`. With no usable
    /// history the exercise's own defaults are used (clamped to the safety rails).
    static func target(for exercise: Exercise, recentLogs: [WorkoutLog]) -> OverloadTarget {
        guard let capacity = demonstratedCapacity(for: exercise, recentLogs: recentLogs) else {
            return defaultTarget(for: exercise)
        }
        let perSet = adjusted(capacity.perSetValue, feedback: capacity.feedback, isHold: exercise.isHold)
        return OverloadTarget(
            sets: clampSets(capacity.sets),
            reps: exercise.isHold ? nil : perSet,
            durationSeconds: exercise.isHold ? perSet : nil
        )
    }

    // MARK: Capacity

    /// What the user demonstrated on an exercise: how many sets they worked, the representative
    /// per-set value, and the session's perceived-difficulty feedback.
    private struct Capacity {
        let sets: Int
        let perSetValue: Int
        let feedback: PerceivedDifficulty?
    }

    /// The user's demonstrated capacity for `exercise`: scan `recentLogs` newest-first and take the
    /// first session that worked it non-skipped with at least one usable set, reading the set count,
    /// the rounded average per-set value (reps for a rep-based movement, seconds for a hold), and
    /// that session's `perceivedDifficulty`. Returns `nil` when no such performance exists, so the
    /// caller falls back to the exercise defaults.
    private static func demonstratedCapacity(
        for exercise: Exercise,
        recentLogs: [WorkoutLog]
    ) -> Capacity? {
        let newestFirst = recentLogs.sorted { $0.completedAt > $1.completedAt }
        for log in newestFirst {
            guard let logged = log.exercises.first(where: {
                $0.exerciseId == exercise.id && !$0.skipped
            }) else { continue }

            let values = logged.completedSets.compactMap { set -> Int? in
                let value = exercise.isHold ? set.durationSeconds : set.reps
                guard let value, value > 0 else { return nil }
                return value
            }
            guard !values.isEmpty else { continue }

            let average = (Double(values.reduce(0, +)) / Double(values.count)).rounded()
            return Capacity(sets: values.count, perSetValue: Int(average), feedback: log.perceivedDifficulty)
        }
        return nil
    }

    /// The starting target when there is no usable history: the exercise's own per-set default over
    /// `defaultSets`, clamped to the safety rails.
    private static func defaultTarget(for exercise: Exercise) -> OverloadTarget {
        if exercise.isHold {
            let seconds = clampPerSet(exercise.defaultDurationSeconds ?? minHoldSeconds, isHold: true)
            return OverloadTarget(sets: defaultSets, reps: nil, durationSeconds: seconds)
        } else {
            let reps = clampPerSet(exercise.defaultReps ?? minReps, isHold: false)
            return OverloadTarget(sets: defaultSets, reps: reps, durationSeconds: nil)
        }
    }

    // MARK: Adjustment

    /// Applies the perceived-difficulty bump to demonstrated `capacity` and clamps to the per-set
    /// rails. `tooEasy` always lands at least one above capacity, `tooHard` at least one below (down
    /// to the floor), and `justRight`/no-rating nudges progressively up by at least one (until the
    /// ceiling) - so the direction of a signal is never lost to rounding.
    private static func adjusted(_ capacity: Int, feedback: PerceivedDifficulty?, isHold: Bool) -> Int {
        let scaled: Int
        switch feedback {
        case .tooHard:
            scaled = min(rounded(capacity, by: hardStep), capacity - 1)
        case .tooEasy:
            scaled = max(rounded(capacity, by: easyStep), capacity + 1)
        case .justRight, .none:
            scaled = max(rounded(capacity, by: progressiveStep), capacity + 1)
        }
        return clampPerSet(scaled, isHold: isHold)
    }

    private static func rounded(_ value: Int, by factor: Double) -> Int {
        Int((Double(value) * factor).rounded())
    }

    private static func clampPerSet(_ value: Int, isHold: Bool) -> Int {
        let lo = isHold ? minHoldSeconds : minReps
        let hi = isHold ? maxHoldSeconds : maxReps
        return min(max(value, lo), hi)
    }

    private static func clampSets(_ sets: Int) -> Int {
        min(max(sets, minSets), maxSets)
    }
}
