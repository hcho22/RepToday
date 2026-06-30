import Foundation

/// Pipeline Step 7 of the deterministic engine (US-C07): take everything Steps 1-6 decided and
/// assemble a complete, playable `Workout` that opens with a warm-up, closes with a cooldown when
/// it runs long, and lands within ±1 minute of the minutes the user asked for.
///
/// This is the step that turns the pipeline's per-decision outputs into the structured session the
/// active-session player renders:
/// - **Shape** (Step 1, `SessionShapeTemplate`) decides single-focus vs. blend.
/// - **Pillars** (Step 2, `PillarPlan`) decide which pillar a single-focus trains, or - for a blend -
///   which pillar leads and which is the smaller second block.
/// - **Pattern, exercise, and target** (Steps 3-6, `PatternFocus` / `ProgressionChainSelection` /
///   `AdaptiveOverload`) fill each training block: the stalest patterns first, the ability-matched
///   exercise in each, and that exercise's capacity-relative reps/sets/hold.
///
/// On top of those it owns two things the earlier steps deliberately left to assembly:
/// - **Structure** - every session opens with a `.warmup` block (mobility); a `.cooldown` block of
///   static stretches closes any session longer than `cooldownThresholdMinutes`. In a short
///   mobility-led session the opening warm-up and the Movement Practice block are both mobility, so
///   the opening flow doubles as warm-up + training, exactly as the PRD describes.
/// - **Timing fit** - the planned wall-clock is `Σ(sets × estTimePerSet) + rests + transitions`; a
///   deterministic best-fit pass trims or extends the session (adding/removing whole exercises or
///   individual sets, never touching the capacity-relative *per-set* target from Step 6) until it
///   lands within `toleranceSeconds` of the request.
///
/// Identity and the reference clock enter here (the earlier steps are clock-free and id-free): the
/// `Workout`/`WorkoutBlock`/`PrescribedExercise` ids are fresh `UUID`s and `createdAt`/staleness are
/// measured against the caller-supplied `asOf`. The *content* of the assembled session (which
/// exercises, in which order, at what sets/reps) is a pure, deterministic function of the inputs;
/// only the ids vary run to run, so tests assert structure and timing rather than whole-`Workout`
/// equality.
enum SessionAssembly {

    // MARK: - Tuning constants

    /// Seconds of transition between two consecutive exercises (move to the next spot, reset). Counted
    /// once per gap across the whole session, matching `Σ ... + transitions`.
    static let transitionSeconds = 15
    /// Rest between sets of a strength/primal movement.
    static let strengthRestSeconds = 40
    /// Rest between sets of a mobility movement (a stretch needs little reset).
    static let mobilityRestSeconds = 15
    /// The ±window the assembled session must land within around the requested time (1 minute).
    static let toleranceSeconds = 60

    /// Set-count rails the timing-fit pass may move a *training* block's exercises between. The
    /// per-set target (reps/seconds) from Step 6 is never touched; only how many sets are done is a
    /// timing lever, and only within these rails so a fit never produces an absurd set count.
    static let minTrainingSets = 1
    static let maxTrainingSets = 4

    /// Caps on how many distinct movements each mobility-sourced block may draw, so the 12-movement
    /// mobility pool is shared across warm-up, an optional Movement Practice block, and the cooldown
    /// without one block starving the others.
    static let maxWarmupExercises = 3
    static let maxMobilityTrainingExercises = 8
    static let maxCooldownExercises = 4

    /// Sessions longer than this many minutes close with a cooldown stretch (so 15/20/30 get one,
    /// 5/10 do not).
    static let cooldownThresholdMinutes = 10

    /// Hard backstop on the timing-fit loop; each accepted step strictly shrinks the timing error, so
    /// the loop converges well within this in practice.
    static let maxFitIterations = 200

    // MARK: - Entry point

    /// Assembles the complete session for `requestedMinutes` (pipeline Step 7).
    ///
    /// Runs the full pipeline over `library`, `user`, and `recentLogs`, structures the result into
    /// warm-up / training / cooldown blocks per the Step 1 shape, and timing-fits it to within
    /// `toleranceSeconds` of the request. `asOf` is the reference "now" (used for `createdAt` and all
    /// staleness math) so the function stays a pure function of its inputs.
    static func assemble(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar = .current
    ) -> Workout {
        let template = SessionShapeTemplate.select(requestedMinutes: requestedMinutes)
        let pillarPlan = PillarPlan.select(
            template: template,
            recentLogs: recentLogs,
            profile: user.profile,
            asOf: asOf,
            calendar: calendar
        )
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs)

        var builder = Builder(
            library: library,
            pool: pool,
            recentLogs: recentLogs,
            asOf: asOf,
            calendar: calendar
        )
        var blocks = builder.buildBlocks(pillarPlan: pillarPlan, requestedMinutes: requestedMinutes)
        fit(&blocks, targetSeconds: requestedMinutes * 60)

        let focusPillar: Pillar?
        switch pillarPlan {
        case .single(let pillar): focusPillar = pillar
        case .blend: focusPillar = nil
        }

        return Workout(
            id: UUID(),
            createdAt: asOf,
            shape: template.shape,
            focusPillar: focusPillar,
            requestedMinutes: requestedMinutes,
            blocks: blocks.compactMap { $0.materialize() }
        )
    }

    // MARK: - Planned wall-clock

    /// The planned wall-clock of an assembled `Workout`: `Σ(sets × estTimePerSet) + rests +
    /// transitions`. The same formula the timing-fit pass minimizes against, exposed so callers and
    /// tests measure the session exactly as the engine sized it.
    static func plannedSeconds(of workout: Workout) -> Int {
        let items = workout.blocks.flatMap(\.exercises)
        let work = items.reduce(0) { sum, item in
            sum + item.sets * item.exercise.estimatedTimePerSetSeconds
                + max(0, item.sets - 1) * item.restSeconds
        }
        return work + max(0, items.count - 1) * transitionSeconds
    }

    // MARK: - Timing fit

    /// Trims or extends `blocks` until the planned wall-clock is as close to `targetSeconds` as the
    /// available adjustments allow (comfortably inside `toleranceSeconds` in practice, not merely at
    /// its edge).
    ///
    /// A deterministic best-fit loop: each pass measures the signed error, then - adding when short,
    /// removing when long - picks the single adjustment (extra/fewer set, extra/dropped exercise) that
    /// brings the planned time closest to target, applying it only if it strictly reduces the absolute
    /// error. The loop runs to the local minimum (it stops only when no adjustment can shrink the gap
    /// further), so it does not park on the first value that happens to fall just inside tolerance.
    /// Because every accepted step strictly shrinks a non-negative integer error, the loop converges.
    static func fit(_ blocks: inout [PlannedBlock], targetSeconds: Int) {
        for _ in 0..<maxFitIterations {
            let error = totalSeconds(blocks) - targetSeconds
            if error == 0 { return }

            let candidates = error < 0 ? additions(in: blocks) : removals(in: blocks)
            var best: (adjustment: Adjustment, resultError: Int)?
            for (adjustment, delta) in candidates {
                let resultError = abs(error + delta)
                guard resultError < abs(error) else { continue }
                if best == nil || resultError < best!.resultError {
                    best = (adjustment, resultError)
                }
            }
            guard let chosen = best?.adjustment else { return }
            apply(chosen, to: &blocks)
        }
    }

    /// Planned wall-clock of a set of blocks mid-assembly (same formula as `plannedSeconds(of:)`).
    static func totalSeconds(_ blocks: [PlannedBlock]) -> Int {
        let items = blocks.flatMap(\.items)
        let work = items.reduce(0) { $0 + $1.seconds }
        return work + max(0, items.count - 1) * transitionSeconds
    }

    /// Every time-increasing adjustment available, with the seconds it would add: one per
    /// set-adjustable item below the set cap (add a set), and one per block holding a reserve exercise
    /// (promote the next reserve exercise). Enumerated in a fixed block/item order so ties resolve
    /// deterministically.
    private static func additions(in blocks: [PlannedBlock]) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if block.allowSetAdjust {
                for (itemIndex, item) in block.items.enumerated() where item.sets < maxTrainingSets {
                    let delta = item.exercise.estimatedTimePerSetSeconds + item.restSeconds
                    result.append((.addSet(block: blockIndex, item: itemIndex), delta))
                }
            }
            if let next = block.reserve.first {
                result.append((.addReserve(block: blockIndex), next.seconds + transitionSeconds))
            }
        }
        return result
    }

    /// Every time-decreasing adjustment available, with the (negative) seconds it would remove: one
    /// per set-adjustable item above the set floor (drop a set), and one per block holding more than
    /// its required minimum exercises (drop the last exercise).
    private static func removals(in blocks: [PlannedBlock]) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if block.allowSetAdjust {
                for (itemIndex, item) in block.items.enumerated() where item.sets > minTrainingSets {
                    let delta = -(item.exercise.estimatedTimePerSetSeconds + item.restSeconds)
                    result.append((.removeSet(block: blockIndex, item: itemIndex), delta))
                }
            }
            if block.items.count > block.minItems, let last = block.items.last {
                result.append((.dropItem(block: blockIndex), -(last.seconds + transitionSeconds)))
            }
        }
        return result
    }

    private static func apply(_ adjustment: Adjustment, to blocks: inout [PlannedBlock]) {
        switch adjustment {
        case let .addSet(block, item):
            blocks[block].items[item].sets += 1
        case let .removeSet(block, item):
            blocks[block].items[item].sets -= 1
        case let .addReserve(block):
            blocks[block].items.append(blocks[block].reserve.removeFirst())
        case let .dropItem(block):
            let removed = blocks[block].items.removeLast()
            blocks[block].reserve.insert(removed, at: 0)
        }
    }

    /// One timing-fit move, addressed by block/item index into the in-progress `[PlannedBlock]`.
    private enum Adjustment {
        case addSet(block: Int, item: Int)
        case removeSet(block: Int, item: Int)
        case addReserve(block: Int)
        case dropItem(block: Int)
    }
}

// MARK: - PlannedItem

/// One exercise as it is being sized during assembly: the movement, its capacity-relative per-set
/// target (reps or hold seconds from Step 6), the current set count (a timing lever), and the rest
/// between sets. Materializes into a playable `PrescribedExercise` once assembly is done.
struct PlannedItem: Equatable {
    let exercise: Exercise
    let reps: Int?
    let durationSeconds: Int?
    var sets: Int
    let restSeconds: Int

    /// Planned seconds for this item alone: `sets × estTimePerSet + (sets - 1) × rest`.
    var seconds: Int {
        sets * exercise.estimatedTimePerSetSeconds + max(0, sets - 1) * restSeconds
    }

    func materialize() -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets,
            reps: reps,
            durationSeconds: durationSeconds,
            restSeconds: restSeconds
        )
    }
}

// MARK: - PlannedBlock

/// A session block being assembled: its title and structural `category` (warm-up / strength /
/// mobility / cooldown), the exercises currently in it, a `reserve` of further candidates the timing
/// fit may promote, whether its exercises' set counts are a timing lever, and the floor on how many
/// exercises it must keep.
struct PlannedBlock {
    let title: String
    let category: ExerciseCategory
    var items: [PlannedItem]
    var reserve: [PlannedItem]
    /// Training blocks let timing fit add/drop sets; warm-up and cooldown stay at one set each.
    let allowSetAdjust: Bool
    /// The minimum exercises this block must retain (timing fit never trims below it).
    let minItems: Int

    /// The playable block, or `nil` when assembly left it empty (so empties never reach the player).
    func materialize() -> WorkoutBlock? {
        guard !items.isEmpty else { return nil }
        return WorkoutBlock(
            id: UUID(),
            title: title,
            category: category,
            exercises: items.map { $0.materialize() }
        )
    }
}

// MARK: - Builder

/// Generates the per-shape block skeleton (warm-up, training block(s), optional cooldown) seeded with
/// one exercise each plus reserves, running Steps 2-6 to fill the training blocks and the shared
/// mobility pool for the bookends. Kept a small stateful value so a single `usedIds` set stops the
/// same movement appearing in two blocks.
private struct Builder {
    let library: [Exercise]
    let pool: [Exercise]
    let recentLogs: [WorkoutLog]
    let asOf: Date
    let calendar: Calendar
    /// Movements already claimed by an earlier block (active or reserve), so blocks never collide.
    var usedIds: Set<String> = []

    /// Builds the ordered block skeleton for the session: warm-up first, the training block(s) the
    /// pillar plan calls for, and a cooldown when the session runs past `cooldownThresholdMinutes`.
    mutating func buildBlocks(pillarPlan: PillarPlan, requestedMinutes: Int) -> [PlannedBlock] {
        var blocks: [PlannedBlock] = [warmupBlock()]

        switch pillarPlan {
        case .single(let pillar):
            if pillar == .mobility {
                if let block = mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises) {
                    blocks.append(block)
                }
            } else if let block = strengthBlock() {
                blocks.append(block)
            }
        case .blend(let weights):
            // Lead with the staler pillar's block; the other becomes the smaller second block.
            let strengthLeads = weights.strength >= weights.mobility
            let strength = strengthBlock()
            let mobility = mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises)
            for block in (strengthLeads ? [strength, mobility] : [mobility, strength]) {
                if let block { blocks.append(block) }
            }
        }

        if requestedMinutes > SessionAssembly.cooldownThresholdMinutes, let cooldown = cooldownBlock() {
            blocks.append(cooldown)
        }
        return blocks
    }

    // MARK: Blocks

    /// The opening warm-up: the freshest mobility movements, one set each. Always first; in a
    /// mobility-led session it flows straight into the Movement Practice block so the opening doubles
    /// as warm-up + training.
    private mutating func warmupBlock() -> PlannedBlock {
        let items = mobilityItems(
            from: orderedMobility(holdsOnly: false),
            cap: SessionAssembly.maxWarmupExercises
        )
        return PlannedBlock(
            title: "Warm-Up",
            category: .warmup,
            items: items.isEmpty ? [] : [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: false,
            minItems: 1
        )
    }

    /// A mobility training block (Movement Practice): mobility movements ordered by staleness/variety,
    /// set counts adjustable for timing. `nil` when no mobility movement is left to fill it.
    private mutating func mobilityBlock(title: String, cap: Int) -> PlannedBlock? {
        let items = mobilityItems(from: orderedMobility(holdsOnly: false), cap: cap)
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: title,
            category: .mobility,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: true,
            minItems: 1
        )
    }

    /// The closing cooldown: static mobility holds (falling back to any mobility if no holds remain),
    /// one set each. `nil` when no mobility movement is left.
    private mutating func cooldownBlock() -> PlannedBlock? {
        var candidates = orderedMobility(holdsOnly: true)
        if candidates.isEmpty { candidates = orderedMobility(holdsOnly: false) }
        let items = mobilityItems(from: candidates, cap: SessionAssembly.maxCooldownExercises)
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: "Cooldown",
            category: .cooldown,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: false,
            minItems: 1
        )
    }

    /// The strength training block: one ability-matched exercise per strength/primal pattern, stalest
    /// pattern first (and never repeating the most recent session's lead pattern), each at its Step 6
    /// capacity-relative target. `nil` when the pool has no strength/primal movement.
    private mutating func strengthBlock() -> PlannedBlock? {
        var items: [PlannedItem] = []
        for pattern in orderedStrengthPatterns() {
            guard
                let selection = ProgressionChainSelection.select(
                    pattern: pattern,
                    library: library,
                    pool: pool,
                    recentLogs: recentLogs
                ),
                !usedIds.contains(selection.exercise.id)
            else { continue }

            let target = AdaptiveOverload.target(for: selection.exercise, recentLogs: recentLogs)
            usedIds.insert(selection.exercise.id)
            items.append(
                PlannedItem(
                    exercise: selection.exercise,
                    reps: target.reps,
                    durationSeconds: target.durationSeconds,
                    sets: target.sets,
                    restSeconds: SessionAssembly.strengthRestSeconds
                )
            )
        }
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: "Strength",
            category: .strength,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: true,
            minItems: 1
        )
    }

    // MARK: Candidate generation

    /// Turns ordered mobility exercises into one-set planned items (per-set value from Step 6),
    /// claiming each id so no later block reuses it.
    private mutating func mobilityItems(from exercises: [Exercise], cap: Int) -> [PlannedItem] {
        exercises.prefix(cap).map { exercise in
            let target = AdaptiveOverload.target(for: exercise, recentLogs: recentLogs)
            usedIds.insert(exercise.id)
            return PlannedItem(
                exercise: exercise,
                reps: target.reps,
                durationSeconds: target.durationSeconds,
                sets: 1,
                restSeconds: SessionAssembly.mobilityRestSeconds
            )
        }
    }

    /// The strength/primal patterns present in the pool, ordered stalest-first via `PatternFocus`,
    /// with the most recent session's lead pattern held out of the lead slot (Step 3's no-repeat rule).
    private func orderedStrengthPatterns() -> [MovementPattern] {
        let patterns = Array(
            Set(
                pool
                    .filter { $0.pillar == .strength || $0.pillar == .primal }
                    .map(\.movementPattern)
            )
        )
        guard !patterns.isEmpty else { return [] }

        let ranked = PatternFocus.rank(
            candidatePatterns: patterns,
            recentLogs: recentLogs,
            asOf: asOf,
            calendar: calendar
        )
        guard
            let lead = PatternFocus.select(
                candidatePatterns: patterns,
                recentLogs: recentLogs,
                asOf: asOf,
                calendar: calendar
            )
        else { return ranked }
        return [lead] + ranked.filter { $0 != lead }
    }

    /// Eligible, not-yet-claimed mobility movements ordered for variety: never-worked and longest-ago
    /// first, movements used in the last few sessions pushed back, then shortest (finest timing
    /// granularity) and id as deterministic tie-breaks.
    private func orderedMobility(holdsOnly: Bool) -> [Exercise] {
        let lastWorked = mobilityLastWorked()
        let recent = recentlyUsedIds()
        return pool
            .filter {
                $0.pillar == .mobility
                    && !usedIds.contains($0.id)
                    && (!holdsOnly || $0.isHold)
            }
            .sorted { lhs, rhs in
                let lhsRecent = recent.contains(lhs.id)
                let rhsRecent = recent.contains(rhs.id)
                if lhsRecent != rhsRecent { return !lhsRecent }

                let lhsDate = lastWorked[lhs.id]
                let rhsDate = lastWorked[rhs.id]
                if (lhsDate == nil) != (rhsDate == nil) { return lhsDate == nil }
                if let lhsDate, let rhsDate, lhsDate != rhsDate { return lhsDate < rhsDate }

                if lhs.estimatedTimePerSetSeconds != rhs.estimatedTimePerSetSeconds {
                    return lhs.estimatedTimePerSetSeconds < rhs.estimatedTimePerSetSeconds
                }
                return lhs.id < rhs.id
            }
    }

    /// Most recent completed (non-skipped) date per mobility exercise id, for variety ordering.
    private func mobilityLastWorked() -> [String: Date] {
        var lastWorked: [String: Date] = [:]
        for log in recentLogs {
            for logged in log.exercises where !logged.skipped {
                if let existing = lastWorked[logged.exerciseId], existing >= log.completedAt { continue }
                lastWorked[logged.exerciseId] = log.completedAt
            }
        }
        return lastWorked
    }

    /// Ids worked (non-skipped) in the most recent few sessions, pushed back in variety ordering so
    /// the user is not handed the same stretch two sessions running. Window mirrors Step 5's.
    private func recentlyUsedIds() -> Set<String> {
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
