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

    /// Where the user stands on each foundation line's active chain (free layer): Push, Pull, the
    /// Squat and Hinge sides of Legs, and Core - `StrengthFoundation.allLines`, in that order.
    let chainPositions: [ChainPositionSummary]

    /// The full per-line ladder (US-SP05, free layer): every rung from the entry tier up the line's
    /// chain, with the user's current frontier and any still-locked Strength rungs marked. Built *from* `chainPositions` (the frontier is the same one derived there), so the
    /// map's "you are here" can never disagree with the chain-position surface above it.
    let progressionMap: ProgressionMap

    /// Headline personal bests from real history (free layer).
    let personalBests: PersonalBests

    /// The deeper analytics layer, gated behind premium at the render boundary (US-N04).
    let deep: DeepAnalytics

    /// Builds the full analytics from the user's history and the exercise library.
    ///
    /// - Parameters:
    ///   - logs: the full `WorkoutLog` history (the Progress tab reads everything, not the engine's
    ///     bounded recent window, so all-time bests and every logged week are represented).
    ///   - library: the validated exercise catalog, needed to resolve chains, hold-vs-rep, and names.
    ///   - level: the user's self-reported fitness level, which with `phase` is everything
    ///     `MovementAccess` needs to say which tiers this user may get (ADR-0007).
    ///   - phase: the user's earned phase; chain position only counts tiers this user can reach, so
    ///     a Discipline user's chain is never reported against a still-locked tier (US-H02, ADR-0007).
    ///   - asOf: the vantage for week bucketing (weekly volume), injected for determinism.
    ///   - calendar: the calendar whose week boundaries match the Consistency Score's.
    static func from(
        logs: [WorkoutLog],
        library: [Exercise],
        level: FitnessLevel,
        phase: Phase,
        asOf: Date,
        calendar: Calendar = .current
    ) -> ProgressAnalytics {
        let exercisesById = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let worked = workedInstances(in: logs)
        let access = Access(level: level, phase: phase)
        let chainPositions = makeChainPositions(worked: worked, exercisesById: exercisesById, access: access)

        return ProgressAnalytics(
            pillarBalance: makePillarBalance(worked: worked),
            chainPositions: chainPositions,
            progressionMap: makeProgressionMap(chainPositions: chainPositions, exercisesById: exercisesById, access: access),
            personalBests: makePersonalBests(logs: logs, worked: worked, exercisesById: exercisesById, calendar: calendar),
            deep: DeepAnalytics(
                patternBalance: makePatternBalance(worked: worked),
                weeklyVolume: makeWeeklyVolume(logs: logs, worked: worked, asOf: asOf, calendar: calendar),
                difficultyMix: makeDifficultyMix(logs: logs),
                strengthJourney: makeStrengthJourney(
                    worked: worked,
                    exercisesById: exercisesById,
                    chainPositions: chainPositions,
                    access: access,
                    calendar: calendar
                )
            )
        )
    }

    // MARK: - Movement access

    /// The user's level and earned phase, bound once so every surface below asks `MovementAccess` -
    /// the engine's own rule - rather than re-deriving who gets which movement.
    private struct Access {
        let level: FitnessLevel
        let phase: Phase

        func allows(_ exercise: Exercise) -> Bool {
            MovementAccess.isAvailable(exercise, level: level, phase: phase)
        }
    }

    // MARK: - Worked instances

    /// One completed exercise within a session (`LoggedExercise.wasPerformed`): non-skipped and
    /// carrying at least one recorded set.
    /// This is the atom every count is built from, so a skipped or set-less movement never inflates
    /// balance, chain position, or a personal best.
    private struct WorkedInstance {
        let logged: LoggedExercise
        let completedAt: Date
    }

    private static func workedInstances(in logs: [WorkoutLog]) -> [WorkedInstance] {
        logs.flatMap { log in
            log.exercises
                .filter(\.wasPerformed)
                .map { WorkedInstance(logged: $0, completedAt: log.completedAt) }
        }
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

    /// For each foundation line, the user's standing in the chain they are *actively* working -
    /// the frontier tier (highest-order worked) within the most recently worked counting chain of that
    /// line. A line the user has never trained reports "not started" (`currentExercise == nil`).
    ///
    /// Everything is read through the user's `MovementAccess`. The reported tier/length/next-tier count
    /// only the tiers this user can actually get: a Discipline user never sees a Strength tier as "next
    /// tier in reach" (US-H02), and a beginner or intermediate user never sees a tier beyond their
    /// staples (ADR-0007). A frontier the user *worked* but no longer gets (a Cossack Squat for an
    /// intermediate, say) is reported as the closest rung they do get on the same chain
    /// (`MovementAccess.closestAvailableRung`), and a chain with no rung they get at all is never the
    /// active chain - the line falls back to another counting chain they worked, or "not started".
    private static func makeChainPositions(
        worked: [WorkedInstance],
        exercisesById: [String: Exercise],
        access: Access
    ) -> [ChainPositionSummary] {
        // Chain -> its tiers, for reachable-length and next-tier lookups.
        let tiersByChain = Dictionary(grouping: exercisesById.values) { $0.progressionChainId }

        return StrengthFoundation.allLines.map { line in
            // Only movements on the line's counting chains: Pull is its horizontal chain alone, so
            // postural pull work never becomes Pull's "current movement". Chains this user gets nothing
            // from are set aside.
            let inPattern = worked.compactMap { instance -> (WorkedInstance, Exercise)? in
                guard let exercise = exercisesById[instance.logged.exerciseId],
                      line.counts(exercise),
                      (tiersByChain[exercise.progressionChainId] ?? []).contains(where: access.allows) else { return nil }
                return (instance, exercise)
            }

            guard !inPattern.isEmpty else {
                return ChainPositionSummary(line: line, currentExercise: nil, tier: 0, chainLength: 0, hasNextTier: false)
            }

            // The active chain: the one containing the most recently worked movement in this pattern
            // (ties within a session break toward the higher tier, then the id, deterministically).
            let mostRecent = inPattern.max { lhs, rhs in
                if lhs.0.completedAt != rhs.0.completedAt { return lhs.0.completedAt < rhs.0.completedAt }
                if lhs.1.progressionOrder != rhs.1.progressionOrder { return lhs.1.progressionOrder < rhs.1.progressionOrder }
                return lhs.1.id > rhs.1.id
            }!
            let activeChainId = mostRecent.1.progressionChainId
            let chain = tiersByChain[activeChainId] ?? []

            // The frontier within that active chain: the highest-order worked tier, moved down to the
            // closest rung this user gets when the tier they worked is no longer theirs.
            let workedFrontier = inPattern
                .filter { $0.1.progressionChainId == activeChainId }
                .max { $0.1.progressionOrder < $1.1.progressionOrder }!
                .1
            let frontier = MovementAccess.closestAvailableRung(
                in: chain,
                atOrBelow: workedFrontier.progressionOrder,
                level: access.level,
                phase: access.phase
            ) ?? workedFrontier

            // Report against only the reachable tiers of the active chain, so a locked tier never
            // inflates the length or claims to be "in reach".
            let reachableTiers = chain.filter(access.allows)
            let chainLength = max(reachableTiers.count, 1)
            // Frontier's 1-based rank among the reachable tiers; `max(_, 1)` defends the case (which
            // shouldn't occur) where the frontier itself is not reachable, keeping tier valid.
            let tier = max(reachableTiers.filter { $0.progressionOrder <= frontier.progressionOrder }.count, 1)
            let hasNextTier = reachableTiers.contains { $0.progressionOrder > frontier.progressionOrder }

            return ChainPositionSummary(
                line: line,
                currentExercise: frontier,
                tier: tier,
                chainLength: chainLength,
                hasNextTier: hasNextTier
            )
        }
    }

    // MARK: - Progression map (free, US-SP05)

    /// The per-line ladder: for each foundation line, the full chain the user is climbing - entry
    /// tier up to its top rung - with the user's frontier and any locked Strength rungs marked.
    ///
    /// The ladder shown for a line is the **active chain** exactly as `makeChainPositions` already
    /// derived it (the chain containing the frontier `currentExercise`), so the "you are here" marker
    /// reuses that logic rather than re-deriving position from the logs. A line the user has never
    /// trained (`currentExercise == nil`) has no frontier to key off, so it defaults to the line's
    /// **canonical chain** for the preview, chosen among the counting chains this user gets at least one
    /// rung of and preferring one with a Strength-Phase summit. The choice is deterministic: the lowest
    /// chain id with such a summit, or the lowest chain id when none has one. Pull has one counting chain
    /// and no Strength-Phase summit, so its ladder is always the horizontal chain, whatever the user has
    /// trained.
    ///
    /// A rung is **locked** iff this user does not get it - a Strength-Phase skill they have not earned,
    /// or a movement beyond the staples for their level until the Strength Phase lifts that (ADR-0007) -
    /// read through the engine's own `MovementAccess` gate so the map cannot mark a rung locked (or free)
    /// in a way the engine would filter differently. The map carries no start/select affordance: it is a
    /// pure readout, and the view renders it without any tappable rung.
    private static func makeProgressionMap(
        chainPositions: [ChainPositionSummary],
        exercisesById: [String: Exercise],
        access: Access
    ) -> ProgressionMap {
        let tiersByChain = Dictionary(grouping: exercisesById.values) { $0.progressionChainId }
        let positionByPattern = Dictionary(chainPositions.map { ($0.pattern, $0) }, uniquingKeysWith: { first, _ in first })

        let ladders = StrengthFoundation.allLines.map { line -> PatternLadder in
            let position = positionByPattern[line.pattern]
            let frontier = position?.currentExercise

            // The chain to show: the active one (containing the frontier) when the user has trained
            // this line, else the line's canonical chain for a preview.
            let chainId = frontier?.progressionChainId
                ?? canonicalChainId(for: line, tiersByChain: tiersByChain, exercisesById: exercisesById, access: access)

            let members = chainId.flatMap { tiersByChain[$0] } ?? []
            // Entry tier first, up to the summit; id break keeps a stable order if two share an order.
            let ordered = members.sorted {
                if $0.progressionOrder != $1.progressionOrder { return $0.progressionOrder < $1.progressionOrder }
                return $0.id < $1.id
            }

            let rungs = ordered.map { exercise -> LadderRung in
                let state: LadderRung.State
                if let frontier {
                    if exercise.id == frontier.id { state = .current }
                    else if exercise.progressionOrder < frontier.progressionOrder { state = .cleared }
                    else { state = .ahead }
                } else {
                    // Never trained this pattern: nothing cleared, nothing current - the whole ladder
                    // lies ahead.
                    state = .ahead
                }
                return LadderRung(
                    exerciseId: exercise.id,
                    displayName: exercise.displayName,
                    difficulty: exercise.difficulty,
                    isStrengthSkill: exercise.phase == .strength,
                    isLocked: !access.allows(exercise),
                    state: state
                )
            }

            return PatternLadder(line: line, rungs: rungs, hasStarted: frontier != nil)
        }

        return ProgressionMap(ladders: ladders)
    }

    /// The line's canonical chain for a fresh-user preview: among the counting chains this user gets at
    /// least one rung of, the one carrying a Strength-Phase summit (deterministically the lowest such
    /// chain id), or the lowest of those chain ids when none has a strength summit. Only used when the
    /// user has no frontier on the line.
    private static func canonicalChainId(
        for line: FoundationLine,
        tiersByChain: [String: [Exercise]],
        exercisesById: [String: Exercise],
        access: Access
    ) -> String? {
        let chainIds = Set(exercisesById.values.filter { line.counts($0) && access.allows($0) }.map(\.progressionChainId))
        let withStrengthSummit = chainIds.filter { id in
            (tiersByChain[id] ?? []).contains { $0.phase == .strength }
        }
        return (withStrengthSummit.isEmpty ? chainIds : withStrengthSummit).min()
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

    // MARK: - Deep: strength journey (premium, US-AN01)

    /// The dated climb through each foundation line's active chain (US-AN01): per-line
    /// tier-advancement milestones read straight from the real `WorkoutLog` history, so the surface
    /// tells the "Knee Push-Up -> Standard Push-Up in 6 weeks" story anchored on actual dates rather
    /// than this week's numbers.
    ///
    /// The chain shown for a pattern is the **active** one exactly as `makeChainPositions` already
    /// derived it (the chain carrying the frontier `currentExercise`), reused rather than re-derived,
    /// so the journey can never disagree with the chain-position surface or the progression map. A
    /// milestone is a tier the user has **actually performed** in a real session (its `firstReachedAt`
    /// is the earliest `completedAt` across every worked instance of that tier); a tier never worked is
    /// simply absent, so nothing is fabricated.
    ///
    /// The journey's current position is that same frontier - the rung the user is served - and it is
    /// current only from the first time they worked it after their last work on any rung of the chain
    /// they first reached after it: the rungs beyond it in their own history, wherever those sit on the
    /// ladder now. A user moved to the closest rung they get (ADR-0007), or whose rungs were reordered,
    /// therefore has no current milestone until they work the served rung again, so time spent on a rung
    /// they moved on to is never read as time on it, while a session back on a rung reached earlier never
    /// interrupts a real stall. The rungs they worked stay in the timeline as genuine history. A
    /// Strength-Phase skill the user has not earned is never a milestone, even when it appears in their
    /// logs (`MovementAccess.isPhaseEarned`).
    /// A line the user has never trained (`currentExercise == nil`) contributes no journey, so an
    /// empty `chains` means no strength history yet. Pull's journey is its horizontal chain only.
    private static func makeStrengthJourney(
        worked: [WorkedInstance],
        exercisesById: [String: Exercise],
        chainPositions: [ChainPositionSummary],
        access: Access,
        calendar: Calendar
    ) -> StrengthJourney {
        let tiersByChain = Dictionary(grouping: exercisesById.values) { $0.progressionChainId }

        // Earliest logged completion per exercise id - the honest "first reached" date for a tier.
        var firstReachedById: [String: Date] = [:]
        for instance in worked {
            let id = instance.logged.exerciseId
            if let existing = firstReachedById[id] {
                if instance.completedAt < existing { firstReachedById[id] = instance.completedAt }
            } else {
                firstReachedById[id] = instance.completedAt
            }
        }

        let positionByPattern = Dictionary(chainPositions.map { ($0.pattern, $0) }, uniquingKeysWith: { first, _ in first })

        let chains: [ChainJourney] = StrengthFoundation.allLines.compactMap { line in
            // Only lines the user has actually trained have a frontier to anchor the journey on.
            guard let frontier = positionByPattern[line.pattern]?.currentExercise else { return nil }
            let activeChainId = frontier.progressionChainId

            // Every worked tier of the active chain, entry-first.
            let milestones: [TierMilestone] = (tiersByChain[activeChainId] ?? [])
                .filter { MovementAccess.isPhaseEarned($0, phase: access.phase) }
                .sorted {
                    if $0.progressionOrder != $1.progressionOrder { return $0.progressionOrder < $1.progressionOrder }
                    return $0.id < $1.id
                }
                .compactMap { exercise -> TierMilestone? in
                    guard let firstReachedAt = firstReachedById[exercise.id] else { return nil }
                    return TierMilestone(
                        exerciseId: exercise.id,
                        displayName: exercise.displayName,
                        tier: exercise.progressionOrder + 1,
                        firstReachedAt: firstReachedAt
                    )
                }

            // The active chain holds a worked tier, but when the only one is an unearned Strength skill
            // there is no climb to show.
            guard !milestones.isEmpty else { return nil }

            let currentSince = milestones.first { $0.exerciseId == frontier.id }.flatMap { served -> Date? in
                let reachedLaterIds = Set(milestones.filter { $0.firstReachedAt > served.firstReachedAt }.map(\.exerciseId))
                let lastLaterWork = worked.filter { reachedLaterIds.contains($0.logged.exerciseId) }.map(\.completedAt).max()
                return worked
                    .filter { instance in
                        instance.logged.exerciseId == served.exerciseId
                            && (lastLaterWork.map { instance.completedAt > $0 } ?? true)
                    }
                    .map(\.completedAt)
                    .min()
            }

            return ChainJourney(
                line: line,
                chainId: activeChainId,
                milestones: milestones,
                currentExerciseId: frontier.id,
                currentDisplayName: frontier.displayName,
                currentSince: currentSince,
                calendar: calendar
            )
        }

        return StrengthJourney(chains: chains)
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

/// The user's standing on a foundation line's active progression chain (US-M02).
struct ChainPositionSummary: Equatable, Identifiable {
    /// The foundation line (Push, Pull, Squat or Hinge side of Legs, Core).
    let line: FoundationLine
    /// The frontier movement the user is currently on, or `nil` when they have never trained this
    /// line ("not started yet").
    let currentExercise: Exercise?
    /// 1-based tier within the active chain (`progressionOrder + 1`); 0 when not started.
    let tier: Int
    /// Number of tiers in the active chain; 0 when not started.
    let chainLength: Int
    /// Whether a harder tier exists above the frontier - the "next up" the user is climbing toward.
    let hasNextTier: Bool

    var pattern: MovementPattern { line.pattern }

    var id: String { pattern.rawValue }

    /// Whether the user has trained this line at all.
    var hasStarted: Bool { currentExercise != nil }
}

/// The per-line progression map (US-SP05, free): one ladder per foundation line, in
/// `StrengthFoundation.allLines` order (Push / Pull / Squat / Hinge / Core).
struct ProgressionMap: Equatable {
    let ladders: [PatternLadder]
}

/// One foundation line's ladder - the chain the user is climbing, entry tier first through the top
/// rung last (a Strength-Phase skill on the lines that have one).
struct PatternLadder: Equatable, Identifiable {
    /// The foundation line (Push, Pull, Squat or Hinge side of Legs, Core).
    let line: FoundationLine
    /// The rungs, entry tier first. Empty only if the catalog somehow has no chain for the line.
    let rungs: [LadderRung]
    /// Whether the user has trained this line at all - drives "not started yet" framing without a
    /// current-position marker.
    let hasStarted: Bool

    var pattern: MovementPattern { line.pattern }

    var id: MovementPattern { pattern }

    /// The rung the user is currently on, if any.
    var currentRung: LadderRung? { rungs.first { $0.state == .current } }
}

/// A single movement on a ladder, with the user's standing on it and whether it is still locked
/// behind the Strength Phase. A pure readout - it carries no id the UI could use to *start* it, and
/// the view renders no tappable control on it (thesis preserved: the map never lets the user choose
/// or start a workout).
struct LadderRung: Equatable, Identifiable {
    /// The catalog id, for stable diffing and evidence only - never a selection handle.
    let exerciseId: String
    let displayName: String
    /// Difficulty band 1...5, for a subtle "gets harder as you climb" read.
    let difficulty: Int
    /// Whether this rung is a `phase == .strength` skill (locked or not - a strength user's summit is
    /// a strength skill that is no longer locked).
    let isStrengthSkill: Bool
    /// Locked iff this user does not get the movement - `!MovementAccess.isAvailable`, the engine's own
    /// gate (an unearned Strength-Phase skill, or a movement beyond their level's staples), so this can
    /// never disagree with what the engine would filter.
    let isLocked: Bool
    /// Where this rung sits relative to the user's frontier.
    let state: State

    var id: String { exerciseId }

    /// A rung's standing relative to the user's current frontier on the chain.
    enum State: Equatable {
        /// Below the frontier - a tier the user has already worked past.
        case cleared
        /// The user's current frontier - "you are here".
        case current
        /// Above the frontier - still to climb (may also be `isLocked`).
        case ahead
    }
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
    /// The dated strength journey (US-AN01): per-chain tier advancement from real history, anchored on
    /// progress over time rather than this week's numbers. Phase-earning progress (US-SP04's signals)
    /// is surfaced alongside it in the view from the view model's own `PhaseProgress`, so it is not
    /// recomputed here.
    let strengthJourney: StrengthJourney
}

/// The premium strength journey (US-AN01): one dated climb per foundation line the user has trained,
/// in `StrengthFoundation.allLines` order (Push, Pull, Squat, Hinge, Core). A line never trained is
/// omitted, so an empty `chains` means there is no strength history yet.
struct StrengthJourney: Equatable {
    let chains: [ChainJourney]

    /// Whether there is any journey to render at all.
    var isEmpty: Bool { chains.isEmpty }
}

/// One foundation line's dated climb through its active progression chain (US-AN01): the tiers
/// the user has actually reached, entry-first, each stamped with the date it was first performed, and
/// the rung they are served now. The span between the first and current milestone is the "in N weeks"
/// story; nothing is fabricated - a tier the user never worked is simply absent, and a still-locked
/// Strength tier is never a milestone.
struct ChainJourney: Equatable, Identifiable {
    /// The foundation line (Push, Pull, Squat or Hinge side of Legs, Core).
    let line: FoundationLine
    /// The active chain id (the chain carrying the frontier `ChainPositionSummary.currentExercise`).
    let chainId: String
    /// The reached tiers, entry-first. A rung the user no longer gets (ADR-0007) stays here as the
    /// history it is. Never empty - a pattern with no reached tier contributes no journey.
    let milestones: [TierMilestone]
    /// The rung the user is served on this chain now: the chain position's frontier
    /// (`ChainPositionSummary.currentExercise`), which they may not have worked yet.
    let currentExerciseId: String
    /// That rung's name, so the journey can say where the user is before they have worked it.
    let currentDisplayName: String
    /// When the user started on that rung: the first time they worked it after their last work on any
    /// rung of this chain they first reached after it, `nil` until they have.
    let currentSince: Date?

    /// The calendar the duration read-outs bucket weeks in, so a view renders the span the same way
    /// the analytics were derived rather than reaching for `Calendar.current`.
    private let calendar: Calendar

    init(
        line: FoundationLine,
        chainId: String,
        milestones: [TierMilestone],
        currentExerciseId: String,
        currentDisplayName: String,
        currentSince: Date?,
        calendar: Calendar
    ) {
        self.line = line
        self.chainId = chainId
        self.milestones = milestones
        self.currentExerciseId = currentExerciseId
        self.currentDisplayName = currentDisplayName
        self.currentSince = currentSince
        self.calendar = calendar
    }

    var pattern: MovementPattern { line.pattern }

    var id: MovementPattern { pattern }

    /// The entry tier the climb started from.
    var startMilestone: TierMilestone? { milestones.first }

    /// The rung the user is served now as a milestone dated `currentSince`, `nil` until they have worked
    /// it there - so a rung they were moved to is never reported as reached, and the time they spent on
    /// a rung they moved on to is never read as time on this one. Its row in `milestones` keeps the date
    /// they first reached it.
    var currentMilestone: TierMilestone? {
        guard let currentSince, let served = milestones.first(where: { $0.exerciseId == currentExerciseId }) else {
            return nil
        }
        return TierMilestone(
            exerciseId: served.exerciseId,
            displayName: served.displayName,
            tier: served.tier,
            firstReachedAt: currentSince
        )
    }

    /// Whether the user has climbed from their entry tier to the rung they are on now (a real "climb",
    /// not a single worked tier), which is what makes a from -> to advancement line meaningful.
    var hasAdvanced: Bool {
        guard let start = startMilestone, let current = currentMilestone else { return false }
        return start.exerciseId != current.exerciseId
    }

    /// Whole weeks between the first reached tier and the current frontier, `nil` until there is an
    /// advancement to measure. Bucketed in the analytics' own calendar so it matches every other
    /// time-relative surface.
    var weeksClimbed: Int? {
        guard let start = startMilestone, let current = currentMilestone, hasAdvanced else { return nil }
        let weeks = calendar.dateComponents([.weekOfYear], from: start.firstReachedAt, to: current.firstReachedAt).weekOfYear ?? 0
        return max(0, weeks)
    }

    // `calendar` is intentionally excluded from `Equatable`: two journeys with the same milestones are
    // equal regardless of the calendar instance they carry (calendars used here differ only by time
    // zone/first-weekday, which the milestone dates already encode).
    static func == (lhs: ChainJourney, rhs: ChainJourney) -> Bool {
        lhs.line == rhs.line && lhs.chainId == rhs.chainId && lhs.milestones == rhs.milestones
            && lhs.currentExerciseId == rhs.currentExerciseId && lhs.currentSince == rhs.currentSince
    }
}

/// A single reached tier on a chain journey (US-AN01): the movement, its 1-based place on the chain,
/// and the date it was first performed in a real logged session.
struct TierMilestone: Equatable, Identifiable {
    /// The catalog id, for stable diffing and evidence only.
    let exerciseId: String
    let displayName: String
    /// 1-based place on the active chain (`progressionOrder + 1`).
    let tier: Int
    /// The earliest `WorkoutLog.completedAt` at which this tier was performed - the honest date the
    /// user first reached it.
    let firstReachedAt: Date

    var id: String { exerciseId }
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
