import Foundation

/// Pipeline Step 2 of the deterministic engine (US-C02): balance the training pillars by
/// staleness so the neglected pillar gets worked and the pillars stay in balance.
///
/// Step 1 picks the session's *shape*; Step 2 decides *which pillar(s)* fill it:
/// - A single-focus session (the short 5-10 min lengths) always trains **strength** (US-001):
///   strength is the pillar of every single-focus session, and mobility survives only as the
///   structural warm-up at these lengths, not as a training block.
/// - A short/full blend is **strength-led** too (US-002): strength takes the leading share of the
///   training time (~75-80%) and mobility is a small minority accessory block on top of the
///   structural warm-up/cooldown - never the lead. `sitsLong` only modulates the *size* of that
///   mobility accessory (a desk worker earns a little more relief for their postural debt), never
///   which pillar leads. Strength-vs-mobility staleness no longer picks the lead; staleness now
///   steers movement-pattern focus *within* the strength family (Step 3) instead.
/// - An extended blend (US-E02) promotes `primal` to a first-class pillar: mobility stays the
///   minority accessory and the leading strength family (strength + primal) is split *within
///   itself* by staleness, so the longest sessions earn a dedicated primal block while strength
///   still leads (US-002).
///
/// "Staleness" is days-since-last-worked, read back from `recentLogs`. The computation is a
/// pure function of the logs and a caller-supplied reference date (`asOf`) - no hidden clock -
/// so it stays deterministic and testable, mirroring Step 1. Staleness (and the per-pillar
/// `pillarWeighting` Session Policy lever, US-E02/US-E03) now only leans the split *within* the
/// strength family - the strength-vs-primal share of an extended blend - never the strength-vs-mobility
/// lead, which is a fixed strength-dominant envelope (US-002). The neutral weighting (`1.0` for every
/// pillar) is a no-op there, so the default policy reproduces the pre-policy within-family split exactly.

// MARK: - PillarStaleness

/// Days since each pillar was last worked, derived from completed (non-skipped) exercises in
/// `recentLogs`. A pillar absent from `daysSinceWorked` was never worked in the supplied logs;
/// callers treat that as maximally stale.
///
/// Only completed work counts - an exercise the user skipped did not train its pillar. Day
/// counts are calendar-day differences (worked yesterday -> 1), not raw elapsed time.
struct PillarStaleness: Equatable {
    /// Per-pillar days since last worked. An absent key means "never worked in `recentLogs`".
    let daysSinceWorked: [Pillar: Int]

    init(recentLogs: [WorkoutLog], asOf: Date, calendar: Calendar = .current) {
        var lastWorked: [Pillar: Date] = [:]
        for log in recentLogs {
            let workedPillars = Set(
                log.exercises.filter { !$0.skipped }.map(\.pillar)
            )
            for pillar in workedPillars {
                if let existing = lastWorked[pillar], existing >= log.completedAt {
                    continue
                }
                lastWorked[pillar] = log.completedAt
            }
        }

        let today = calendar.startOfDay(for: asOf)
        var days: [Pillar: Int] = [:]
        for (pillar, date) in lastWorked {
            let elapsed = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: today
            ).day ?? 0
            days[pillar] = max(0, elapsed)
        }
        self.daysSinceWorked = days
    }

    /// Days since `pillar` was last worked, or `nil` if it was never worked in the logs.
    func days(for pillar: Pillar) -> Int? {
        daysSinceWorked[pillar]
    }

    /// Whether `a` is strictly staler than `b`, treating "never worked" (`nil`) as the most
    /// stale value of all.
    static func isStaler(_ a: Int?, than b: Int?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (lhs?, rhs?): return lhs > rhs
        }
    }
}

// MARK: - PillarPlan

/// The pillar makeup Step 2 selects for a session: one pillar for single-focus, or a
/// staleness-weighted split across the pillars for a blend.
enum PillarPlan: Equatable {
    /// Single-focus: train exactly this one pillar.
    case single(Pillar)
    /// Blend: train two pillars - or all three for an extended blend - with time apportioned by `weights`.
    case blend(PillarWeights)

    // MARK: Tuning constants

    /// Staleness is capped here when leaning the within-family (strength-vs-primal) split of an
    /// extended blend, so one long gap (or a never-worked pillar) can lean the split without starving
    /// the other of all its time.
    static let maxStalenessDays = 14
    /// The floor (and, by symmetry, ceiling) on the mobility accessory's share of a blend, so mobility
    /// is always a genuine minority accessory yet can never grow into the lead. 0.2 -> mobility keeps
    /// 20-80% of the time, and the strength-dominant envelope (US-002) sits it near the floor.
    static let minBlendShare = 0.2

    /// Mobility's minority-accessory share of a blend's training time for an **active** user
    /// (`profile.sitsLong == false`). Strength leads every blend (US-002); mobility is a small
    /// accessory block on top of the structural warm-up/cooldown, so the base is deliberately near the
    /// `minBlendShare` floor. At `0.2` an active user's blend runs ~80% strength / 20% mobility, inside
    /// the ~0.75-0.80 strength target band.
    static let baseMobilityAccessoryShare = 0.2

    /// Extra mobility accessory a **sedentary** (desk-worker) user gets on top of
    /// `baseMobilityAccessoryShare` - the recast of the old `activeUserStrengthBias` as a modulation of
    /// the *mobility accessory's size*, not a lead selector (US-002, FR-5). A desk worker carries more
    /// postural debt, so they earn a little more mobility relief; an active user gets the base. At
    /// `0.05` a sedentary blend runs ~75% strength / 25% mobility - still a strength lead and inside the
    /// ~0.75-0.80 target band. It can never flip the lead: even at the accessory's `minBlendShare`
    /// ceiling mobility stays a minority.
    static let sitsLongMobilityAccessoryBoost = 0.05

    /// The floor and ceiling on **primal**'s share *of the strength family* (strength + primal) in an
    /// extended blend (US-E02). The family keeps the leading share (`1 - mobility accessory`); primal's
    /// slice of it scales with weighted staleness between these bounds, so a stale (or policy-favored)
    /// primal earns a bigger dedicated block. The ceiling stays below `0.5` so strength keeps the
    /// majority of the family and always leads; the floor keeps primal a genuinely-trained block.
    static let extendedPrimalFamilyFloor = 0.2
    static let extendedPrimalFamilyCap = 0.45

    /// Selects the pillar makeup for a session (pipeline Step 2).
    ///
    /// - Parameters:
    ///   - template: the Step 1 shape; single-focus picks one pillar, a short/full blend leads strength
    ///     with a mobility minority accessory (US-002), and an extended blend adds a dedicated primal
    ///     block carved from the leading strength family (US-E02).
    ///   - recentLogs: completed sessions, the source of per-pillar staleness (which now leans only the
    ///     within-family strength-vs-primal split of an extended blend, US-002).
    ///   - profile: supplies `sitsLong`, which modulates the *size* of a blend's mobility accessory
    ///     (never the lead pillar, US-002 FR-5).
    ///   - pillarWeighting: the Session Policy per-pillar staleness multiplier (US-E02/US-E03);
    ///     defaults to neutral (`1.0` each). It leans only the extended blend's within-family
    ///     strength-vs-primal split now, never the strength-vs-mobility lead (US-002). The engine
    ///     threads the live policy's weighting through `SessionAssembly.assemble` (US-E03).
    ///   - asOf: the reference "today" staleness is measured against (injected for purity).
    ///   - calendar: calendar used for day-difference math; defaults to the current calendar.
    static func select(
        template: SessionShapeTemplate,
        recentLogs: [WorkoutLog],
        profile: UserProfile,
        pillarWeighting: [Pillar: Double] = SessionPolicy.neutralPillarWeighting,
        asOf: Date,
        calendar: Calendar = .current
    ) -> PillarPlan {
        let staleness = PillarStaleness(recentLogs: recentLogs, asOf: asOf, calendar: calendar)
        switch template {
        case .singleFocus:
            return .single(singlePillar())
        case .blendLight, .blendFull:
            return .blend(blendWeights(
                staleness: staleness,
                weighting: pillarWeighting,
                sitsLong: profile.sitsLong,
                includePrimal: false
            ))
        case .blendExtended:
            return .blend(blendWeights(
                staleness: staleness,
                weighting: pillarWeighting,
                sitsLong: profile.sitsLong,
                includePrimal: true
            ))
        }
    }

    // MARK: Single-focus selection

    /// Picks the one pillar a single-focus session trains: always **strength** (US-001).
    ///
    /// Strength is the pillar of every single-focus session, independent of staleness or the
    /// desk-worker (`sitsLong`) signal. Mobility is not a training option here - it survives only
    /// as the structural warm-up every session opens with. This makes strength-primary structural
    /// at the short lengths rather than an emergent outcome of the staleness math, so a short
    /// session can never resolve to an all-mobility block.
    private static func singlePillar() -> Pillar {
        .strength
    }

    // MARK: Blend weighting

    /// Splits a blend's time so **strength always leads** and mobility is a minority accessory (US-002).
    ///
    /// Mobility's share is a small, fixed accessory (`mobilityAccessoryShare`) - independent of
    /// strength-vs-mobility staleness, so staleness can never make mobility lead. `sitsLong` only
    /// modulates the accessory's *size* (a desk worker gets `sitsLongMobilityAccessoryBoost` more relief),
    /// never the lead (FR-5). A two-pillar blend (`includePrimal == false`) hands the whole leading share
    /// to strength (primal is folded into the strength block downstream, as before), landing strength in
    /// the ~0.75-0.80 target band.
    ///
    /// A three-pillar extended blend (`includePrimal == true`, US-E02) keeps the same minority mobility
    /// accessory and carves a dedicated primal block out of the leading **strength family** (strength +
    /// primal). Only the split *within* that family responds to weighted staleness: a stale (or
    /// policy-favored) primal earns a bigger slice, bounded by `[extendedPrimalFamilyFloor,
    /// extendedPrimalFamilyCap]` so strength keeps the majority of the family and still leads. The three
    /// shares always sum to `1`.
    private static func blendWeights(
        staleness: PillarStaleness,
        weighting: [Pillar: Double],
        sitsLong: Bool,
        includePrimal: Bool
    ) -> PillarWeights {
        let mobilityShare = mobilityAccessoryShare(sitsLong: sitsLong)

        guard includePrimal else {
            // Two-pillar blend: strength takes the entire leading share; primal folds into it downstream.
            return PillarWeights(strength: 1 - mobilityShare, mobility: mobilityShare, primal: 0)
        }

        // Extended blend: the strength family keeps the leading share; only the strength-vs-primal split
        // *inside* it responds to staleness/policy weighting, never overtaking strength.
        let familyBudget = 1 - mobilityShare
        let strengthStale = weightedStaleness(.strength, staleness: staleness, weighting: weighting)
        let primalStale = weightedStaleness(.primal, staleness: staleness, weighting: weighting)
        let denom = strengthStale + primalStale
        let primalFraction = denom == 0 ? 0.5 : primalStale / denom
        let primalFamilyShare = extendedPrimalFamilyFloor
            + (extendedPrimalFamilyCap - extendedPrimalFamilyFloor) * primalFraction
        let primalShare = familyBudget * primalFamilyShare
        return PillarWeights(
            strength: familyBudget - primalShare,
            mobility: mobilityShare,
            primal: primalShare
        )
    }

    /// Mobility's minority-accessory share of a blend's training time: `baseMobilityAccessoryShare`
    /// for an active user, plus `sitsLongMobilityAccessoryBoost` for a desk worker (`sitsLong`), clamped
    /// into `[minBlendShare, 1 - minBlendShare]`. Always a minority, so strength keeps the lead (US-002).
    private static func mobilityAccessoryShare(sitsLong: Bool) -> Double {
        let raw = baseMobilityAccessoryShare + (sitsLong ? sitsLongMobilityAccessoryBoost : 0)
        return min(1 - minBlendShare, max(minBlendShare, raw))
    }

    /// A pillar's staleness as a bounded Double, scaled by its policy weight: never-worked maps
    /// to the cap (maximally stale) and any longer real gap is clamped to the cap too, then the
    /// per-pillar `weighting` multiplier (neutral `1.0` by default) leans the split.
    private static func weightedStaleness(
        _ pillar: Pillar,
        staleness: PillarStaleness,
        weighting: [Pillar: Double]
    ) -> Double {
        cappedStaleness(staleness.days(for: pillar)) * (weighting[pillar] ?? 1.0)
    }

    /// Staleness as a bounded Double: never-worked maps to the cap (maximally stale), and any
    /// longer real gap is clamped to the cap too.
    private static func cappedStaleness(_ days: Int?) -> Double {
        Double(min(days ?? maxStalenessDays, maxStalenessDays))
    }
}

// MARK: - PillarWeights

/// A blend's time split across the pillars. The three shares always sum to `1`; the downstream
/// assembly step (US-C07/US-E02) turns these fractions into actual block time.
///
/// For a two-pillar blend `primal == 0` (primal is folded into the strength block, as before)
/// and `strength + mobility == 1`. For an extended blend (US-E02) `primal > 0` earns a dedicated
/// primal block and all three shares are positive.
struct PillarWeights: Equatable {
    var strength: Double
    var mobility: Double
    var primal: Double = 0
}

extension PillarWeights {
    /// The canonical pillar order the share swaps below iterate in, so ties for the max share resolve
    /// deterministically (strength, then mobility, then primal).
    private static let order: [Pillar] = [.strength, .mobility, .primal]

    /// Re-points the shares so `lead` owns the largest share (its block leads and gets the most time),
    /// by swapping the lead's share with whichever pillar currently holds the max. This preserves the
    /// exact multiset of shares, so they still sum to 1 and every pillar keeps its floor - the emphasis
    /// is reordered, never a pillar starved. Used by both the cold-start First-Week Contrast
    /// (`ColdStartOverride`) and the Return override (`ReturnOverride`) to lead a blend with a chosen
    /// pillar. A no-op when `lead` is not part of this blend (share 0, e.g. primal in a short blend) or
    /// already leads.
    func favoring(_ lead: Pillar) -> PillarWeights {
        let shares: [Pillar: Double] = [.strength: strength, .mobility: mobility, .primal: primal]
        guard (shares[lead] ?? 0) > 0 else { return self }

        var maxPillar = PillarWeights.order[0]
        for pillar in PillarWeights.order where (shares[pillar] ?? 0) > (shares[maxPillar] ?? 0) {
            maxPillar = pillar
        }
        guard maxPillar != lead else { return self }

        var result = shares
        result[lead] = shares[maxPillar]
        result[maxPillar] = shares[lead]
        return PillarWeights(
            strength: result[.strength] ?? 0,
            mobility: result[.mobility] ?? 0,
            primal: result[.primal] ?? 0
        )
    }
}
