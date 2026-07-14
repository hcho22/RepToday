import Foundation

/// The Progress tab's legibility layer (US-M02): pillar balance, progression-chain position, and
/// personal bests derived from the real `WorkoutLog` history, plus a deeper analytics layer gated
/// behind premium.
///
/// Like `ConsistencyScore`/`ConsistencyTrend` this is a pure, deterministic function of its inputs
/// (`asOf` injected, never a wall-clock read), so every surface is unit-testable and the same logs
/// always produce the same analytics. Coverage is counted the way `SessionSummary` counts it - only
/// non-skipped exercises with a recorded set - so the tab can never over-claim a movement the user
/// passed on.
///
/// The whole struct is computed regardless of entitlement; the *view* renders the free layers
/// (`pillarBalance`/`chainPositions`/`personalBests`) for everyone and gates only `deep` behind
/// premium (US-N04), so the split lives at the render boundary and the analytics stay simple and
/// fully testable.
struct ProgressAnalytics: Equatable {

    /// Share of training across the three pillars (free layer).
    let pillarBalance: [PillarShare]

    /// Where the user stands in each foundational movement pattern's active chain (free layer).
    let chainPositions: [ChainPositionSummary]

    /// Headline personal bests from real history (free layer).
    let personalBests: PersonalBests

    /// The deeper analytics layer, gated behind premium at the render boundary (US-N04).
    let deep: DeepAnalytics

    /// The foundational patterns whose chain position the free layer surfaces, in display order.
    /// These mirror the four patterns the `PhaseEvaluator` gates competence on (US-H02).
    static let foundationalPatterns: [MovementPattern] = [.push, .squat, .hinge, .core]

    /// Builds the full analytics from the user's history and the exercise library.
    ///
    /// - Parameters:
    ///   - logs: the full `WorkoutLog` history (the Progress tab reads everything, not the engine's
    ///     bounded recent window, so all-time bests and every logged week are represented).
    ///   - library: the validated exercise catalog, needed to resolve chains, hold-vs-rep, and names.
    ///   - phase: the user's earned phase; chain position only counts tiers this phase can reach, so
    ///     a Discipline user's chain is never reported against a still-locked Strength tier (US-H02).
    ///   - asOf: the vantage for week bucketing (weekly volume), injected for determinism.
    ///   - calendar: the calendar whose week boundaries match the Consistency Score's.
    static func from(
        logs: [WorkoutLog],
        library: [Exercise],
        phase: Phase,
        asOf: Date,
        calendar: Calendar = .current
    ) -> ProgressAnalytics {
        let exercisesById = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let worked = workedInstances(in: logs)

        return ProgressAnalytics(
            pillarBalance: makePillarBalance(worked: worked),
            chainPositions: makeChainPositions(worked: worked, exercisesById: exercisesById, phase: phase),
            personalBests: makePersonalBests(logs: logs, worked: worked, exercisesById: exercisesById, calendar: calendar),
            deep: DeepAnalytics(
                patternBalance: makePatternBalance(worked: worked),
                weeklyVolume: makeWeeklyVolume(logs: logs, worked: worked, asOf: asOf, calendar: calendar),
                difficultyMix: makeDifficultyMix(logs: logs)
            )
        )
    }

    // MARK: - Worked instances

    /// One completed exercise within a session: non-skipped and carrying at least one recorded set.
    /// This is the atom every count is built from, so a skipped or set-less movement never inflates
    /// balance, chain position, or a personal best.
    private struct WorkedInstance {
        let logged: LoggedExercise
        let completedAt: Date
    }

    private static func workedInstances(in logs: [WorkoutLog]) -> [WorkedInstance] {
        logs.flatMap { log in
            log.exercises
                .filter { !$0.skipped && hasRecordedSet($0) }
                .map { WorkedInstance(logged: $0, completedAt: log.completedAt) }
        }
    }

    private static func hasRecordedSet(_ logged: LoggedExercise) -> Bool {
        logged.completedSets.contains { ($0.reps ?? 0) > 0 || ($0.durationSeconds ?? 0) > 0 }
    }

    // MARK: - Pillar balance (free)

    private static func makePillarBalance(worked: [WorkedInstance]) -> [PillarShare] {
        let total = worked.count
        let counts = worked.reduce(into: [Pillar: Int]()) { $0[$1.logged.pillar, default: 0] += 1 }
        return Pillar.allCases.map { pillar in
            let count = counts[pillar] ?? 0
            return PillarShare(
                pillar: pillar,
                exerciseCount: count,
                fraction: total > 0 ? Double(count) / Double(total) : 0
            )
        }
    }

    // MARK: - Chain position (free)

    /// For each foundational pattern, the user's standing in the chain they are *actively* working -
    /// the frontier tier (highest-order worked) within the most recently worked chain for that
    /// pattern. A pattern the user has never trained reports "not started" (`currentExercise == nil`).
    ///
    /// The reported tier/length/next-tier are counted only over the tiers this `phase` can actually
    /// reach: a Discipline user (all MVP users) reaches only `.discipline` tiers, so a chain that tops
    /// out in a still-locked Strength movement (push_one_arm, pistol, the L-sit) is never reported as
    /// "next tier in reach" and its length never counts the unreachable tier, mirroring the
    /// `PhaseEvaluator` principle that Strength movements never surface until earned (US-H02).
    private static func makeChainPositions(
        worked: [WorkedInstance],
        exercisesById: [String: Exercise],
        phase: Phase
    ) -> [ChainPositionSummary] {
        // Chain -> its tiers, for reachable-length and next-tier lookups.
        let tiersByChain = Dictionary(grouping: exercisesById.values) { $0.progressionChainId }

        func isReachable(_ exercise: Exercise) -> Bool {
            exercise.phase == .discipline || phase == .strength
        }

        return foundationalPatterns.map { pattern in
            let inPattern = worked.compactMap { instance -> (WorkedInstance, Exercise)? in
                guard let exercise = exercisesById[instance.logged.exerciseId],
                      exercise.movementPattern == pattern else { return nil }
                return (instance, exercise)
            }

            guard !inPattern.isEmpty else {
                return ChainPositionSummary(pattern: pattern, currentExercise: nil, tier: 0, chainLength: 0, hasNextTier: false)
            }

            // The active chain: the one containing the most recently worked movement in this pattern
            // (ties within a session break toward the higher tier, then the id, deterministically).
            let mostRecent = inPattern.max { lhs, rhs in
                if lhs.0.completedAt != rhs.0.completedAt { return lhs.0.completedAt < rhs.0.completedAt }
                if lhs.1.progressionOrder != rhs.1.progressionOrder { return lhs.1.progressionOrder < rhs.1.progressionOrder }
                return lhs.1.id > rhs.1.id
            }!
            let activeChainId = mostRecent.1.progressionChainId

            // The frontier within that active chain: the highest-order worked tier.
            let frontier = inPattern
                .filter { $0.1.progressionChainId == activeChainId }
                .max { $0.1.progressionOrder < $1.1.progressionOrder }!
                .1

            // Report against only the reachable tiers of the active chain, so a locked Strength tier
            // never inflates the length or claims to be "in reach".
            let reachableTiers = (tiersByChain[activeChainId] ?? []).filter(isReachable)
            let chainLength = max(reachableTiers.count, 1)
            // Frontier's 1-based rank among the reachable tiers; `max(_, 1)` defends the case (which
            // shouldn't occur) where the frontier itself is not reachable, keeping tier valid.
            let tier = max(reachableTiers.filter { $0.progressionOrder <= frontier.progressionOrder }.count, 1)
            let hasNextTier = reachableTiers.contains { $0.progressionOrder > frontier.progressionOrder }

            return ChainPositionSummary(
                pattern: pattern,
                currentExercise: frontier,
                tier: tier,
                chainLength: chainLength,
                hasNextTier: hasNextTier
            )
        }
    }

    // MARK: - Personal bests (free)

    private static func makePersonalBests(
        logs: [WorkoutLog],
        worked: [WorkedInstance],
        exercisesById: [String: Exercise],
        calendar: Calendar
    ) -> PersonalBests {
        let sessionsByWeek = logs.reduce(into: [Date: Int]()) { counts, log in
            counts[ConsistencyScore.startOfWeek(log.completedAt, calendar), default: 0] += 1
        }

        var bestReps: ExerciseBest?
        var bestHold: ExerciseBest?
        for instance in worked {
            guard let exercise = exercisesById[instance.logged.exerciseId] else { continue }
            for set in instance.logged.completedSets {
                if exercise.isHold {
                    if let seconds = set.durationSeconds, seconds > 0 {
                        bestHold = better(bestHold, than: seconds, exercise: exercise)
                    }
                } else if let reps = set.reps, reps > 0 {
                    bestReps = better(bestReps, than: reps, exercise: exercise)
                }
            }
        }

        return PersonalBests(
            totalSessions: logs.count,
            totalMinutesMoved: logs.reduce(0) { $0 + $1.durationMinutes },
            longestSessionMinutes: logs.map(\.durationMinutes).max() ?? 0,
            mostSessionsInAWeek: sessionsByWeek.values.max() ?? 0,
            bestReps: bestReps,
            bestHold: bestHold
        )
    }

    /// Keeps the larger value; on a tie prefers the lexicographically smaller id so the winner is
    /// deterministic regardless of log ordering.
    private static func better(_ current: ExerciseBest?, than value: Int, exercise: Exercise) -> ExerciseBest {
        let candidate = ExerciseBest(exerciseId: exercise.id, displayName: exercise.displayName, value: value)
        guard let current else { return candidate }
        if value > current.value { return candidate }
        if value == current.value, candidate.exerciseId < current.exerciseId { return candidate }
        return current
    }

    // MARK: - Deep: pattern balance (premium)

    private static func makePatternBalance(worked: [WorkedInstance]) -> [PatternShare] {
        let total = worked.count
        let counts = worked.reduce(into: [MovementPattern: Int]()) { $0[$1.logged.movementPattern, default: 0] += 1 }
        return MovementPattern.allCases.compactMap { pattern in
            let count = counts[pattern] ?? 0
            guard count > 0 else { return nil }
            return PatternShare(
                pattern: pattern,
                exerciseCount: count,
                fraction: total > 0 ? Double(count) / Double(total) : 0
            )
        }
    }

    // MARK: - Deep: weekly volume (premium)

    /// Completed sets and sessions per week over the same rolling window the Consistency Score
    /// averages, oldest week first. Weeks with no activity inside the span are kept (a real bar
    /// chart has gaps), so the trajectory reads honestly.
    private static func makeWeeklyVolume(
        logs: [WorkoutLog],
        worked: [WorkedInstance],
        asOf: Date,
        calendar: Calendar
    ) -> [WeeklyVolumePoint] {
        guard !logs.isEmpty else { return [] }

        let oldestWeeksAgo = logs
            .map { ConsistencyScore.weeksAgo($0.completedAt, from: asOf, calendar) }
            .filter { $0 >= 0 }
            .max() ?? 0
        let span = min(oldestWeeksAgo, ConsistencyScore.recentWeeksWindow - 1)

        var setsByWeek: [Int: Int] = [:]
        for instance in worked {
            let weeksAgo = ConsistencyScore.weeksAgo(instance.completedAt, from: asOf, calendar)
            guard weeksAgo >= 0 else { continue }
            setsByWeek[weeksAgo, default: 0] += instance.logged.completedSets.filter { ($0.reps ?? 0) > 0 || ($0.durationSeconds ?? 0) > 0 }.count
        }
        var sessionsByWeek: [Int: Int] = [:]
        for log in logs {
            let weeksAgo = ConsistencyScore.weeksAgo(log.completedAt, from: asOf, calendar)
            guard weeksAgo >= 0 else { continue }
            sessionsByWeek[weeksAgo, default: 0] += 1
        }

        return stride(from: span, through: 0, by: -1).map { weeksAgo in
            let vantage = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: asOf) ?? asOf
            return WeeklyVolumePoint(
                weekStart: ConsistencyScore.startOfWeek(vantage, calendar),
                setsCompleted: setsByWeek[weeksAgo] ?? 0,
                sessionCount: sessionsByWeek[weeksAgo] ?? 0
            )
        }
    }

    // MARK: - Deep: difficulty mix (premium)

    private static func makeDifficultyMix(logs: [WorkoutLog]) -> DifficultyMix {
        var counts: [PerceivedDifficulty: Int] = [:]
        for log in logs {
            guard let rating = log.perceivedDifficulty else { continue }
            counts[rating, default: 0] += 1
        }
        return DifficultyMix(
            tooEasy: counts[.tooEasy] ?? 0,
            justRight: counts[.justRight] ?? 0,
            tooHard: counts[.tooHard] ?? 0
        )
    }
}

// MARK: - Free-layer surfaces

/// One pillar's share of the user's training (US-M02). `fraction` is over the count of completed
/// exercises across all pillars, so the three shares sum to 1 once there is any history.
struct PillarShare: Equatable, Identifiable {
    let pillar: Pillar
    let exerciseCount: Int
    let fraction: Double

    var id: String { pillar.rawValue }
}

/// The user's standing in a foundational pattern's active progression chain (US-M02).
struct ChainPositionSummary: Equatable, Identifiable {
    /// The foundational pattern (push/squat/hinge/core).
    let pattern: MovementPattern
    /// The frontier movement the user is currently on, or `nil` when they have never trained this
    /// pattern ("not started yet").
    let currentExercise: Exercise?
    /// 1-based tier within the active chain (`progressionOrder + 1`); 0 when not started.
    let tier: Int
    /// Number of tiers in the active chain; 0 when not started.
    let chainLength: Int
    /// Whether a harder tier exists above the frontier - the "next up" the user is climbing toward.
    let hasNextTier: Bool

    var id: String { pattern.rawValue }

    /// Whether the user has trained this pattern at all.
    var hasStarted: Bool { currentExercise != nil }
}

/// A single-value best naming the movement it was set on.
struct ExerciseBest: Equatable {
    let exerciseId: String
    let displayName: String
    /// Reps for a rep-based movement, seconds for a hold.
    let value: Int
}

/// Headline personal bests from real history (US-M02).
struct PersonalBests: Equatable {
    let totalSessions: Int
    let totalMinutesMoved: Int
    let longestSessionMinutes: Int
    let mostSessionsInAWeek: Int
    /// Best single-set reps across every rep-based movement, or `nil` with no rep history.
    let bestReps: ExerciseBest?
    /// Longest single-set hold across every hold, or `nil` with no hold history.
    let bestHold: ExerciseBest?
}

// MARK: - Premium (deep) surfaces

/// The deeper analytics layer gated behind premium (US-M02 / US-N04).
struct DeepAnalytics: Equatable {
    /// Finer than pillar balance: the share across all seven movement patterns the user has trained.
    let patternBalance: [PatternShare]
    /// Completed sets and sessions per week over the rolling window, oldest first.
    let weeklyVolume: [WeeklyVolumePoint]
    /// How sessions have felt - the calibration signal behind Adaptive Overload.
    let difficultyMix: DifficultyMix
}

/// One movement pattern's share of training (premium; finer than `PillarShare`). Patterns with no
/// history are omitted.
struct PatternShare: Equatable, Identifiable {
    let pattern: MovementPattern
    let exerciseCount: Int
    let fraction: Double

    var id: String { pattern.rawValue }
}

/// Completed volume for one week (premium).
struct WeeklyVolumePoint: Equatable, Identifiable {
    let weekStart: Date
    let setsCompleted: Int
    let sessionCount: Int

    var id: Date { weekStart }
}

/// The distribution of post-session difficulty ratings (premium).
struct DifficultyMix: Equatable {
    let tooEasy: Int
    let justRight: Int
    let tooHard: Int

    /// Total rated sessions; 0 when nothing has been rated yet.
    var ratedCount: Int { tooEasy + justRight + tooHard }
}
