import Foundation

/// The always-valid, per-user program the deterministic engine runs on (US-D03).
///
/// The Session Policy is the single seam between the AI Programmer (Epic F) and the engine
/// (Epic E): the Programmer *writes* a policy, the engine *reads* one, and they never
/// otherwise touch. The Programmer never generates a session and is never on the path
/// between opening the app and starting one - it shapes the program, not the session.
///
/// A policy is valid from the very first launch: `SessionPolicy.default` is a complete,
/// sensible policy, so the engine can generate a session offline and before the Programmer
/// has ever run. The last-written policy is persisted (as `CDSessionPolicy`, US-D03) so it
/// survives relaunch and offline use, and a freshly computed policy applies on the next open
/// rather than mid-session (the user never waits on programming).
///
/// `SessionPolicy.default` sets every lever to neutral, so wiring the policy through the
/// pipeline (US-E03) reproduces the pre-policy engine behavior exactly until the Programmer
/// moves a lever.
struct SessionPolicy: Codable, Equatable {

    /// Monotonic version. `default` is `1`; each re-program increments it (US-F03) so the
    /// most recently written policy is identifiable.
    var version: Int

    /// When this policy was written. `default` uses a fixed sentinel epoch (never `Date()`)
    /// so the default is deterministic, matching the engine's time-injection convention -
    /// time is always passed in, never read from the wall clock inside pure logic.
    var updatedAt: Date

    /// Who last wrote this policy.
    var updatedBy: UpdatedBy

    /// Multiplier on the Adaptive Overload bump in Step 6 (US-E03/US-F03). `1.0` is neutral;
    /// a higher rate advances reps/holds faster, still clamped to the engine's safety rails.
    var progressionRate: Double

    /// Per-pillar multiplier on staleness that Step 2 once used to size a blend's pillar split
    /// (US-E03). It is **inert since US-M01**: removing the Movement Practice block retired the
    /// strength-vs-mobility split machinery (`PillarBalance`), and no engine path reads this lever
    /// today. The field is kept (decoded, neutral `1.0` for every pillar) so persisted policies and the
    /// Programmer continue to round-trip unchanged; a future story that reintroduces a within-family
    /// split would wire it back in. Always carries every pillar (`strength`/`mobility`/`primal`).
    var pillarWeighting: [Pillar: Double]

    /// The no-repeat variety window Step 5 honors (US-E03), replacing the engine's previously
    /// hardcoded `recentSessionWindow = 3` so it is tunable per user.
    var varietyWindow: Int

    /// Per-`MovementPattern` **emphasis** on Step 3's stalest-first ordering (US-AC05): a bounded,
    /// neutral-by-default preference the coach (US-AC07) can later use to bias the session toward or
    /// away from a pattern *without ever breaking session structure*.
    ///
    /// It is a **multiplier on staleness**, exactly the vocabulary the retired `pillarWeighting` once
    /// carried (see below), applied one level down at the pattern granularity and actually wired into
    /// the engine: Step 3 ranks patterns by days-since-worked, and a pattern's emphasis scales that
    /// staleness before the sort, so `> 1.0` surfaces a pattern earlier (as if staler) and `< 1.0`
    /// later (as if fresher). `1.0` (neutral) is a no-op, reproducing the pre-US-AC05 ordering exactly.
    ///
    /// It is strictly a **preference layered on the existing ordering, never a filter** (shaped like the
    /// `sitsLong` bias): it only reorders the pattern list, so it can never remove a movement, starve a
    /// pool, change a block's structure or its uniform round count (ADR-0003), or reintroduce a mobility
    /// middle block. A de-emphasized pattern still appears in the list (just later) and is still
    /// available to the block's breadth-first widening as an accessory. The no-repeat rule (never repeat
    /// the previous session's lead pattern) is a structural safety that emphasis never overrides.
    ///
    /// **Bounded and clamped** to `[minEmphasis, maxEmphasis]` = `[0.5, 2.0]` around `neutralEmphasis`
    /// `1.0` (the engine clamps every value before use via `SessionPolicy.clampedEmphasis`, so an
    /// out-of-range value is pinned to the rail, never treated as a filter). The range is deliberately
    /// gentle: at most 2x/0.5x staleness means a genuinely neglected pattern can still out-rank an
    /// emphasized-but-fresh one, so emphasis *nudges* the lead rather than dictating it - the deliberate
    /// answer to the PRD's open question ("how strongly before it feels like the user chose").
    ///
    /// Additive and round-trip safe like the Start Seed fields: a policy persisted before US-AC05 lacks
    /// this key and decodes to `neutralPatternEmphasis` (every pattern `1.0`), so it loads without error
    /// and behaves exactly as it did. Always carries every `MovementPattern`; an absent pattern is read
    /// as neutral by the engine regardless.
    ///
    /// Defaulted to neutral on the memberwise initializer so it is *always* present-and-neutral: a caller
    /// can never construct a policy with a missing or invalid emphasis, and existing construction sites
    /// need not restate the neutral map. `SessionPolicy.default` still sets it explicitly for clarity.
    var patternEmphasis: [MovementPattern: Double] = SessionPolicy.neutralPatternEmphasis

    /// The cold-start override contract, present only during the cold-start window (US-E04):
    /// it caps Starting Difficulty and carries the Start Seed (US-O02) - the difficulty floor and
    /// opening volume the self-reported fitness level starts at. (Its pillar-lead override was retired
    /// by US-M01; the strength lead is now structural.) `nil` once the engine retires cold-start
    /// (US-G04), after which Step 0 is a no-op.
    var coldStartContract: ColdStartContract?

    /// The Re-entry Ramp state, present only while walking a user back up after a Return
    /// (US-E06). `nil` in the steady state.
    var reentry: Reentry?

    /// An honest note about the last real change (US-F04/US-G03), or `nil` when there is
    /// nothing to say. It may only name a change the sessions actually reflect.
    var note: Note?
}

// MARK: - Nested policy types

extension SessionPolicy {

    /// Who last wrote the policy. This is persisted (part of the JSON contract), so the raw
    /// values are stable - renaming a case's raw value would silently break stored policies.
    enum UpdatedBy: String, Codable, CaseIterable, Equatable {
        /// The built-in default policy; the AI Programmer has never run for this user.
        case `default`
        /// Written by the on-device deterministic Programmer at option (C) (US-F03).
        case deterministic
        /// Written with an LLM-sourced change (reserved; the MVP Programmer is deterministic,
        /// and only the Variety Language note is ever LLM-sourced).
        case llm
    }

    /// The cold-start override contract (US-E04/US-G01/US-G02). Present only while
    /// `user.coldStart.active`; the engine reads it in Step 0 and never past the handoff.
    ///
    /// Alongside the difficulty *ceiling* it carries the **Start Seed** (US-O02): the floor and the
    /// volume a self-reported fitness level starts at, so an active user's first sessions are not
    /// served the absolute beginner tier. The three seed fields are additive and decode to neutral
    /// values (floor 1 / x1.0 / 3 sets), so a policy persisted before US-O02 still loads and behaves
    /// exactly as it did.
    struct ColdStartContract: Codable, Equatable {
        /// Once the Step 0 gate that forced every cold-start day to lead **strength** (US-004). It is
        /// **inert since US-M01**: the strength lead is now structural in `SessionAssembly` (every
        /// session builds a leading strength block), so `ColdStartOverride` no longer carries a
        /// pillar-lead override and nothing reads this flag. The field is kept (still seeded `true`,
        /// still decoded) so persisted contracts round-trip unchanged. (Named for the long-retired
        /// First-Week Contrast spread it originally replaced.)
        var forceContrastSpread: Bool
        /// Hard difficulty cap for cold-start sessions, in `1...5`. It is the *ceiling* of the Start
        /// Seed band: the engine serves at the gentle end of `[startingDifficultyFloor, this]` (below
        /// for warm-up/mobility/cooldown, which are never floored), so a mis-reported fitness level
        /// never yields a badly over-hard first day.
        var cappedMaxDifficulty: Int
        /// Start Seed (US-O02): the difficulty *floor* the strength and primal training pool is banded
        /// to, so a no-history user starts at the band entry rather than the chain's absolute entry
        /// tier. `1` (neutral) is a no-op - the whole band beneath the cap stays eligible.
        var startingDifficultyFloor: Int = ColdStartContract.neutralStartingDifficultyFloor
        /// Start Seed (US-O02): multiplier on the *no-history* per-set target (reps or hold seconds),
        /// so an active user's first prescription carries proportionate volume. `1.0` is neutral.
        /// Capacity-derived targets (session 2+ of a movement) are never scaled by it.
        var startingRepMultiplier: Double = ColdStartContract.neutralStartingRepMultiplier
        /// Start Seed (US-O02): the set count of a *no-history* prescription.
        var startingSets: Int = ColdStartContract.neutralStartingSets

        /// The neutral Start Seed - the values a pre-US-O02 policy decodes to, reproducing the
        /// previous behavior exactly: the full band beneath the cap, unscaled per-set targets, and
        /// the engine's own default set count.
        ///
        /// These are the single definition of "neutral": the engine aliases them
        /// (`AdaptiveOverload.neutralStartingRepMultiplier` / `.defaultSets`) rather than restating
        /// them, so the contract and the step that consumes it cannot drift apart.
        static let neutralStartingDifficultyFloor = 1
        static let neutralStartingRepMultiplier = 1.0
        static let neutralStartingSets = 3
    }

    /// The Re-entry Ramp state after a Return (US-E06). Difficulty is held below normal and
    /// walked back up over the remaining sessions - the readjustment for lost time lives here,
    /// never in the Return itself.
    struct Reentry: Codable, Equatable {
        /// Sessions still to ramp back up; decrements each session until it reaches zero.
        var rampSessionsRemaining: Int
    }

    /// The user-visible note attached to a re-program (US-F04/US-G03). The language may only
    /// name a change the engine actually produced - never a hollow callback to `why`.
    struct Note: Codable, Equatable {
        /// The templated (or LLM) line describing the real change.
        var text: String
        /// Where the note's language came from.
        var source: Source

        /// The origin of a note's language. Persisted (part of the JSON contract), so the raw
        /// values are stable.
        enum Source: String, Codable, CaseIterable, Equatable {
            /// The deterministic template - always available, offline-safe, never blocks.
            case template
            /// The LLM Variety Language slice (US-G03), used only when online, always with a
            /// template fallback.
            case llm
        }
    }
}

// MARK: - Default policy

extension SessionPolicy {

    /// A fixed sentinel timestamp for a policy the AI Programmer has never rewritten. Using a
    /// stable reference epoch (not `Date()`) keeps `default` deterministic.
    static let unprogrammedEpoch = Date(timeIntervalSinceReferenceDate: 0)

    /// The neutral (unbiased) pillar weighting: an equal `1.0` multiplier for every pillar.
    /// Derived from `Pillar.allCases` so it always covers the full set - a new pillar would
    /// be weighted neutrally rather than silently omitted.
    static var neutralPillarWeighting: [Pillar: Double] {
        Dictionary(uniqueKeysWithValues: Pillar.allCases.map { ($0, 1.0) })
    }

    // MARK: Pattern emphasis rails (US-AC05)

    /// The neutral pattern-emphasis multiplier: a `1.0` staleness scale, a no-op on Step 3's ordering.
    static let neutralEmphasis: Double = 1.0
    /// The lower rail of a pattern-emphasis value: a de-emphasized pattern appears at most half as
    /// stale, so it surfaces later - but is never removed, so this is a preference, never a filter.
    static let minEmphasis: Double = 0.5
    /// The upper rail of a pattern-emphasis value: an emphasized pattern appears at most twice as
    /// stale, so it surfaces earlier. Kept gentle so a neglected pattern can still out-rank a fresh
    /// emphasized one (emphasis nudges the lead, never dictates it).
    static let maxEmphasis: Double = 2.0

    /// Clamps a pattern-emphasis multiplier to `[minEmphasis, maxEmphasis]`. The single definition of
    /// the rail: the engine clamps every value through this before use, so an out-of-range coach write
    /// (US-AC07) is pinned to the rail rather than ever acting as a filter or inverting the ordering.
    static func clampedEmphasis(_ value: Double) -> Double {
        min(maxEmphasis, max(minEmphasis, value))
    }

    /// The neutral (unbiased) pattern emphasis: an equal `1.0` staleness multiplier for every
    /// movement pattern. Derived from `MovementPattern.allCases` so it always covers the full set - a
    /// new pattern would be weighted neutrally rather than silently omitted. This is the value a policy
    /// persisted before US-AC05 decodes to, reproducing the pre-US-AC05 Step 3 ordering exactly.
    static var neutralPatternEmphasis: [MovementPattern: Double] {
        Dictionary(uniqueKeysWithValues: MovementPattern.allCases.map { ($0, neutralEmphasis) })
    }

    // MARK: Progression-rate rail and coach-easing gate (US-AC06)

    /// The neutral progression rate: a `1.0` multiplier on Step 6's Adaptive Overload bump, a no-op that
    /// reproduces the pre-policy curve. The same value the engine's `AdaptiveOverload.neutralProgressionRate`
    /// uses - kept equal by construction (both are the neutral `progressionRate` lever).
    static let neutralProgressionRate: Double = 1.0
    /// The lower rail of `progressionRate`: pace eases to at most half the neutral advancing bump. This is
    /// the deterministic Programmer's long-standing plateau-easing floor (`PlateauDiagnosis` aliases it).
    static let minProgressionRate: Double = 0.5
    /// The upper rail of `progressionRate`: pace advances at most twice the neutral bump - the engine's
    /// long-standing ceiling on how aggressive a policy may get (`PlateauDiagnosis` aliases it).
    static let maxProgressionRate: Double = 2.0

    /// Clamps a `progressionRate` to `[minProgressionRate, maxProgressionRate]`. The single definition of
    /// the policy-level rate rail (mirroring `clampedEmphasis`): every writer that sets `progressionRate`
    /// - the engine or the coach - stays inside the engine's safety band. A **coach** write is *additionally*
    /// capped at the engine-earned value by `easingProgressionRate(towardCoachProposed:)`, so it can lower
    /// pace but never raise it.
    static func clampedProgressionRate(_ value: Double) -> Double {
        min(maxProgressionRate, max(minProgressionRate, value))
    }

    // MARK: Variety-window rail and coach-narrowing gate (US-AC07)

    /// The lower rail of `varietyWindow`: the no-repeat window never narrows past one session (a session
    /// still never repeats the immediately previous lead pattern). The deterministic Programmer's
    /// long-standing floor (`PlateauDiagnosis` aliases it), now shared so the coach's narrowing floor and
    /// the engine's easing floor cannot drift apart.
    static let minVarietyWindow: Int = 1
    /// The upper rail of `varietyWindow`: the widest the window ever opens. The deterministic Programmer's
    /// long-standing ceiling (`PlateauDiagnosis` aliases it).
    static let maxVarietyWindow: Int = 6

    /// Clamps a `varietyWindow` to `[minVarietyWindow, maxVarietyWindow]`. The single definition of the
    /// policy-level window rail (mirroring `clampedProgressionRate`): every writer that sets
    /// `varietyWindow` stays inside the engine's sane operating range. A **coach** write is *additionally*
    /// capped at the in-force value by `easingVarietyWindow(towardCoachProposed:)`, so it can narrow the
    /// window (toward familiar movement) but never widen it - widening (fresher, less-repeated movement) is
    /// added friction the coach is not allowed to impose on a user a safety back-off has eased.
    static func clampedVarietyWindow(_ value: Int) -> Int {
        min(maxVarietyWindow, max(minVarietyWindow, value))
    }

    /// The always-valid starting policy for a fresh user (US-D03): every lever neutral so the
    /// engine behaves exactly as it did before policies existed. Progression at `1.0`, equal
    /// weighting across all pillars, a 3-session variety window, and no cold-start, re-entry,
    /// or note attached yet. Onboarding (US-I01/US-G01) layers a `coldStartContract` on top.
    static let `default` = SessionPolicy(
        version: 1,
        updatedAt: unprogrammedEpoch,
        updatedBy: .default,
        progressionRate: 1.0,
        pillarWeighting: neutralPillarWeighting,
        varietyWindow: 3,
        patternEmphasis: neutralPatternEmphasis,
        coldStartContract: nil,
        reentry: nil,
        note: nil
    )
}

// MARK: - Asymmetric pace easing: the coach eases down, only the engine advances (US-AC06)

extension SessionPolicy {

    /// **Asymmetric pace easing (US-AC06): a coach may ease `progressionRate` down, never up.**
    ///
    /// The single structural seam a coach-sourced (`.llm`) `progressionRate` change must pass through,
    /// ahead of the live coach policy-write path (US-AC07). It returns a copy of this policy whose
    /// `progressionRate` is set from the coach's `proposed` value but **can only ever ease down, never
    /// rise above the pace the deterministic engine already earned**:
    ///
    /// ```
    /// min(clampedProgressionRate(proposed), progressionRate)
    /// ```
    ///
    /// so the result is both inside the rate rail *and* no higher than the rate currently in force. A
    /// coach *attempt to raise* pace (a `proposed` above the current rate) is silently clamped to no
    /// increase, not applied; a genuine ease-down (a lower `proposed`) takes effect.
    ///
    /// This is *stricter than or equal to* the acceptance criterion ("the coach may not raise pace above
    /// the engine-earned value"), and never weaker, by a structural invariant: **upward pace is owned
    /// solely by the engine** (Adaptive Overload / the Asymmetric Ramp; the deterministic Programmer's
    /// `.deterministic`/`.default` writes), and a coach write only ever lowers - so the in-force rate is
    /// always ≤ the last engine-earned rate. Capping a coach write at the in-force rate therefore caps it
    /// at or below the engine-earned rate too, without this type needing to persist a separate
    /// engine-earned field. (If a later story needs the coach to *restore* pace within `[floor,
    /// engine-earned]` after a prior ease, that engine-earned ceiling can be threaded in explicitly; the
    /// no-increase guarantee this method owns holds regardless.)
    ///
    /// The clamp is **structural, not conventional**: authoring an `.llm` pace change *is* this call, so
    /// the coach write path (US-AC07) cannot produce a coach-sourced rate write that increases pace
    /// without bypassing the one sanctioned producer. It stamps `updatedBy == .llm` (the coach's
    /// provenance, inseparable from the clamp) and moves only the rate lever, leaving `version`/
    /// `updatedAt`/`note` to the write orchestration - exactly as `PlateauDiagnosis.reweighted` moves
    /// only levers and leaves provenance and persistence to its service.
    ///
    /// Engine writes (`.deterministic`/`.default`) never call this and are wholly unaffected: they own
    /// upward pace and set `progressionRate` directly (still inside the shared rail). `asOf`-pure - it
    /// reads no clock.
    func easingProgressionRate(towardCoachProposed proposed: Double) -> SessionPolicy {
        var next = self
        next.progressionRate = min(Self.clampedProgressionRate(proposed), progressionRate)
        next.updatedBy = .llm
        return next
    }

    /// **Coach variety narrowing (US-AC07): a coach may narrow `varietyWindow`, never widen it.**
    ///
    /// The `varietyWindow` sibling of `easingProgressionRate`, and the second half of what makes every
    /// coach-touchable lever *disjoint or only-downward*. A coach-sourced (`.llm`) window write is clamped
    /// to `min(clampedVarietyWindow(proposed), inForceWindow)`, so it can only ever pull the no-repeat
    /// window **in** (toward more familiar, less-rotated movement - the "reduce friction" direction the
    /// disengagement de-load itself narrows toward), never push it **out**. Widening the window adds novelty
    /// and reduces repetition, which is *more* challenge/friction - the same thing US-AC06 forbids the coach
    /// from doing to `progressionRate` - so it stays the engine's alone.
    ///
    /// This is what lets a coach write overlay onto the *current* in-force policy and never clobber a
    /// deterministic safety back-off: the disengagement de-load narrows `varietyWindow`, and a coach write
    /// capped at the in-force (already-narrowed) value can only narrow it further, never re-open it. It
    /// stamps `updatedBy == .llm` and moves only this lever, leaving `version`/`updatedAt`/`note` to the
    /// write orchestration (`CoachSessionPolicyService`). `asOf`-pure.
    func easingVarietyWindow(towardCoachProposed proposed: Int) -> SessionPolicy {
        var next = self
        next.varietyWindow = min(Self.clampedVarietyWindow(proposed), varietyWindow)
        next.updatedBy = .llm
        return next
    }

    /// **The safety-sovereign coach overlay (US-AC07, ADR-0005).** Apply a bounded `CoachPolicyProposal`
    /// onto *this* (the current, freshest in-force) policy, moving **only** the three preference levers and
    /// leaving every safety lever - `coldStartContract`, `reentry`, `pillarWeighting` - and the
    /// `version`/`updatedAt`/`note` bookkeeping untouched (provenance and persistence are
    /// `CoachSessionPolicyService`'s job, exactly as `PlateauDiagnosis.reweighted` leaves them to its
    /// service).
    ///
    /// Because it *overlays onto the current policy* rather than replacing it, and because each lever it
    /// touches is either **disjoint** from every deterministic safety move (`patternEmphasis` - no safety
    /// move reads or writes it) or **only-downward** (`progressionRate` eased down only via
    /// `easingProgressionRate`; `varietyWindow` narrowed only via `easingVarietyWindow`), a coach write can
    /// never undo a deterministic de-load / Re-entry Ramp / cold-start that landed since - *safety >
    /// preference* holds structurally, not by convention. Every proposed value is clamped to the engine's
    /// rails first, so even an out-of-range or hostile proposal (a compromised proxy) is pinned to a safe,
    /// order-preserving value and never acts as a filter. Pure and `asOf`-free.
    func applyingCoachProposal(_ proposal: CoachPolicyProposal) -> SessionPolicy {
        var next = self
        // Emphasis: disjoint from every safety move, so a straight clamped overlay is safe. Absent
        // patterns keep their current emphasis (this is an overlay, not a replacement).
        for (pattern, value) in proposal.patternEmphasis {
            next.patternEmphasis[pattern] = Self.clampedEmphasis(value)
        }
        // Progression: ease down only, capped at the in-force (engine-earned) rate (US-AC06 seam).
        if let proposedRate = proposal.easedProgressionRate {
            next = next.easingProgressionRate(towardCoachProposed: proposedRate)
        }
        // Variety: narrow only, capped at the in-force window (the US-AC07 seam above).
        if let proposedWindow = proposal.narrowedVarietyWindow {
            next = next.easingVarietyWindow(towardCoachProposed: proposedWindow)
        }
        return next
    }

    /// Whether a coach overlay actually moved one of the three preference levers relative to `other` -
    /// the honest "did anything change" gate the write path uses to decide whether to persist a new policy
    /// (and therefore whether there is a real change to note). Compares only the coach-touchable levers,
    /// ignoring provenance/version/timestamp, so a no-op proposal (everything clamped away or already at the
    /// in-force value) writes nothing and leaves the in-force policy - and its note - untouched.
    func coachLeversDiffer(from other: SessionPolicy) -> Bool {
        progressionRate != other.progressionRate
            || varietyWindow != other.varietyWindow
            || patternEmphasis != other.patternEmphasis
    }
}

// MARK: - Backward-compatible decoding

extension SessionPolicy {

    /// The persisted JSON contract for a `SessionPolicy`. Written out explicitly because the
    /// hand-rolled `init(from:)` below needs it: US-AC05's `patternEmphasis` is an additive top-level
    /// field, so a policy persisted before it must still decode (to `neutralPatternEmphasis`) rather
    /// than failing the whole blob. The raw values are the stored contract, so renaming a case silently
    /// drops that field from every already-stored policy.
    enum CodingKeys: String, CodingKey {
        case version
        case updatedAt
        case updatedBy
        case progressionRate
        case pillarWeighting
        case varietyWindow
        case patternEmphasis
        case coldStartContract
        case reentry
        case note
    }

    /// Decodes a persisted policy, defaulting the US-AC05 `patternEmphasis` lever to neutral when
    /// absent. A policy written before US-AC05 therefore still loads and reproduces the previous engine
    /// behavior exactly (every pattern at a `1.0` staleness multiplier), rather than failing to decode
    /// and losing the user's in-force policy - the same additive round-trip contract the Start Seed
    /// fields honor on `ColdStartContract`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.updatedBy = try container.decode(UpdatedBy.self, forKey: .updatedBy)
        self.progressionRate = try container.decode(Double.self, forKey: .progressionRate)
        self.pillarWeighting = try container.decode([Pillar: Double].self, forKey: .pillarWeighting)
        self.varietyWindow = try container.decode(Int.self, forKey: .varietyWindow)
        self.patternEmphasis =
            try container.decodeIfPresent([MovementPattern: Double].self, forKey: .patternEmphasis)
            ?? Self.neutralPatternEmphasis
        self.coldStartContract =
            try container.decodeIfPresent(ColdStartContract.self, forKey: .coldStartContract)
        self.reentry = try container.decodeIfPresent(Reentry.self, forKey: .reentry)
        self.note = try container.decodeIfPresent(Note.self, forKey: .note)
    }
}

// MARK: - Cold-start seeding (US-G01/US-G02)

extension SessionPolicy.ColdStartContract {

    /// The provisional cold-start Starting Difficulty cap seeded from the user's self-reported
    /// fitness level (US-G01): **beginner 2, intermediate 3, advanced 4**.
    ///
    /// This is a deliberately conservative band, at or below the steady-state difficulty cap the
    /// pool filter applies (`ExercisePoolFilter.difficultyCap`: beginner 1-2, intermediate 1-3,
    /// advanced 1-5) - it tightens only the advanced user (5 -> 4), and matches the others.
    /// The point is not the ceiling alone: the engine serves the *gentle end* of the eligible
    /// band first (US-E04, via Step 5's no-history entry-tier selection), where since US-O02 that
    /// band starts at `startingDifficultyFloor` rather than at the chain's absolute entry tier - so
    /// an over-rated self-report still yields a winnable first session, one tier beneath the cap.
    /// Correction runs in both directions: a too-easy day self-corrects upward through the
    /// Asymmetric Ramp (US-E05) as the user returns, and a `tooHard` rating steps the floor itself
    /// back down a tier within one session (`ColdStartOverride.startSeed`, US-O02).
    static func cappedMaxDifficulty(for level: FitnessLevel) -> Int {
        switch level {
        case .beginner: return 2
        case .intermediate: return 3
        case .advanced: return 4
        }
    }

    /// The cold-start contract seeded at onboarding (US-G01/US-G02/US-O02): `forceContrastSpread`
    /// on so every cold-start day leads strength (US-004, reversing the retired First-Week Contrast
    /// spread), Starting Difficulty capped from the self-reported fitness level (US-G01), and the whole Start Seed -
    /// `startingDifficultyFloor`, `startingRepMultiplier`, `startingSets` - seeded from that same
    /// level (US-O02). The engine reads this in Step 0 and retires it after the handoff (US-G04).
    static func seeded(for level: FitnessLevel) -> Self {
        Self(
            forceContrastSpread: true,
            cappedMaxDifficulty: cappedMaxDifficulty(for: level),
            startingDifficultyFloor: startingDifficultyFloor(for: level),
            startingRepMultiplier: startingRepMultiplier(for: level),
            startingSets: startingSets(for: level)
        )
    }
}

// MARK: - Start Seed (US-O02)

extension SessionPolicy.ColdStartContract {

    /// The Start Seed's difficulty **floor** for a self-reported fitness level (US-O02): **beginner 1,
    /// intermediate 2, advanced 3**.
    ///
    /// Together with `cappedMaxDifficulty` this bands the strength/primal training pool to
    /// `[floor, cap]`, so Step 5's lowest-eligible selection for a no-history user starts at the *band
    /// entry* rather than the chain's absolute entry tier - an active user's first push is a standard
    /// or diamond push-up, not a wall push-up. A beginner's floor is `1`, so the beginner experience is
    /// unchanged.
    ///
    /// The floor is tuned against the library the user can actually *reach*, not the nominal 1-5
    /// difficulty scale. `ExercisePoolFilter` gates `phase == .strength` movements out for every
    /// Discipline-Phase user, so a floor can only ever band against the Discipline catalog - but phase
    /// gates *skills*, not tiers, so that catalog is a real 1-4 range.
    ///
    /// Setting each level's floor to its own cap would collapse the "band" to a single tier, so the
    /// floor sits one tier beneath it, and the catalog has to actually carry both tiers in every
    /// pattern the band reaches. Two gates hold that open, and they are the reason these numbers can
    /// be trusted rather than merely declared:
    /// - `ExerciseLibraryTests.testEveryBandedPatternSpansTwoTiersInsideItsStartBand` - each banded
    ///   pattern offers at least two *difficulties* inside every seeded `[floor, cap]`.
    /// - `ExerciseLibraryTests.testAdvancedStartBandHasRoomToRotate` - and at least two *chains*,
    ///   which is what the variety window actually rotates over.
    ///
    /// The floor is only ever a starting *aim*: banding never starves a movement pattern
    /// (`ColdStartOverride.startBandedPool` clamps the floor down to what a pattern actually offers),
    /// and an over-reported level is corrected downward within one cycle - the Asymmetric Ramp
    /// (US-E05) eases the volume, and `ColdStartOverride.startSeed` steps the *tier* itself back down
    /// on a `too_hard` rating. Only that rating moves the tier: a skipped movement is the product's
    /// escape hatch ("not this one") and eases the volume alone, so a preference tap can never erode a
    /// band that outlives the window. Nothing re-raises the tier the seed lowered either - the only
    /// thing carrying the band past the handoff is `User.ColdStart.bandFloorAtHandoff`, which
    /// `ColdStartHandoff` records *from that same eased seed* on the retiring session and re-resolves
    /// once when that session's own rating lands. The floor below is therefore only ever the starting
    /// aim - what a user is later judged against is the floor their own week ran at.
    static func startingDifficultyFloor(for level: FitnessLevel) -> Int {
        switch level {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        }
    }

    /// The Start Seed's per-set **volume multiplier** for a self-reported fitness level (US-O02):
    /// **beginner x1.0, intermediate x1.15, advanced x1.30**. It scales only the *no-history* default
    /// target (an exercise the user has never logged); once there is demonstrated capacity, Step 6 is
    /// capacity-relative and the seed no longer applies.
    static func startingRepMultiplier(for level: FitnessLevel) -> Double {
        switch level {
        case .beginner: return 1.0
        case .intermediate: return 1.15
        case .advanced: return 1.30
        }
    }

    /// The Start Seed's **set count** for a self-reported fitness level (US-O02): **beginner and
    /// intermediate 3, advanced 4**. Like the multiplier it applies only to a no-history prescription,
    /// and it is clamped to the engine's existing set rails.
    static func startingSets(for level: FitnessLevel) -> Int {
        switch level {
        case .beginner, .intermediate: return 3
        case .advanced: return 4
        }
    }
}

// MARK: - Backward-compatible decoding

extension SessionPolicy.ColdStartContract {

    /// Written out explicitly because the hand-written `init(from:)` below needs them: adding the
    /// synthesized initializer's memberwise decode back would defeat the `decodeIfPresent` fallbacks
    /// the three Start Seed keys rely on. The raw values are the persisted JSON contract, so renaming
    /// a case silently drops that field from every already-stored policy.
    enum CodingKeys: String, CodingKey {
        case forceContrastSpread
        case cappedMaxDifficulty
        case startingDifficultyFloor
        case startingRepMultiplier
        case startingSets
    }

    /// Decodes a persisted contract, defaulting the US-O02 Start Seed fields to their neutral values
    /// when absent. A policy written before US-O02 therefore still loads and reproduces the previous
    /// engine behavior exactly (full band beneath the cap, unscaled targets, 3 sets), rather than
    /// failing to decode and losing the user's in-force policy.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.forceContrastSpread = try container.decode(Bool.self, forKey: .forceContrastSpread)
        self.cappedMaxDifficulty = try container.decode(Int.self, forKey: .cappedMaxDifficulty)
        self.startingDifficultyFloor =
            try container.decodeIfPresent(Int.self, forKey: .startingDifficultyFloor)
            ?? Self.neutralStartingDifficultyFloor
        self.startingRepMultiplier =
            try container.decodeIfPresent(Double.self, forKey: .startingRepMultiplier)
            ?? Self.neutralStartingRepMultiplier
        self.startingSets =
            try container.decodeIfPresent(Int.self, forKey: .startingSets)
            ?? Self.neutralStartingSets
    }
}

extension SessionPolicy {

    /// The starting policy for a freshly onboarded user (US-G01/US-I01): the neutral `default`
    /// levers with a cold-start contract layered on - capping Starting Difficulty from the
    /// self-reported fitness level and forcing the cold-start strength lead (US-004). Every other lever stays
    /// neutral, so once cold-start retires (US-G04 clears the contract) the engine behaves exactly
    /// as `default`. Onboarding calls this with `profile.fitnessLevel`.
    static func seeded(forFitnessLevel level: FitnessLevel) -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.coldStartContract = .seeded(for: level)
        return policy
    }
}
