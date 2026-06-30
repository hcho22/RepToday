import Foundation

/// Pipeline Step 5 of the deterministic engine (US-C05): within each pattern Step 3 chose, pick
/// the *exact exercise* in the progression chain that matches the user's demonstrated ability, so
/// the session is always appropriately challenging - never repeating an exercise the user has
/// outgrown, never skipping ahead past a tier they have not yet cleared.
///
/// Steps 1-4 chose the session's shape, pillar(s), lead pattern, and the safe eligible pool; Step
/// 5 walks the user up the chains inside a pattern:
/// - **Current position** - the user's frontier in a chain is the highest-order tier they have
///   actually worked (read back from `recentLogs`); a user with no history starts at the chain
///   entry (`progressionOrder` 0).
/// - **Advancement** - when the frontier tier's `advancementCriteria` are met in the logs, the
///   *next* tier is offered instead (and only the next - exactly one step, never a leap past an
///   un-cleared tier). Advancement is honored only when the next tier is itself in the eligible
///   pool, so a phase-gated or over-cap skill (e.g. the one-arm push-up) is never offered to a
///   user who cannot yet receive it.
/// - **Variety** - across the chains available for a pattern, an exercise used in the last 3
///   sessions is avoided when a fresher alternative exists, so the user is not handed the same
///   movement every time. Variety never wins over having an exercise at all: if every candidate
///   was used recently, the best ability-matched pick is still returned.
///
/// Like the earlier steps this is a pure function of its inputs - the full `library` (so chains
/// can be reasoned about end-to-end), the eligible `pool` from Step 4, and `recentLogs` - with no
/// hidden clock or library lookup, so it stays deterministic and unit-testable, mirroring
/// `PillarBalance`, `MovementPatternFocus`, and `ExercisePoolFilter`.

// MARK: - AdvancementCriteria

/// The structured form of an exercise's free-text `advancementCriteria` (e.g. `"3x15 clean reps"`,
/// `"3x30s hold"`, `"hold 45s per side"`, `"12 reps per side"`), so the engine can decide from the
/// logs whether the user has cleared a tier.
///
/// The criteria carry no machine-readable schema in the library, so this parses the two numbers
/// that matter: how many qualifying **sets** are required and the per-set **target** (reps for a
/// rep-based movement, seconds for a hold). A `"{sets}x{target}"` token is read when present
/// (`"3x15..."` -> 3 sets of 15); otherwise the first standalone number is the target for a single
/// set (`"hold 45s"` -> 1 set of 45). Whether the target counts reps or seconds is decided by the
/// exercise's `isHold` flag at comparison time, not by the text, so a trailing `s` in `"30s"` needs
/// no special handling.
///
/// - Note: This is a deliberately small parser for the controlled vocabulary the bundled library
///   uses today. It is forgiving (an unparseable string yields `nil`, treated as "never
///   advanceable" by callers) rather than strict, because the library's wording is content, not a
///   contract; a future structured criteria field would retire it.
struct AdvancementCriteria: Equatable {
    /// How many sets must meet `target` for the tier to be cleared (1 when the text has no
    /// `"{sets}x..."` prefix).
    let sets: Int
    /// The per-set threshold: reps for a rep-based movement, seconds of hold for a hold.
    let target: Int

    /// The structured form directly (the failable `init(parsing:)` suppresses the synthesized
    /// memberwise initializer).
    init(sets: Int, target: Int) {
        self.sets = sets
        self.target = target
    }

    /// Parses the two numbers that drive advancement, or `nil` when the text carries no number at
    /// all (so the tier can never be cleared from logs and the user simply stays on it).
    init?(parsing raw: String) {
        guard let parsed = Self.parse(raw) else { return nil }
        self.sets = parsed.sets
        self.target = parsed.target
    }

    /// Whether a single logged performance of the exercise clears this tier: at least `sets` of its
    /// `completedSets` reached `target` (reps for a rep-based movement, `durationSeconds` for a
    /// hold). A set missing the relevant value contributes 0 and simply does not count.
    func isMet(by logged: LoggedExercise, isHold: Bool) -> Bool {
        let qualifying = logged.completedSets.filter { set in
            let value = isHold ? (set.durationSeconds ?? 0) : (set.reps ?? 0)
            return value >= target
        }
        return qualifying.count >= sets
    }

    /// Scans for a `"{sets}x{target}"` token (preferred, even when a standalone number appears
    /// first), falling back to the first standalone number as a single-set target. Returns `nil`
    /// when the text has no digits.
    private static func parse(_ raw: String) -> (sets: Int, target: Int)? {
        let chars = Array(raw.lowercased())
        var firstStandalone: Int?
        var index = 0
        while index < chars.count {
            guard chars[index].isNumber else {
                index += 1
                continue
            }
            // Read the digit run starting here.
            var end = index
            while end < chars.count, chars[end].isNumber { end += 1 }
            let first = Int(String(chars[index..<end]))!

            // A "{first} x {second}" token wins outright, wherever it sits in the string.
            var cursor = end
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            if cursor < chars.count, chars[cursor] == "x" {
                cursor += 1
                while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
                if cursor < chars.count, chars[cursor].isNumber {
                    var secondEnd = cursor
                    while secondEnd < chars.count, chars[secondEnd].isNumber { secondEnd += 1 }
                    let second = Int(String(chars[cursor..<secondEnd]))!
                    return (sets: first, target: second)
                }
            }

            // Otherwise remember the first standalone number and keep scanning for an "NxM".
            if firstStandalone == nil { firstStandalone = first }
            index = end
        }
        return firstStandalone.map { (sets: 1, target: $0) }
    }
}

// MARK: - ChainSelection

/// The outcome of resolving one chain (or one pattern) to a single exercise: the chosen movement,
/// which chain it belongs to, its tier, and whether the user advanced a tier this session.
struct ChainSelection: Equatable {
    /// The exercise to prescribe for this chain/pattern.
    let exercise: Exercise
    /// The chain the exercise belongs to (`progressionChainId`).
    let chainId: String
    /// The chosen exercise's `progressionOrder` within its chain.
    let order: Int
    /// `true` when the user cleared their frontier tier's criteria and was moved one step up the
    /// chain this session; `false` when they stayed on (or started at) their current tier.
    let didAdvance: Bool
}

// MARK: - ProgressionChainSelection

/// Selects the right progression-chain exercise for a pattern (pipeline Step 5).
enum ProgressionChainSelection {

    /// How many of the most recent sessions count toward the variety rule: an exercise worked in
    /// any of the last `recentSessionWindow` sessions is avoided when a fresher candidate exists.
    /// Tunable.
    static let recentSessionWindow = 3

    // MARK: Per-chain selection

    /// Resolves a single chain to the exercise that matches the user's ability.
    ///
    /// `chain` is the full set of tiers for one progression chain (any order); `eligibleIds` are
    /// the ids Step 4 left prescribable, so reasoning happens over the whole chain but only an
    /// eligible tier is ever returned. Returns `nil` only when the chain has no eligible tier at
    /// all (the caller then drops the chain).
    ///
    /// - The user's **frontier** is the highest-order tier they have worked (non-skipped) in
    ///   `recentLogs`. With no worked tier, selection starts at the lowest eligible tier (the
    ///   entry, `progressionOrder` 0 for a full chain).
    /// - When the frontier tier's `advancementCriteria` are met in the logs and its next tier
    ///   exists, the desired tier is that next tier; otherwise it is the frontier itself.
    /// - The desired tier is then clamped to what is eligible: the highest eligible tier no higher
    ///   than desired (so a gated/over-cap next tier collapses back to the frontier rather than
    ///   leaking through), or the lowest eligible tier if none sits at or below.
    static func selectInChain(
        _ chain: [Exercise],
        eligibleIds: Set<String>,
        recentLogs: [WorkoutLog]
    ) -> ChainSelection? {
        let sorted = chain.sorted { $0.progressionOrder < $1.progressionOrder }
        let eligible = sorted.filter { eligibleIds.contains($0.id) }
        guard let lowestEligible = eligible.first else { return nil }

        guard let frontier = frontierTier(in: sorted, recentLogs: recentLogs) else {
            // No history in this chain: start at the entry (lowest eligible tier).
            return ChainSelection(
                exercise: lowestEligible,
                chainId: lowestEligible.progressionChainId,
                order: lowestEligible.progressionOrder,
                didAdvance: false
            )
        }

        let desiredOrder = advancedOrder(from: frontier, in: sorted, recentLogs: recentLogs)
        // Clamp the desired tier to the eligible set: greatest eligible order <= desired, else the
        // lowest eligible tier. Both are guaranteed to exist (eligible is non-empty).
        let chosen = eligible.last { $0.progressionOrder <= desiredOrder } ?? lowestEligible
        return ChainSelection(
            exercise: chosen,
            chainId: chosen.progressionChainId,
            order: chosen.progressionOrder,
            didAdvance: chosen.progressionOrder > frontier.progressionOrder
        )
    }

    // MARK: Per-pattern selection

    /// Selects the single exercise to prescribe for `pattern`, integrating every chain available
    /// for it and the last-3-sessions variety rule.
    ///
    /// `library` is the full catalog (so each chain is reasoned about end-to-end); `pool` is the
    /// eligible pool from Step 4 (so only safe, level-appropriate tiers are prescribable). Each
    /// chain present for the pattern is resolved by `selectInChain`; among the resulting
    /// candidates a fresh one (not used in the last `recentSessionWindow` sessions) is preferred,
    /// and ties break toward the chain the user is actively progressing, then the gentler option,
    /// deterministically. Returns `nil` when the pattern has no eligible tier in any chain.
    static func select(
        pattern: MovementPattern,
        library: [Exercise],
        pool: [Exercise],
        recentLogs: [WorkoutLog]
    ) -> ChainSelection? {
        let eligibleIds = Set(pool.map(\.id))
        let chains = Dictionary(
            grouping: library.filter { $0.movementPattern == pattern },
            by: \.progressionChainId
        )

        let candidates = chains
            .sorted { $0.key < $1.key } // stable starting order before the real ordering below
            .compactMap { _, members in
                selectInChain(members, eligibleIds: eligibleIds, recentLogs: recentLogs)
            }
        guard !candidates.isEmpty else { return nil }

        let recentlyUsed = recentlyUsedExerciseIds(recentLogs: recentLogs)
        let lastWorked = lastWorkedByChain(recentLogs: recentLogs, library: library)

        // Prefer candidates whose chosen exercise was not used in the last few sessions; fall back
        // to the full set if that leaves nothing (variety never beats having an exercise).
        let fresh = candidates.filter { !recentlyUsed.contains($0.exercise.id) }
        let pickFrom = fresh.isEmpty ? candidates : fresh

        return pickFrom.min { lhs, rhs in
            // The chain the user worked most recently wins (keep them on their active chain).
            let lhsWorked = lastWorked[lhs.chainId]
            let rhsWorked = lastWorked[rhs.chainId]
            if lhsWorked != rhsWorked { return isMoreRecent(lhsWorked, than: rhsWorked) }
            // Then the gentler option: lower difficulty, then lower tier, then id for determinism.
            if lhs.exercise.difficulty != rhs.exercise.difficulty {
                return lhs.exercise.difficulty < rhs.exercise.difficulty
            }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.exercise.id < rhs.exercise.id
        }
    }

    // MARK: Helpers

    /// The user's frontier in a chain: the highest-order tier worked (non-skipped) in `recentLogs`,
    /// or `nil` when the chain has no worked tier.
    private static func frontierTier(
        in sorted: [Exercise],
        recentLogs: [WorkoutLog]
    ) -> Exercise? {
        let workedIds = workedExerciseIds(recentLogs: recentLogs)
        return sorted.last { workedIds.contains($0.id) }
    }

    /// The tier the user should be offered from `frontier`: the next tier when the frontier's
    /// criteria are met in the logs and a next tier exists, otherwise the frontier's own order.
    private static func advancedOrder(
        from frontier: Exercise,
        in sorted: [Exercise],
        recentLogs: [WorkoutLog]
    ) -> Int {
        guard
            criteriaMet(for: frontier, recentLogs: recentLogs),
            let nextId = frontier.progressionId,
            let next = sorted.first(where: { $0.id == nextId })
        else {
            return frontier.progressionOrder
        }
        return next.progressionOrder
    }

    /// Whether the user has cleared `exercise`'s advancement criteria in any single past
    /// performance. Unparseable criteria are never "met", so the user stays on the tier.
    private static func criteriaMet(for exercise: Exercise, recentLogs: [WorkoutLog]) -> Bool {
        guard let criteria = AdvancementCriteria(parsing: exercise.advancementCriteria) else {
            return false
        }
        return recentLogs.contains { log in
            log.exercises.contains { logged in
                logged.exerciseId == exercise.id
                    && !logged.skipped
                    && criteria.isMet(by: logged, isHold: exercise.isHold)
            }
        }
    }

    /// Ids of every exercise worked (non-skipped) anywhere in `recentLogs`.
    private static func workedExerciseIds(recentLogs: [WorkoutLog]) -> Set<String> {
        recentLogs.reduce(into: Set<String>()) { ids, log in
            for logged in log.exercises where !logged.skipped {
                ids.insert(logged.exerciseId)
            }
        }
    }

    /// Ids worked (non-skipped) in the most recent `recentSessionWindow` sessions, used to avoid
    /// repeating an exercise for variety. The window is by distinct session recency, not by how
    /// many logs the caller happened to pass.
    private static func recentlyUsedExerciseIds(recentLogs: [WorkoutLog]) -> Set<String> {
        let recentSessions = recentLogs
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(recentSessionWindow)
        return recentSessions.reduce(into: Set<String>()) { ids, log in
            for logged in log.exercises where !logged.skipped {
                ids.insert(logged.exerciseId)
            }
        }
    }

    /// The most recent date each chain was worked (non-skipped), so per-pattern selection can keep
    /// the user on the chain they are actively progressing. A chain absent from the result was
    /// never worked.
    private static func lastWorkedByChain(
        recentLogs: [WorkoutLog],
        library: [Exercise]
    ) -> [String: Date] {
        let chainByExerciseId = Dictionary(
            uniqueKeysWithValues: library.map { ($0.id, $0.progressionChainId) }
        )
        var lastWorked: [String: Date] = [:]
        for log in recentLogs {
            for logged in log.exercises where !logged.skipped {
                guard let chainId = chainByExerciseId[logged.exerciseId] else { continue }
                if let existing = lastWorked[chainId], existing >= log.completedAt { continue }
                lastWorked[chainId] = log.completedAt
            }
        }
        return lastWorked
    }

    /// Whether chain activity `a` is more recent than `b`, treating "never worked" (`nil`) as the
    /// least recent of all, so an actively-worked chain outranks an untouched one.
    private static func isMoreRecent(_ a: Date?, than b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (lhs?, rhs?): return lhs > rhs
        }
    }
}
