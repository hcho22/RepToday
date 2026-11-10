import Foundation

/// The one owner of the Training Day set grammar (US-TD03, ADR-0013): how many sets a station runs,
/// which rep and hold numbers exist, how far a short session may go below Earned Reps, what a Practice
/// Movement is prescribed at, and what clears a rung.
///
/// - **Sets.** Every main, Practice and core station runs exactly `setsPerStation` (4) rounds, at every
///   length. Session length moves reps and rest, never sets.
/// - **Steps.** Every rep and hold number is a multiple of `step` (5), ADR-0011's grid.
/// - **Earned range** (decision 14), by kind and level: reps 15-30 for beginner and intermediate and
///   15-50 for advanced; reps per side 5-15; holds 20-60 seconds (advanced to 90), per side the same.
///   Earned Reps live inside it; Padding fills a long session up to its top.
/// - **Short-session floor** (decision 16): a short session may serve below Earned Reps, never below
///   10 reps, 5 reps per side, or a 10-second hold.
/// - **Practice** (decision 9): 4 x 10 reps, 4 x 5 per side, 15-second holds.
/// - **Advancement** (decision 15): four clean sets at the top of the range, at earned reps, in a session
///   not rated too hard and not marked "couldn't finish".
///
/// Pure and clock-free like the rest of the engine.
enum RepGrammar {

    /// The rounds every Training Day station runs.
    static let setsPerStation = 4

    /// The grid every rep and hold number sits on.
    static let step = 5

    /// How a movement is counted, which decides its range, floor and Practice value.
    enum Kind: Equatable {
        /// Reps counted across both sides at once.
        case reps
        /// Reps counted per side (`Exercise.isPerSide`).
        case repsPerSide
        /// A timed hold, in seconds (per side when the movement is per side).
        case hold
    }

    static func kind(of exercise: Exercise) -> Kind {
        if exercise.isHold { return .hold }
        return exercise.isPerSide == true ? .repsPerSide : .reps
    }

    /// The range Earned Reps (or hold seconds) live in, and Padding fills up to (decision 14).
    static func earnedRange(for kind: Kind, level: FitnessLevel) -> ClosedRange<Int> {
        switch kind {
        case .reps: return 15...(level == .advanced ? 50 : 30)
        case .repsPerSide: return 5...15
        case .hold: return 20...(level == .advanced ? 90 : 60)
        }
    }

    static func earnedRange(for exercise: Exercise, level: FitnessLevel) -> ClosedRange<Int> {
        earnedRange(for: kind(of: exercise), level: level)
    }

    /// The lowest a short session may serve (decision 16), below the bottom of the earned range.
    static func shortSessionFloor(for kind: Kind) -> Int {
        switch kind {
        case .reps: return 10
        case .repsPerSide: return 5
        case .hold: return 10
        }
    }

    /// What a Practice Movement - the next harder rung - is prescribed at (decision 9).
    static func practiceValue(for kind: Kind) -> Int {
        switch kind {
        case .reps: return 10
        case .repsPerSide: return 5
        case .hold: return 15
        }
    }

    /// `value` floored onto the grid.
    static func floored(_ value: Int) -> Int {
        (max(0, value) / step) * step
    }

    /// `earned` as it is served: floored onto the grid and held inside the earned range. Earned Reps
    /// are stored as the engine computed them; a number logged before the grid (13) serves as 10, and
    /// the range then lifts it to its bottom.
    static func served(earned: Int, for kind: Kind, level: FitnessLevel) -> Int {
        let range = earnedRange(for: kind, level: level)
        return min(max(floored(earned), range.lowerBound), range.upperBound)
    }

    // MARK: Advancement

    /// Whether `logged` clears its rung (decision 15): it counts toward advancement, the session was not
    /// rated too hard, at least four sets reached the top of the user's range, and the station was
    /// prescribed at earned reps that had themselves reached the top - so Padding can never clear a rung.
    static func isAdvancementMet(
        by logged: LoggedExercise,
        in log: WorkoutLog,
        exercise: Exercise,
        level: FitnessLevel
    ) -> Bool {
        guard logged.exerciseId == exercise.id,
              log.countsTowardAdvancement(logged),
              log.perceivedDifficulty != .tooHard else { return false }
        let top = earnedRange(for: exercise, level: level).upperBound
        let atTop = logged.completedSets.filter { set in
            (exercise.isHold ? set.durationSeconds : set.reps).map { $0 >= top } ?? false
        }
        guard atTop.count >= setsPerStation else { return false }
        return (logged.earnedValue(isHold: exercise.isHold) ?? 0) >= top
    }

    /// Whether any of `logs` clears `exercise`'s rung for a user at `level`.
    static func hasCleared(_ exercise: Exercise, in logs: [WorkoutLog], level: FitnessLevel) -> Bool {
        clearingSessionCount(exercise, in: logs, level: level) > 0
    }

    /// How many of `logs` clear `exercise`'s rung - read by plateau diagnosis, which looks for a rung
    /// cleared again and again without the user moving up.
    static func clearingSessionCount(_ exercise: Exercise, in logs: [WorkoutLog], level: FitnessLevel) -> Int {
        logs.filter { log in
            log.exercises.contains { isAdvancementMet(by: $0, in: log, exercise: exercise, level: level) }
        }.count
    }
}
