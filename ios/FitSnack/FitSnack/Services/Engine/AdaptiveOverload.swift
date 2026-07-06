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
/// - **The Asymmetric Ramp (US-E05)** - that same log's `perceivedDifficulty` (or a skip) steers the
///   next target, and it does so *asymmetrically*: it backs off fast and climbs slow. A single recent
///   `tooHard` **or a skip** of this exercise pulls the next target down eagerly (the larger step),
///   `tooEasy` nudges it up only patiently (a smaller step), and `justRight`/no rating nudges it
///   progressively up by the gentlest step. Every signal moves the target by at least one so its
///   direction is never lost to rounding, and the down-step magnitude is always >= the up-step, so a
///   user is never overwhelmed by a too-hard day and never bored by a too-easy one.
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

    /// The per-cycle bump curve (the PRD's open question made concrete), tuned as the **Asymmetric
    /// Ramp** (US-E05): back off fast, climb slow. Each multiplier is applied to demonstrated
    /// capacity, then rounded; direction is then guaranteed (every signal - easier, harder, or the
    /// progressive nudge - always moves the target by at least one), so a small capacity can never
    /// stall.
    ///
    /// - `progressiveStep` (`justRight` / no rating): the gentlest nudge just above capacity.
    /// - `easyStep` (`tooEasy`): a patient climb above capacity.
    /// - `hardStep` (`tooHard` or a **skip**): an eager back-off below capacity.
    ///
    /// The asymmetry invariant is `(1 - hardStep) >= (easyStep - 1)`: the down-step is at least as
    /// large as the up-step (here twice as large - a 20% eager back-off against a 10% patient climb),
    /// so a too-hard day is corrected decisively while a too-easy day advances only gradually. A skip
    /// is treated as an eager down-signal exactly like `tooHard` (the user bailed; that was too much).
    ///
    /// The two *advancing* steps (`progressiveStep`/`easyStep`) are scaled by the Session Policy's
    /// `progressionRate` (US-E03): the deviation-from-capacity grows with the rate, so a higher rate
    /// advances reps/holds faster while still clamping to the safety rails. The neutral rate `1.0`
    /// leaves the curve exactly as it was, so `SessionPolicy.default` is a no-op. `hardStep` is a
    /// safety response to a too-hard/skip signal, so the rate never scales the ease (a faster program
    /// must not back off harder): the eager down-step is a fixed property of the ramp. (Because only
    /// the up-steps are paced, a deliberately aggressive `progressionRate` can climb faster than the
    /// fixed back-off - the asymmetry is a property of the base ramp at the neutral rate, by design.)
    static let progressiveStep = 1.05
    static let easyStep = 1.10
    static let hardStep = 0.80

    /// The neutral progression rate: the Session Policy default, reproducing the pre-policy curve.
    static let neutralProgressionRate = 1.0

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
    ///
    /// `progressionRate` is the Session Policy lever (US-E03) scaling the advancing bump: `1.0` is
    /// neutral (pre-policy behavior), a higher rate advances reps/holds faster. It only affects the
    /// step *up* from demonstrated capacity, so a no-history default (which has no bump to scale) is
    /// unchanged by it.
    static func target(
        for exercise: Exercise,
        recentLogs: [WorkoutLog],
        progressionRate: Double = neutralProgressionRate
    ) -> OverloadTarget {
        guard let capacity = demonstratedCapacity(for: exercise, recentLogs: recentLogs) else {
            return defaultTarget(for: exercise)
        }
        let perSet = adjusted(
            capacity.perSetValue,
            signal: capacity.signal,
            isHold: exercise.isHold,
            progressionRate: progressionRate
        )
        return OverloadTarget(
            sets: clampSets(capacity.sets),
            reps: exercise.isHold ? nil : perSet,
            durationSeconds: exercise.isHold ? perSet : nil
        )
    }

    // MARK: Capacity

    /// The direction the Asymmetric Ramp (US-E05) moves the next target, resolved from the most
    /// recent signal: `eased` (an eager down-step on `tooHard` or a **skip**), `intensify` (a patient
    /// up-step on `tooEasy`), or `progress` (the gentlest nudge up on `justRight`/no rating).
    private enum RampSignal {
        case eased
        case intensify
        case progress
    }

    /// What the user demonstrated on an exercise: how many sets they worked, the representative
    /// per-set value, and the resolved ramp signal for the next target.
    private struct Capacity {
        let sets: Int
        let perSetValue: Int
        let signal: RampSignal
    }

    /// The user's demonstrated capacity for `exercise`: scan `recentLogs` newest-first and take the
    /// first session that worked it non-skipped with at least one usable set, reading the set count,
    /// the rounded average per-set value (reps for a rep-based movement, seconds for a hold), and the
    /// resolved ramp signal. A **more-recent skip** of this exercise (encountered before the worked
    /// session) is the Asymmetric Ramp's eager down-signal (US-E05): it overrides the worked session's
    /// own rating so the next target eases, regardless of how that earlier session felt. Returns `nil`
    /// when no worked performance exists, so the caller falls back to the exercise defaults.
    private static func demonstratedCapacity(
        for exercise: Exercise,
        recentLogs: [WorkoutLog]
    ) -> Capacity? {
        let newestFirst = recentLogs.sorted { $0.completedAt > $1.completedAt }
        var sawRecentSkip = false
        for log in newestFirst {
            guard let logged = log.exercises.first(where: { $0.exerciseId == exercise.id }) else {
                continue
            }
            if logged.skipped {
                sawRecentSkip = true
                continue
            }

            let values = logged.completedSets.compactMap { set -> Int? in
                let value = exercise.isHold ? set.durationSeconds : set.reps
                guard let value, value > 0 else { return nil }
                return value
            }
            guard !values.isEmpty else { continue }

            let average = (Double(values.reduce(0, +)) / Double(values.count)).rounded()
            let signal: RampSignal = sawRecentSkip ? .eased : rampSignal(for: log.perceivedDifficulty)
            return Capacity(sets: values.count, perSetValue: Int(average), signal: signal)
        }
        return nil
    }

    /// Maps a session's `perceivedDifficulty` to the ramp direction. A skip is handled upstream in
    /// `demonstratedCapacity` (it forces `.eased` before this is consulted).
    private static func rampSignal(for difficulty: PerceivedDifficulty?) -> RampSignal {
        switch difficulty {
        case .tooHard: return .eased
        case .tooEasy: return .intensify
        case .justRight, .none: return .progress
        }
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

    /// Applies the Asymmetric Ramp (US-E05) to demonstrated `capacity` and clamps to the per-set
    /// rails. `.eased` (a `tooHard` or a skip) lands at least one below capacity via the eager
    /// `hardStep` (down to the floor), `.intensify` (`tooEasy`) at least one above via the patient
    /// `easyStep`, and `.progress` (`justRight`/no rating) at least one above via the gentlest
    /// `progressiveStep` - so the direction of a signal is never lost to rounding. The two advancing
    /// steps are scaled by `progressionRate` (US-E03); the eager down-step is not (see `hardStep`).
    private static func adjusted(
        _ capacity: Int,
        signal: RampSignal,
        isHold: Bool,
        progressionRate: Double
    ) -> Int {
        let scaled: Int
        switch signal {
        case .eased:
            scaled = min(rounded(capacity, by: hardStep), capacity - 1)
        case .intensify:
            scaled = max(rounded(capacity, by: paced(easyStep, rate: progressionRate)), capacity + 1)
        case .progress:
            scaled = max(rounded(capacity, by: paced(progressiveStep, rate: progressionRate)), capacity + 1)
        }
        return clampPerSet(scaled, isHold: isHold)
    }

    /// Scales an advancing multiplier by `progressionRate` around `1.0`: the deviation from
    /// no-change (`step - 1`) grows with the rate, so a faster program advances by more each cycle
    /// while the neutral rate `1.0` reproduces `step` exactly. Only advancing steps (>= 1) are paced.
    private static func paced(_ step: Double, rate: Double) -> Double {
        1.0 + (step - 1.0) * rate
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
