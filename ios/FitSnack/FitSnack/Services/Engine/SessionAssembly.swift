import Foundation

/// Pipeline Step 7 of the deterministic engine (US-C07): take everything Steps 1-6 decided and
/// assemble a complete, playable `Workout` that opens with a warm-up, closes with a cooldown when
/// it runs long, and lands within ±1 minute of the minutes the user asked for.
///
/// This is the step that turns the pipeline's per-decision outputs into the structured session the
/// active-session player renders:
/// - **Shape** (Step 1, `SessionShapeTemplate`) decides single-focus vs. blend.
/// - **Pillars** (Step 2, `PillarPlan`) decide which pillar a single-focus trains, or - for a blend -
///   how the training time splits: the staleness `PillarWeights` size the blocks, so the staler pillar
///   both leads and gets the larger share. A short/full blend sizes strength (primal folded in) and
///   mobility; an extended blend (US-E02) promotes primal to a third, `locomotion`-driven block.
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

    /// Per-block ceilings on how many distinct movements each mobility-sourced block may draw from the
    /// shared 12-movement pool. The warm-up and the cooldown reserve their movements first (the
    /// cooldown before any Movement Practice block - see `buildBlocks`); the elastic Movement Practice
    /// block then takes whatever remains and makes up any shortfall with its set-count lever, so no
    /// block ever starves the cooldown of its static holds.
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
    ///
    /// `sessionPolicy` is the per-user program the engine runs on (US-E03): its `pillarWeighting`
    /// scales Step 2's staleness split, its `varietyWindow` sets Step 5's no-repeat window, and its
    /// `progressionRate` paces Step 6's overload bump. It defaults to `SessionPolicy.default` (every
    /// lever neutral), which reproduces pre-policy behavior exactly, so an unpolicied caller is
    /// unchanged.
    static func assemble(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default,
        asOf: Date,
        calendar: Calendar = .current
    ) -> Workout {
        let template = SessionShapeTemplate.select(requestedMinutes: requestedMinutes)
        // Step 0 (US-E04): the cold-start override reshapes the pillar plan (First-Week Contrast)
        // before the reported `focusPillar` is read from it, so a cold-start session's focus matches
        // the block `planBlocks` actually builds. A no-op once the engine retires cold-start.
        let pillarPlan = ColdStartOverride.overridePlan(
            PillarPlan.select(
                template: template,
                recentLogs: recentLogs,
                profile: user.profile,
                pillarWeighting: sessionPolicy.pillarWeighting,
                asOf: asOf,
                calendar: calendar
            ),
            template: template,
            user: user,
            sessionPolicy: sessionPolicy
        )

        var blocks = planBlocks(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            asOf: asOf,
            calendar: calendar
        )
        // Shape the blend's two training blocks toward their staleness-weighted shares first, then let
        // the global timing fit land the overall total within tolerance.
        shapeTowardTargets(&blocks)
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

    /// Builds the seeded block skeleton (warm-up, the pillar plan's training block(s) with their
    /// weight targets, and an optional cooldown) before the timing fit - the structural output of
    /// Steps 1-6. Exposed internally so tests can inspect block reserves and per-block weight targets
    /// prior to the global fit consuming them. `sessionPolicy` threads the US-E03 levers into
    /// Steps 2/5/6 (see `assemble`); it defaults to `SessionPolicy.default` (neutral, no regression).
    static func planBlocks(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default,
        asOf: Date,
        calendar: Calendar = .current
    ) -> [PlannedBlock] {
        let template = SessionShapeTemplate.select(requestedMinutes: requestedMinutes)
        // Step 0 (US-E04): the cold-start override runs before Steps 1-6. It forces First-Week
        // Contrast onto the pillar plan and caps the eligible pool at the contract's Starting
        // Difficulty; both are no-ops once the engine retires cold-start (US-G04), so a warmed-up
        // user runs exactly the US-E03 pipeline.
        let pillarPlan = ColdStartOverride.overridePlan(
            PillarPlan.select(
                template: template,
                recentLogs: recentLogs,
                profile: user.profile,
                pillarWeighting: sessionPolicy.pillarWeighting,
                asOf: asOf,
                calendar: calendar
            ),
            template: template,
            user: user,
            sessionPolicy: sessionPolicy
        )
        let pool = ColdStartOverride.cappedPool(
            ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs),
            user: user,
            sessionPolicy: sessionPolicy
        )
        var builder = Builder(
            library: library,
            pool: pool,
            recentLogs: recentLogs,
            progressionRate: sessionPolicy.progressionRate,
            varietyWindow: sessionPolicy.varietyWindow,
            asOf: asOf,
            calendar: calendar
        )
        return builder.buildBlocks(
            pillarPlan: pillarPlan,
            template: template,
            requestedMinutes: requestedMinutes
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

    /// Planned wall-clock of a single block in isolation: its items' work + rests + the transitions
    /// *between* those items. Because every timing-fit adjustment touches exactly one block, the same
    /// add/drop deltas the global fit uses also describe this per-block measure exactly, so the
    /// weight-shaping pass and the global fit stay consistent.
    static func blockSeconds(_ block: PlannedBlock) -> Int {
        let work = block.items.reduce(0) { $0 + $1.seconds }
        return work + max(0, block.items.count - 1) * transitionSeconds
    }

    // MARK: - Weighted shaping

    /// Grows each block that carries a `targetSeconds` toward that share (a best-fit greedy scoped to
    /// the single block), so a blend's training time is split by the Step 2 pillar weights *before*
    /// `fit` lands the overall total. It uses the same levers as the global fit - set counts within the
    /// rails and reserve promotion - and never touches the capacity-relative per-set target from Step 6.
    static func shapeTowardTargets(_ blocks: inout [PlannedBlock]) {
        for index in blocks.indices {
            guard let target = blocks[index].targetSeconds else { continue }
            for _ in 0..<maxFitIterations {
                let error = blockSeconds(blocks[index]) - target
                if error == 0 { break }

                let candidates = error < 0
                    ? additions(in: blocks, restrictedTo: index)
                    : removals(in: blocks, restrictedTo: index)
                var best: (adjustment: Adjustment, resultError: Int)?
                for (adjustment, delta) in candidates {
                    let resultError = abs(error + delta)
                    guard resultError < abs(error) else { continue }
                    if best == nil || resultError < best!.resultError {
                        best = (adjustment, resultError)
                    }
                }
                guard let chosen = best?.adjustment else { break }
                apply(chosen, to: &blocks)
            }
        }
    }

    /// Every time-increasing adjustment available, with the seconds it would add: one per
    /// set-adjustable item below the set cap (add a set), and one per block holding a reserve exercise
    /// (promote the next reserve exercise). Enumerated in a fixed block/item order so ties resolve
    /// deterministically. `restrictedTo`, when set, limits the enumeration to a single block (used by
    /// the weight-shaping pass to grow one training block toward its own share).
    private static func additions(in blocks: [PlannedBlock], restrictedTo only: Int? = nil) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if let only, only != blockIndex { continue }
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
    /// its required minimum exercises (drop the last exercise). `restrictedTo`, when set, limits the
    /// enumeration to a single block (used by the weight-shaping pass).
    private static func removals(in blocks: [PlannedBlock], restrictedTo only: Int? = nil) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if let only, only != blockIndex { continue }
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
    /// The planned-seconds share this block should be shaped toward before the global timing fit, set
    /// for a blend's two training blocks from the Step 2 pillar weights. `nil` leaves the block to the
    /// global fit alone (warm-up, cooldown, and single-focus training).
    var targetSeconds: Int? = nil

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
    /// Session Policy lever (US-E03): paces Step 6's overload bump. `1.0` is neutral.
    let progressionRate: Double
    /// Session Policy lever (US-E03): Step 5's no-repeat variety window, also mirrored by the
    /// mobility variety ordering so both use the same per-user window.
    let varietyWindow: Int
    let asOf: Date
    let calendar: Calendar
    /// Movements already claimed by an earlier block (active or reserve), so blocks never collide.
    var usedIds: Set<String> = []

    /// Builds the ordered block skeleton for the session: warm-up first, the training block(s) the
    /// pillar plan calls for, and a cooldown when the session runs past `cooldownThresholdMinutes`.
    ///
    /// The cooldown's static holds are *reserved before* the Movement Practice block draws from the
    /// shared mobility pool (it is constructed here, up front, and appended last only at output time),
    /// so a blend's cooldown keeps real holds plus reserves instead of the single leftover stretch it
    /// would get if the training block claimed the pool first.
    ///
    /// `template` distinguishes an extended blend (US-E02), which promotes primal to its own block,
    /// from the shorter blends that keep folding primal into strength.
    mutating func buildBlocks(
        pillarPlan: PillarPlan,
        template: SessionShapeTemplate,
        requestedMinutes: Int
    ) -> [PlannedBlock] {
        let warmup = warmupBlock()
        let cooldown = requestedMinutes > SessionAssembly.cooldownThresholdMinutes ? cooldownBlock() : nil

        var middle: [PlannedBlock] = []
        switch pillarPlan {
        case .single(let pillar):
            switch pillar {
            case .mobility:
                if let block = mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises) {
                    middle.append(block)
                }
            case .primal:
                // A single-focus primal day (only reached under the Step 0 First-Week Contrast, US-E04)
                // builds a dedicated locomotion block, degrading gracefully to strength then mobility if
                // the capped pool leaves no eligible primal movement so the day is never empty.
                let block = primalBlock()
                    ?? strengthBlock()
                    ?? mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises)
                if let block { middle.append(block) }
            case .strength:
                if let block = strengthBlock() {
                    middle.append(block)
                }
            }
        case .blend(let weights):
            middle = blendBlocks(
                weights: weights,
                warmup: warmup,
                cooldown: cooldown,
                template: template,
                requestedMinutes: requestedMinutes
            )
        }

        return [warmup] + middle + (cooldown.map { [$0] } ?? [])
    }

    /// The training blocks of a blend, ordered staler-pillar-first and each tagged with the
    /// planned-seconds share it should be shaped toward. The share is the remaining training budget
    /// (request minus the warm-up and cooldown the bookends already cost) split in proportion to the
    /// Step 2 staleness weights, so the staler pillar ends up the *larger* block, not merely the lead.
    ///
    /// A short or full blend produces the two co-primary blocks (strength - which still folds primal
    /// in - and mobility). An extended blend (US-E02) promotes primal to its own `locomotion`-driven
    /// block: the strength block sheds primal, and a dedicated primal block joins the split, ordered
    /// among the three by its weighted share.
    private mutating func blendBlocks(
        weights: PillarWeights,
        warmup: PlannedBlock,
        cooldown: PlannedBlock?,
        template: SessionShapeTemplate,
        requestedMinutes: Int
    ) -> [PlannedBlock] {
        let extended = template == .blendExtended

        // In an extended blend primal earns its own block, so the strength block must not also fold
        // primal in (that would double-book the same locomotion movement).
        var strength = strengthBlock(includePrimal: !extended)
        var mobility = mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises)
        var primal = extended ? primalBlock() : nil

        let bookendSeconds = SessionAssembly.blockSeconds(warmup)
            + (cooldown.map(SessionAssembly.blockSeconds) ?? 0)
        let trainingBudget = max(0, requestedMinutes * 60 - bookendSeconds)
        strength?.targetSeconds = Int((Double(trainingBudget) * weights.strength).rounded())
        mobility?.targetSeconds = Int((Double(trainingBudget) * weights.mobility).rounded())
        primal?.targetSeconds = Int((Double(trainingBudget) * weights.primal).rounded())

        // Order the blocks staler-pillar-first (heavier weight leads); a fixed pillar order breaks
        // ties deterministically, matching the prior two-block strength-leads-on-tie behavior.
        let entries: [(weight: Double, tieBreak: Int, block: PlannedBlock?)] = [
            (weights.strength, 0, strength),
            (weights.mobility, 1, mobility),
            (weights.primal, 2, primal),
        ]
        return entries
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.tieBreak < $1.tieBreak }
            .compactMap { $0.block }
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

    /// The strength training block: one ability-matched exercise per strength pattern, stalest
    /// pattern first (and never repeating the most recent session's lead pattern), each at its Step 6
    /// capacity-relative target. When `includePrimal` is set (every shape but an extended blend), the
    /// primal `locomotion` pattern is folded in here as before; an extended blend passes `false` so
    /// primal instead earns its own dedicated block. `nil` when the pool has no eligible movement.
    private mutating func strengthBlock(includePrimal: Bool = true) -> PlannedBlock? {
        var items: [PlannedItem] = []
        for pattern in orderedStrengthPatterns(includePrimal: includePrimal) {
            guard
                let selection = ProgressionChainSelection.select(
                    pattern: pattern,
                    library: library,
                    pool: pool,
                    recentLogs: recentLogs,
                    varietyWindow: varietyWindow
                ),
                !usedIds.contains(selection.exercise.id)
            else { continue }

            let target = AdaptiveOverload.target(
                for: selection.exercise,
                recentLogs: recentLogs,
                progressionRate: progressionRate
            )
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

    /// The dedicated primal block for an extended blend (US-E02): the ability-matched movement from
    /// the primal `locomotion` chain at its Step 6 capacity-relative target, sets adjustable for
    /// timing. Draws only `pillar == .primal` movements from the eligible pool, so the Zero-Equipment
    /// Floor and difficulty gating still hold. `nil` when the pool has no eligible primal movement
    /// (e.g. a difficulty cap or injury filtered them out) - the session then degrades gracefully to
    /// strength + mobility rather than emitting an empty block.
    private mutating func primalBlock() -> PlannedBlock? {
        guard
            let selection = ProgressionChainSelection.select(
                pattern: .locomotion,
                library: library,
                pool: pool,
                recentLogs: recentLogs,
                varietyWindow: varietyWindow
            ),
            selection.exercise.pillar == .primal,
            !usedIds.contains(selection.exercise.id)
        else { return nil }

        let target = AdaptiveOverload.target(
            for: selection.exercise,
            recentLogs: recentLogs,
            progressionRate: progressionRate
        )
        usedIds.insert(selection.exercise.id)
        let item = PlannedItem(
            exercise: selection.exercise,
            reps: target.reps,
            durationSeconds: target.durationSeconds,
            sets: target.sets,
            restSeconds: SessionAssembly.strengthRestSeconds
        )
        return PlannedBlock(
            title: "Primal Movement",
            category: .primal,
            items: [item],
            reserve: [],
            allowSetAdjust: true,
            minItems: 1
        )
    }

    // MARK: Candidate generation

    /// Turns ordered mobility exercises into one-set planned items (per-set value from Step 6),
    /// claiming each id so no later block reuses it.
    private mutating func mobilityItems(from exercises: [Exercise], cap: Int) -> [PlannedItem] {
        exercises.prefix(cap).map { exercise in
            let target = AdaptiveOverload.target(
                for: exercise,
                recentLogs: recentLogs,
                progressionRate: progressionRate
            )
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

    /// The strength patterns present in the pool, ordered stalest-first via `PatternFocus`, with the
    /// most recent session's lead pattern held out of the lead slot (Step 3's no-repeat rule). Primal
    /// `locomotion` patterns are included only when `includePrimal` is set (folded into strength for
    /// every shape but an extended blend, which gives primal its own block instead).
    private func orderedStrengthPatterns(includePrimal: Bool) -> [MovementPattern] {
        let patterns = Array(
            Set(
                pool
                    .filter { $0.pillar == .strength || (includePrimal && $0.pillar == .primal) }
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
    /// the user is not handed the same stretch two sessions running. The window is the policy's
    /// `varietyWindow`, mirroring Step 5's no-repeat window per user (US-E03).
    private func recentlyUsedIds() -> Set<String> {
        let recentSessions = recentLogs
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(max(0, varietyWindow))
        return recentSessions.reduce(into: Set<String>()) { ids, log in
            for logged in log.exercises where !logged.skipped {
                ids.insert(logged.exerciseId)
            }
        }
    }
}
