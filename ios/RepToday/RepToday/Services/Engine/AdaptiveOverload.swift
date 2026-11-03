import Foundation

/// Pipeline Step 6 of the deterministic engine (US-C06): once Step 5 has chosen the exact exercise
/// to prescribe, decide *how much* of it the user should do - sets, and either reps-per-set
/// (rep-based) or hold seconds (hold) - matched to what they have actually demonstrated.
///
/// The promise is "challenging but never absurd": every target is **capacity-relative**, read from
/// the user's own logged performance, never a fixed heroic number ("100 squats"). The lever is the
/// per-set target (reps or seconds); the set count tracks what the user already sustains.
///
/// **Round numbers (ADR-0011).** Every per-set target sits on a grid of `step` (5): reps are 10, 15,
/// 20 and up to `maxReps`, holds are 10, 15, 20 seconds and up to the hold ceiling, and nothing is ever
/// prescribed below `minReps`/`minHoldSeconds` (10) - a user who cannot do ten simply does what they
/// can. A per-side movement follows the same grid per side.
///
/// - **Demonstrated capacity** - the most recent *usable* (non-skipped, non-empty) logged performance
///   of this exact exercise, rounded down onto the grid (`onGrid`), so a number logged before the grid
///   existed (13, 14) is served at the round number below it (10) and never below the floor. A
///   freshly-advanced exercise (Step 5 moved the user up a tier) has no history of its own, so it falls
///   back to the exercise's own default, likewise rounded down onto the grid.
/// - **The climb (amends the Asymmetric Ramp, US-E05)** - the target moves one `step` at a time:
///   three sessions in a row at the same number rated "just right" (an unrated session counts as "just
///   right") add 5; "too easy" adds 5 at once; "too hard" or a skip takes 5 off - or, already at the
///   floor, steps the movement one rung down its progression chain (`ProgressionChainSelection`) while
///   the number stays at the floor. When "too hard" comes with the completion screen's "couldn't
///   finish" list, only the moves the user tapped step back; the others hold (`signal(for:in:)`). It
///   still backs off faster than it climbs: one bad day steps back, while a climb takes three good ones.
/// - **Safety rails** - per-set targets and set counts are clamped to sane floors and ceilings, so
///   even a runaway log can never produce an absurd ("heroic") prescription.
///
/// Like the earlier steps this is a pure function of its inputs - the selected `exercise` and
/// `recentLogs` - with no hidden clock and no UUIDs (the playable `PrescribedExercise`, with its
/// identity and rest, is assembled in Step 7), so it stays deterministic and unit-testable,
/// mirroring `MovementPatternFocus`, `ExercisePoolFilter`, and `ProgressionChainSelection`.

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

    /// The one step every per-set target moves by and lands on (ADR-0011): reps and hold seconds are
    /// always a multiple of it.
    static let step = 5

    /// How many sessions in a row at the same number, each rated "just right" (or left unrated), earn
    /// the next `step` at the neutral `progressionRate` (ADR-0011). The Session Policy's
    /// `progressionRate` scales this count (`justRightSessionsToClimb(progressionRate:)`).
    static let justRightSessionsToClimb = 3

    /// The neutral progression rate: the Session Policy default, reproducing the three-session climb.
    static let neutralProgressionRate = 1.0

    /// The neutral Re-entry Ramp scale (US-E06): `1.0` holds nothing back, so the default reproduces
    /// the un-held target exactly. A Return and its Re-entry Ramp pass a scale `< 1.0`
    /// (`ReturnOverride.reentryScale`) to hold the per-set target below normal and walk it back up.
    static let neutralReentryScale = 1.0

    /// The neutral Start Seed volume multiplier (US-O02): `1.0` scales nothing, so the no-history
    /// default target is exactly the exercise's own (grid-rounded) default. A cold-start user at a
    /// higher self-reported fitness level passes a larger multiplier
    /// (`SessionPolicy.ColdStartContract.startingRepMultiplier`) so their *first* prescription of a
    /// movement carries proportionate volume; it is landed on the grid and clamped to the same per-set
    /// rails as every other target, and it never touches a capacity-derived one.
    ///
    /// Aliased from the policy contract's own neutral rather than restated, so the value the
    /// Programmer writes and the value this step falls back to cannot drift apart.
    static let neutralStartingRepMultiplier = SessionPolicy.ColdStartContract.neutralStartingRepMultiplier

    /// Floors and ceilings for the per-set target, all multiples of `step`. The ceilings are
    /// deliberately generous - they are a safety rail against an absurd prescription, not a
    /// normal-range limiter - and the floors are the smallest number ever prescribed (ADR-0011).
    ///
    /// `maxHoldSeconds` bounds what one *set* costs, not the number the player shows: a per-side hold
    /// is clamped to `maxHoldSeconds / sidesPerSet`, landed on the grid, so three minutes stays three
    /// minutes whether the movement is held once or once per side (see `clampPerSet`).
    static let minReps = 10
    static let maxReps = 50
    static let minHoldSeconds = 10
    static let maxHoldSeconds = 180

    /// Set-count bounds, and the default when the user has no history for the exercise. The exercise
    /// carries a default *per-set* value (`defaultReps`/`defaultDurationSeconds`) but no default set
    /// count, so `defaultSets` supplies it; once there is history the set count tracks what the user
    /// actually sustained. Like `neutralStartingRepMultiplier`, `defaultSets` is aliased from the
    /// policy contract's neutral Start Seed so the two cannot drift.
    static let minSets = 1
    static let maxSets = 4
    static let defaultSets = SessionPolicy.ColdStartContract.neutralStartingSets

    // MARK: Signals

    /// What one logged performance of an exercise tells the next target (ADR-0011).
    enum Signal: Equatable {
        /// "Too hard" (on a move the user marked as not finished, or on every move when they marked
        /// none) or a skip: take one `step` off, or step down the chain when already at the floor.
        case stepBack
        /// "Too easy": add one `step` at once.
        case climbNow
        /// "Just right" or unrated: counts toward the run of sessions that earns the next `step`.
        case justRight
        /// A move the user did *not* mark in a "too hard" session that marked others: it neither steps
        /// back nor counts toward the climb, so the number holds and the run of "just right" restarts.
        case hold
    }

    /// The signal one logged move carries, read from its session's rating and the completion screen's
    /// per-move "couldn't finish" marks (ADR-0011). A skip is always a step back. On a "too hard"
    /// session, a session that marked at least one move steps back only the marked moves and holds the
    /// rest; a session that marked none (and every log written before the marks existed) steps every
    /// move back, as "too hard" always has.
    static func signal(for logged: LoggedExercise, in log: WorkoutLog) -> Signal {
        if log.stepsBack(logged) { return .stepBack }
        switch log.perceivedDifficulty {
        case .tooHard:
            return .hold
        case .tooEasy:
            return .climbNow
        case .justRight, .none:
            return .justRight
        }
    }

    /// The number of "just right" sessions in a row at one number that earn the next `step`, scaled by
    /// the Session Policy's `progressionRate` (US-E03, ADR-0011): `3 / rate`, rounded up, never below
    /// one. The neutral rate `1.0` is three sessions; an eased rate (the floor `0.5`) asks for six, and
    /// the fastest rate (`2.0`) for two - so the lever keeps its direction and can never skip a step or
    /// climb by more than one at a time.
    static func justRightSessionsToClimb(progressionRate: Double) -> Int {
        let rate = max(SessionPolicy.minProgressionRate, progressionRate)
        return max(1, Int((Double(justRightSessionsToClimb) / rate).rounded(.up)))
    }

    // MARK: Target selection

    /// The capacity-relative target for `exercise`, derived from the user's recent performances of it
    /// in `recentLogs` and their signals (see `signal(for:in:)`). With no usable history the exercise's
    /// own grid-rounded default is used (clamped to the safety rails).
    ///
    /// `progressionRate` is the Session Policy lever (US-E03): it sets how many "just right" sessions a
    /// climb takes (`justRightSessionsToClimb(progressionRate:)`); every climb is still one `step`. A
    /// no-history default (which has no climb to pace) is unchanged by it.
    ///
    /// `reentryScale` is the Return / Re-entry Ramp lever (US-E06): `1.0` is neutral (no-op), while a
    /// value `< 1.0` (`ReturnOverride.reentryScale`) holds the *capacity-derived* per-set target below
    /// what it would otherwise be: the scaled value rounded down onto the grid, and always at least one
    /// `step` below the un-held target (down to the floor), so the ease is never lost to rounding. A
    /// no-history default is already the gentle starting value and is left untouched.
    ///
    /// `heldSince` is when a Re-entry Ramp's held run began (`ReturnOverride.heldSince`, the Return
    /// session), `nil` otherwise. The held target is then read from the capacity the user demonstrated
    /// *before* it, so each held session is not held against the previous one's held number; but once a
    /// session in the held run steps this move back ("too hard", "couldn't finish" or a skip), the move
    /// is never served above the climb's own target over every log - that session's number less one
    /// `step` - until a later session earns it back by the normal climb (ADR-0011).
    ///
    /// `startingRepMultiplier` / `startingSets` are the cold-start **Start Seed** (US-O02), and they
    /// apply *only* to the no-history default target - the very first prescription of a movement. The
    /// multiplier scales the grid-rounded default and lands on the nearest grid number (never below
    /// the default for a multiplier above one), and both are clamped to the existing rails and ignored
    /// the moment the user has logged the movement. The neutral values reproduce the default precisely.
    static func target(
        for exercise: Exercise,
        recentLogs: [WorkoutLog],
        progressionRate: Double = neutralProgressionRate,
        reentryScale: Double = neutralReentryScale,
        heldSince: Date? = nil,
        startingRepMultiplier: Double = neutralStartingRepMultiplier,
        startingSets: Int = defaultSets
    ) -> OverloadTarget {
        let baseLogs = heldSince.map { since in recentLogs.filter { $0.completedAt < since } } ?? recentLogs
        let target: OverloadTarget
        if let capacity = demonstratedCapacity(for: exercise, recentLogs: baseLogs) {
            let perSet = adjusted(
                capacity,
                isHold: exercise.isHold,
                sides: exercise.sidesPerSet,
                progressionRate: progressionRate,
                reentryScale: reentryScale
            )
            target = OverloadTarget(
                sets: clampSets(capacity.sets),
                reps: exercise.isHold ? nil : perSet,
                durationSeconds: exercise.isHold ? perSet : nil
            )
        } else {
            target = defaultTarget(
                for: exercise,
                startingRepMultiplier: startingRepMultiplier,
                startingSets: startingSets
            )
        }

        guard
            let heldSince,
            recentLogs.contains(where: { log in
                log.completedAt >= heldSince
                    && log.exercises.contains { $0.exerciseId == exercise.id && log.stepsBack($0) }
            }),
            let latest = demonstratedCapacity(for: exercise, recentLogs: recentLogs)
        else { return target }
        let ceiling = adjusted(
            latest,
            isHold: exercise.isHold,
            sides: exercise.sidesPerSet,
            progressionRate: progressionRate,
            reentryScale: neutralReentryScale
        )
        return OverloadTarget(
            sets: target.sets,
            reps: target.reps.map { min($0, ceiling) },
            durationSeconds: target.durationSeconds.map { min($0, ceiling) }
        )
    }

    /// When the user's most recent outcome on `exercise` is a step back *at the floor* - "too hard"
    /// (or a skip) on a move already at ten reps or ten seconds - the date of that outcome, else `nil`.
    /// The number cannot go lower, so Step 5 serves the rung below on the movement's progression chain
    /// instead (`ProgressionChainSelection`), and only a later session's clean performance there earns
    /// the way back up (ADR-0011).
    static func floorStepBackDate(for exercise: Exercise, recentLogs: [WorkoutLog]) -> Date? {
        guard
            let capacity = demonstratedCapacity(for: exercise, recentLogs: recentLogs),
            capacity.signal == .stepBack,
            capacity.value <= floor(isHold: exercise.isHold, sides: exercise.sidesPerSet)
        else { return nil }
        return capacity.signalDate
    }

    // MARK: Grid

    /// `value` rounded down onto the grid and clamped to the per-set rails: a multiple of `step`, never
    /// below the floor (10) and never above the ceiling. This is how a number logged before the grid
    /// existed - or a catalog default such as 12 - becomes the round number the user is served
    /// (ADR-0011).
    static func onGrid(_ value: Int, isHold: Bool, sides: Int) -> Int {
        clampPerSet((value / step) * step, isHold: isHold, sides: sides)
    }

    // MARK: Capacity

    /// What the user demonstrated on an exercise: how many sets they worked, the grid value they worked
    /// at, the signal for the next target, the session date that signal came from, and how many
    /// sessions in a row (newest first) were "just right" at that same grid value.
    private struct Capacity {
        let sets: Int
        let value: Int
        let signal: Signal
        let signalDate: Date
        let justRightRun: Int
    }

    /// The user's demonstrated capacity for `exercise`: scan `recentLogs` newest-first and take the
    /// first session that worked it non-skipped with at least one usable set, reading the set count and
    /// the rounded average per-set value (reps for a rep-based movement, seconds for a hold), landed on
    /// the grid. A **more-recent skip** of this exercise (encountered before the worked session) is a
    /// step back (US-E05) that overrides the worked session's own rating. Otherwise the signal is that
    /// session's own (`signal(for:in:)`), and the "just right" run counts it and the consecutive older
    /// sessions that were also "just right" at the same grid value. Returns `nil` when no worked
    /// performance exists, so the caller falls back to the exercise defaults.
    private static func demonstratedCapacity(
        for exercise: Exercise,
        recentLogs: [WorkoutLog]
    ) -> Capacity? {
        let newestFirst = recentLogs.sorted { $0.completedAt > $1.completedAt }
        var recentSkipDate: Date?
        var latest: (sets: Int, value: Int, signal: Signal, date: Date)?
        var run = 0
        for log in newestFirst {
            guard let logged = log.exercises.first(where: { $0.exerciseId == exercise.id }) else {
                continue
            }
            if logged.skipped {
                // A skip before the first worked session overrides its signal; a skip below it ends
                // the "just right" run like any other non-"just right" session.
                if latest == nil {
                    if recentSkipDate == nil { recentSkipDate = log.completedAt }
                    continue
                }
                break
            }
            guard let value = gridValue(of: logged, for: exercise) else { continue }

            let signal = signal(for: logged, in: log)
            guard let first = latest else {
                latest = (value.sets, value.perSet, signal, log.completedAt)
                if recentSkipDate == nil, signal == .justRight { run = 1 } else { break }
                continue
            }
            guard signal == .justRight, value.perSet == first.value else { break }
            run += 1
        }
        guard let latest else { return nil }
        if let recentSkipDate {
            return Capacity(sets: latest.sets, value: latest.value, signal: .stepBack, signalDate: recentSkipDate, justRightRun: 0)
        }
        return Capacity(sets: latest.sets, value: latest.value, signal: latest.signal, signalDate: latest.date, justRightRun: run)
    }

    /// The set count and grid value of one logged performance, or `nil` when it carries no usable set.
    private static func gridValue(of logged: LoggedExercise, for exercise: Exercise) -> (sets: Int, perSet: Int)? {
        let values = logged.completedSets.compactMap { set -> Int? in
            let value = exercise.isHold ? set.durationSeconds : set.reps
            guard let value, value > 0 else { return nil }
            return value
        }
        guard !values.isEmpty else { return nil }
        let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return (values.count, onGrid(average, isHold: exercise.isHold, sides: exercise.sidesPerSet))
    }

    /// The starting target when there is no usable history: the exercise's own per-set default rounded
    /// down onto the grid, scaled by the Start Seed's `startingRepMultiplier` (landing on the nearest
    /// grid number) over `startingSets` (US-O02), clamped to the safety rails. The neutral seed (`x1.0`,
    /// `defaultSets`) is the grid-rounded default exactly.
    private static func defaultTarget(
        for exercise: Exercise,
        startingRepMultiplier: Double,
        startingSets: Int
    ) -> OverloadTarget {
        let sets = clampSets(startingSets)
        let sides = exercise.sidesPerSet
        let base = exercise.isHold
            ? (exercise.defaultDurationSeconds ?? minHoldSeconds)
            : (exercise.defaultReps ?? minReps)
        let gridBase = onGrid(base, isHold: exercise.isHold, sides: sides)
        let seeded = nearestOnGrid(Double(gridBase) * max(0, startingRepMultiplier), isHold: exercise.isHold, sides: sides)
        return OverloadTarget(
            sets: sets,
            reps: exercise.isHold ? nil : seeded,
            durationSeconds: exercise.isHold ? seeded : nil
        )
    }

    // MARK: Adjustment

    /// Applies the climb (ADR-0011) to demonstrated `capacity`, then the Return / Re-entry Ramp hold
    /// (US-E06), and clamps to the per-set rails. A step back takes one `step` off (down to the floor),
    /// "too easy" adds one, a held move stays, and a run of "just right" sessions at the same number as
    /// long as `justRightSessionsToClimb(progressionRate:)` adds one.
    ///
    /// A `reentryScale < 1.0` (US-E06) then holds that result below the normal target: the scaled
    /// value rounded down onto the grid, and at least one `step` below the un-held target (down to the
    /// floor), so a Return / Re-entry Ramp session is always gentler than the un-held session while
    /// remaining within the rails. The neutral `1.0` is a no-op.
    private static func adjusted(
        _ capacity: Capacity,
        isHold: Bool,
        sides: Int,
        progressionRate: Double,
        reentryScale: Double
    ) -> Int {
        let current = capacity.value
        let next: Int
        switch capacity.signal {
        case .stepBack:
            next = current - step
        case .climbNow:
            next = current + step
        case .hold:
            next = current
        case .justRight:
            next = capacity.justRightRun >= justRightSessionsToClimb(progressionRate: progressionRate)
                ? current + step
                : current
        }
        let unheld = onGrid(next, isHold: isHold, sides: sides)
        guard reentryScale < neutralReentryScale else { return unheld }
        let scaled = Int((Double(unheld) * max(0, reentryScale)).rounded(.down))
        return onGrid(min(scaled, unheld - step), isHold: isHold, sides: sides)
    }

    /// `value` landed on the nearest grid number and clamped to the rails (a tie rounds up).
    private static func nearestOnGrid(_ value: Double, isHold: Bool, sides: Int) -> Int {
        let steps = (value / Double(step)).rounded(.toNearestOrAwayFromZero)
        return clampPerSet(Int(steps) * step, isHold: isHold, sides: sides)
    }

    /// The per-set floor for a movement: 10 reps or 10 seconds (per side), or the ceiling when a
    /// per-side hold's ceiling would sit below it.
    private static func floor(isHold: Bool, sides: Int) -> Int {
        clampPerSet(0, isHold: isHold, sides: sides)
    }

    /// Clamps a per-set target to the safety rails, reading `maxHoldSeconds` as the ceiling on what the
    /// *set* costs rather than on the number shown, landed on the grid.
    ///
    /// A per-side hold is performed once per side, so a prescribed "90 seconds" of `core_side_plank` is
    /// three minutes of holding. Capping the prescribed number alone would let an `isPerSide` movement
    /// reach six minutes in a single set - past the entire budget of a 5-minute session - which is
    /// exactly the absurd prescription the rail exists to prevent. Dividing the ceiling by `sides` (and
    /// rounding it down onto the grid) makes the rail mean what its doc says for every movement. The
    /// floor stays per-side (10 seconds a side is still a meaningful hold), and `min` keeps it from
    /// crossing the divided ceiling.
    private static func clampPerSet(_ value: Int, isHold: Bool, sides: Int) -> Int {
        let effectiveSides = max(1, sides)
        let hi = isHold ? (maxHoldSeconds / effectiveSides / step) * step : maxReps
        let lo = min(isHold ? minHoldSeconds : minReps, hi)
        return min(max(value, lo), hi)
    }

    private static func clampSets(_ sets: Int) -> Int {
        min(max(sets, minSets), maxSets)
    }
}
