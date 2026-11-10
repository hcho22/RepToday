import Foundation

/// Pipeline Step 6 of the deterministic engine (US-C06, reshaped by US-TD03): once a station's rung is
/// chosen, decide *how much* of it the user does, matched to what they have earned.
///
/// The promise is "challenging but never absurd": every target is read from the user's own rated
/// sessions, never a fixed heroic number. Since Training Days (ADR-0013) the set count is fixed at
/// `RepGrammar.setsPerStation`, so the lever is the per-set number - reps, or hold seconds.
///
/// - **Earned Reps** (`earned(for:...)`) - the per-movement number the user has earned, inside
///   `RepGrammar.earnedRange` for their level. Every prescription records it (`PrescribedExercise
///   .earnedReps`), so a log says what was earned even when the session padded above it or cut below
///   it; a log written before Training Days recorded earned = performed (`LoggedExercise.earnedValue`).
///   A movement with no history opens at the bottom of the range.
/// - **The climb** (the M1 planning default; ADR-0013 records how it replaces ADR-0011's three-session
///   climb) - one `step` after each session, not rated too hard, whose prescription was at or above
///   Earned Reps; "too easy" adds a step at once. "Too hard" or a skip takes a step off - or, already at
///   the bottom of the range, steps the movement one rung down its chain (`ProgressionChainSelection`).
///   When "too hard" comes with the "couldn't finish" list, only the moves the user tapped step back
///   (`signal(for:in:)`). The Session Policy pace sets how many such sessions a climb takes.
/// - **Padding and Practice never move it** - a padded set climbs exactly as a set at Earned Reps does,
///   one step; a Practice station never counts at all (`LoggedExercise.countsForProgression`).
/// - **Return** - a Return or Re-entry Ramp session scales the *prescription*, not Earned Reps: the
///   served number sits at least a step under them, never below the short-session floor.
///
/// Pure over its inputs - no clock, no ids - like the rest of the engine.

// MARK: - OverloadTarget

/// The prescription Step 6 computes for one station: the fixed set count, the per-set number it is
/// served at (`reps` or `durationSeconds`, matching the exercise's `isHold`), and the Earned Reps (or
/// hold seconds) behind it, which Step 7 copies onto the prescription.
struct OverloadTarget: Equatable {
    /// Number of sets to prescribe.
    let sets: Int
    /// Target reps per set (rep-based movements); nil for holds.
    let reps: Int?
    /// Target hold seconds per set (holds); nil for rep-based movements.
    let durationSeconds: Int?
    /// The Earned Reps (or hold seconds) the served number was derived from.
    let earned: Int

    /// The served per-set number, whichever kind it is.
    var value: Int { reps ?? durationSeconds ?? 0 }
}

// MARK: - AdaptiveOverload

enum AdaptiveOverload {

    // MARK: Tuning constants

    /// The one step every per-set number moves by and lands on (ADR-0011, `RepGrammar.step`).
    static let step = RepGrammar.step

    /// Qualifying sessions a climb takes at the neutral pace (the M1 planning default): one.
    static let qualifyingSessionsToClimb = 1

    /// Neutral Session Policy pace.
    static let neutralProgressionRate = 1.0

    /// Neutral Return / Re-entry Ramp scale: the prescription is not held below Earned Reps.
    static let neutralReentryScale = 1.0

    /// Neutral cold-start multiplier on a no-history opening number.
    static let neutralStartingRepMultiplier = SessionPolicy.ColdStartContract.neutralStartingRepMultiplier

    // MARK: Signals

    /// What one rated session says about one move.
    enum Signal: Equatable {
        /// Take a step off (or, at the bottom of the range, step down the chain): a skip, "too hard" on a
        /// move marked "couldn't finish", or "too hard" with nothing marked.
        case stepBack
        /// Add a step now: "too easy".
        case climbNow
        /// A session not rated too hard: it climbs when its prescription reached Earned Reps.
        case justRight
        /// Neither climb nor step back: an unmarked move in a "too hard" session that marked others.
        case hold
    }

    /// The signal `logged` takes from `log`. The step back is `WorkoutLog.stepsBack(_:)`, the one
    /// definition shared with advancement.
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

    /// Qualifying sessions in a row a climb takes at `progressionRate`: `ceil(1 / rate)`, so the
    /// neutral pace climbs every qualifying session and the slowest (0.5) every second one.
    static func qualifyingSessionsToClimb(progressionRate: Double) -> Int {
        let rate = max(SessionPolicy.minProgressionRate, progressionRate)
        return max(1, Int((Double(qualifyingSessionsToClimb) / rate).rounded(.up)))
    }

    // MARK: Target selection

    /// The main or core prescription for `exercise`: four sets at its served Earned Reps, held under
    /// them by a Return or Re-entry Ramp (`reentryScale < 1`).
    static func target(
        for exercise: Exercise,
        level: FitnessLevel,
        recentLogs: [WorkoutLog],
        progressionRate: Double = neutralProgressionRate,
        reentryScale: Double = neutralReentryScale,
        steppedDownSince: Date? = nil,
        startingRepMultiplier: Double = neutralStartingRepMultiplier
    ) -> OverloadTarget {
        let kind = RepGrammar.kind(of: exercise)
        let earned = earned(
            for: exercise,
            level: level,
            recentLogs: recentLogs,
            progressionRate: progressionRate,
            steppedDownSince: steppedDownSince,
            startingRepMultiplier: startingRepMultiplier
        )
        var served = RepGrammar.served(earned: earned, for: kind, level: level)
        if reentryScale < neutralReentryScale {
            let scaled = RepGrammar.floored(Int((Double(served) * max(0, reentryScale)).rounded(.down)))
            served = max(RepGrammar.shortSessionFloor(for: kind), min(scaled, served - step))
        }
        return make(exercise, value: served, earned: earned)
    }

    /// An `OverloadTarget` for `exercise` at `value` per set, four sets, recording `earned`.
    static func make(_ exercise: Exercise, value: Int, earned: Int) -> OverloadTarget {
        OverloadTarget(
            sets: RepGrammar.setsPerStation,
            reps: exercise.isHold ? nil : value,
            durationSeconds: exercise.isHold ? value : nil,
            earned: earned
        )
    }

    /// The user's Earned Reps (or hold seconds) for `exercise`, inside the earned range for `level`.
    ///
    /// Read from the newest session that worked the move (Practice stations never count). With none: the
    /// bottom of the range - lifted by a cold-start multiplier, never to the top, so a seeded first
    /// session cannot clear the rung. `steppedDownSince` (the move was stepped down onto) reads only the
    /// sessions after the step down, opening at the bottom of the range.
    static func earned(
        for exercise: Exercise,
        level: FitnessLevel,
        recentLogs: [WorkoutLog],
        progressionRate: Double = neutralProgressionRate,
        steppedDownSince: Date? = nil,
        startingRepMultiplier: Double = neutralStartingRepMultiplier
    ) -> Int {
        let range = RepGrammar.earnedRange(for: exercise, level: level)
        let history = entries(for: exercise, level: level, recentLogs: recentLogs, since: steppedDownSince)
        guard let latest = history.first else {
            guard steppedDownSince == nil else { return range.lowerBound }
            return seeded(range: range, multiplier: startingRepMultiplier)
        }
        let next: Int
        switch latest.signal {
        case .stepBack:
            next = latest.earned - step
        case .climbNow:
            next = latest.earned + step
        case .hold:
            next = latest.earned
        case .justRight:
            let run = history.prefix { $0.qualifies && $0.earned == latest.earned }.count
            next = run >= qualifyingSessionsToClimb(progressionRate: progressionRate)
                ? latest.earned + step
                : latest.earned
        }
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// When the newest session on `exercise` stepped it back while it already sat at the bottom of the
    /// range - the session that steps the user one rung down its chain - else `nil`.
    static func floorStepBackDate(for exercise: Exercise, level: FitnessLevel, recentLogs: [WorkoutLog]) -> Date? {
        guard let latest = entries(for: exercise, level: level, recentLogs: recentLogs, since: nil).first,
              latest.signal == .stepBack,
              latest.earned <= RepGrammar.earnedRange(for: exercise, level: level).lowerBound
        else { return nil }
        return latest.date
    }

    // MARK: History

    /// One session's reading of a move: the Earned Reps it recorded (inside the range), its signal, and
    /// whether its prescription reached Earned Reps.
    private struct Entry {
        let date: Date
        let earned: Int
        let signal: Signal
        let qualifies: Bool
    }

    /// The sessions that worked `exercise`, newest first. A skip counts (it steps back) and a Practice
    /// station never does. A log written before Training Days carries no Earned Reps and recorded
    /// earned = performed, so it is read only when it was not held under capacity by a Return or ramp
    /// (`ReturnOverride.splitHeld`) - a held session's performed number is not what the user earned.
    private static func entries(
        for exercise: Exercise,
        level: FitnessLevel,
        recentLogs: [WorkoutLog],
        since: Date?
    ) -> [Entry] {
        let held = Set(ReturnOverride.splitHeld(recentLogs).held.map(\.id))
        let range = RepGrammar.earnedRange(for: exercise, level: level)
        var result: [Entry] = []
        var skipDates: [Date] = []
        for log in recentLogs.sorted(by: { $0.completedAt > $1.completedAt }) {
            if let since, log.completedAt <= since { continue }
            guard let logged = log.exercises.first(where: { $0.exerciseId == exercise.id && $0.role != .practice })
            else { continue }
            if logged.skipped {
                skipDates.append(log.completedAt)
                continue
            }
            let recordsEarned = (exercise.isHold ? logged.earnedDurationSeconds : logged.earnedReps) != nil
            guard recordsEarned || !held.contains(log.id),
                  let earnedValue = logged.earnedValue(isHold: exercise.isHold) else { continue }
            let earned = min(max(RepGrammar.floored(earnedValue), range.lowerBound), range.upperBound)
            let performed = logged.completedSets
                .compactMap { exercise.isHold ? $0.durationSeconds : $0.reps }
                .filter { $0 > 0 }
                .min() ?? 0
            result.append(Entry(
                date: log.completedAt,
                earned: earned,
                signal: signal(for: logged, in: log),
                qualifies: performed >= earned
            ))
        }
        // A skip newer than the newest worked session steps that session's number back: the skip is the
        // newest signal on the move, and a skip carries no number of its own.
        if let newestSkip = skipDates.first, let newest = result.first, newestSkip > newest.date {
            result.insert(Entry(date: newestSkip, earned: newest.earned, signal: .stepBack, qualifies: false), at: 0)
        }
        return result
    }

    /// The opening number for a move with no history: the bottom of the range, scaled by a cold-start
    /// multiplier onto the nearest grid number, never above one step under the top.
    private static func seeded(range: ClosedRange<Int>, multiplier: Double) -> Int {
        let scaled = Double(range.lowerBound) * max(0, multiplier)
        let nearest = Int((scaled / Double(step)).rounded(.toNearestOrAwayFromZero)) * step
        return min(max(nearest, range.lowerBound), max(range.lowerBound, range.upperBound - step))
    }
}
