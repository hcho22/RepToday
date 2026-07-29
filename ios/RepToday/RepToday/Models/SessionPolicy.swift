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

    /// Per-pillar multiplier on staleness in Step 2 (US-E03). Neutral is `1.0` for every
    /// pillar (equal weighting); a heavier weight measurably increases that pillar's share of
    /// session time. Always carries every pillar (`strength`/`mobility`/`primal`).
    var pillarWeighting: [Pillar: Double]

    /// The no-repeat variety window Step 5 honors (US-E03), replacing the engine's previously
    /// hardcoded `recentSessionWindow = 3` so it is tunable per user.
    var varietyWindow: Int

    /// The cold-start override contract, present only during the cold-start window (US-E04):
    /// it forces First-Week Contrast and caps Starting Difficulty. `nil` once the engine
    /// retires cold-start (US-G04), after which Step 0 is a no-op.
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
        /// Force a vivid day-to-day pillar spread (First-Week Contrast), overriding the
        /// single-theme bias that `why`/`sitsLong` alone would produce.
        var forceContrastSpread: Bool
        /// Hard difficulty cap for cold-start sessions, in `1...5`. The engine serves at the
        /// gentle end of the eligible band beneath this cap so a mis-reported fitness level
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
        coldStartContract: nil,
        reentry: nil,
        note: nil
    )
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
    /// band first (US-E04, via Step 5's no-history entry-tier selection), so an over-rated
    /// self-report still yields a winnable first session. Correction is left to the Asymmetric
    /// Ramp (US-E05) - a too-easy day self-corrects upward as the user returns, while a too-hard
    /// day is prevented up front.
    static func cappedMaxDifficulty(for level: FitnessLevel) -> Int {
        switch level {
        case .beginner: return 2
        case .intermediate: return 3
        case .advanced: return 4
        }
    }

    /// The cold-start contract seeded at onboarding (US-G01/US-G02): First-Week Contrast forced on
    /// so the first week visibly spans strength/mobility/primal (US-G02), and Starting Difficulty
    /// capped from the self-reported fitness level (US-G01). The engine reads this in Step 0 and
    /// retires it after the handoff (US-G04).
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
    /// self-reported fitness level and forcing First-Week Contrast. Every other lever stays
    /// neutral, so once cold-start retires (US-G04 clears the contract) the engine behaves exactly
    /// as `default`. Onboarding calls this with `profile.fitnessLevel`.
    static func seeded(forFitnessLevel level: FitnessLevel) -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.coldStartContract = .seeded(for: level)
        return policy
    }
}
