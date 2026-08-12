import Foundation

/// Pipeline Step 2 of the deterministic engine (US-C02): balance the training pillars by
/// staleness so the neglected pillar gets worked and the pillars stay in balance.
///
/// Step 1 picks the session's *shape*; Step 2 decides *which pillar(s)* fill it:
/// - A single-focus session (the short 5-10 min lengths) always trains **strength** (US-001):
///   strength is the pillar of every single-focus session, and mobility survives only as the
///   structural warm-up at these lengths, not as a training block.
/// - A short/full blend trains strength and mobility (primal folded into strength), splitting
///   time toward whichever is staler.
/// - An extended blend (US-E02) promotes `primal` to a first-class pillar, splitting time
///   three ways so the longest sessions earn a dedicated primal block instead of folding
///   primal into strength.
///
/// "Staleness" is days-since-last-worked, read back from `recentLogs`. The computation is a
/// pure function of the logs and a caller-supplied reference date (`asOf`) - no hidden clock -
/// so it stays deterministic and testable, mirroring Step 1. Staleness is further scaled by a
/// per-pillar `pillarWeighting` (the Session Policy lever, US-E02/US-E03): a heavier weight on a
/// pillar increases its share of the session. The neutral weighting (`1.0` for every pillar) is
/// a no-op, so the default policy reproduces pre-policy behavior exactly.

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

    /// Staleness is capped here when weighting a blend, so one long gap (or a never-worked
    /// pillar) can lean the split without starving the other pillar of all its time.
    static let maxStalenessDays = 14
    /// The floor (and, by symmetry, ceiling) on either pillar's share of a two-pillar blend, so
    /// both pillars are always genuinely trained. 0.3 -> each pillar gets 30-70% of the time.
    static let minBlendShare = 0.3
    /// The floor on each pillar's share of a three-pillar extended blend (US-E02), so strength,
    /// mobility, and primal are all genuinely trained; the remaining share is apportioned by
    /// weighted staleness. 0.2 -> each pillar keeps at least 20% and shares sum to 1.
    static let minExtendedBlendShare = 0.2

    /// Extra multiplier applied to the **strength** pillar's weighted staleness in a *blend* for an
    /// **active** user - one whose onboarding answer to "Do you sit 6+ hours most days?" is *no*
    /// (`profile.sitsLong == false`). It biases their blended sessions to spend proportionally more
    /// time (and therefore more movements) on strength.
    ///
    /// A sedentary user's blend split is left unbiased, while an active user - who is not
    /// accumulating the postural debt a desk worker does - is nudged toward strength instead. The
    /// sedentary path is untouched (bias `1.0`), so this *adds* a strength bias for the active case
    /// without altering the sedentary split. (Single-focus sessions always train strength for every
    /// user under US-001, so there is no longer a single-focus mobility lean this mirrors.)
    ///
    /// `1.0` would be no bias. At `1.5`, an otherwise-even blend (equal staleness, e.g. a no-history
    /// user) shifts from a 50/50 strength/mobility split to 60/40 in strength's favor - noticeably
    /// more strength-forward without making mobility disappear (both stay well inside the
    /// `minBlendShare` rails). It is deliberately a single, isolated constant so the magnitude is easy
    /// to retune later without touching the sedentary path or the staleness math.
    static let activeUserStrengthBias = 1.5

    /// Selects the pillar makeup for a session (pipeline Step 2).
    ///
    /// - Parameters:
    ///   - template: the Step 1 shape; single-focus picks one pillar, a short/full blend splits
    ///     strength and mobility, and an extended blend splits all three pillars (US-E02).
    ///   - recentLogs: completed sessions, the source of per-pillar staleness.
    ///   - profile: supplies `sitsLong`, which biases a blend's split toward strength for active users.
    ///   - pillarWeighting: the Session Policy per-pillar staleness multiplier (US-E02/US-E03);
    ///     defaults to neutral (`1.0` each) so pre-policy behavior is reproduced exactly. The
    ///     engine threads the live policy's weighting through `SessionAssembly.assemble` (US-E03).
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

    /// Splits a blend's time across its pillars by relative (policy-weighted) staleness, clamped
    /// so every pillar keeps a meaningful share.
    ///
    /// A two-pillar blend (`includePrimal == false`) splits strength and mobility 30-70% either
    /// way with primal at `0` (primal is folded into the strength block downstream, as before).
    /// A three-pillar extended blend (`includePrimal == true`, US-E02) also apportions primal:
    /// every pillar keeps at least `minExtendedBlendShare` and the remainder is divided by
    /// weighted staleness, so the shares always sum to `1`. Equal staleness (including no
    /// history) splits evenly.
    ///
    /// For an **active** user (`sitsLong == false`) strength's weighted staleness is scaled up by
    /// `activeUserStrengthBias`, biasing the split toward strength; a desk worker's split is left
    /// unbiased.
    private static func blendWeights(
        staleness: PillarStaleness,
        weighting: [Pillar: Double],
        sitsLong: Bool,
        includePrimal: Bool
    ) -> PillarWeights {
        let strengthBias = sitsLong ? 1.0 : activeUserStrengthBias
        let strength = weightedStaleness(.strength, staleness: staleness, weighting: weighting) * strengthBias
        let mobility = weightedStaleness(.mobility, staleness: staleness, weighting: weighting)

        guard includePrimal else {
            let total = strength + mobility
            let rawMobilityShare = total == 0 ? 0.5 : mobility / total
            let mobilityShare = min(1 - minBlendShare, max(minBlendShare, rawMobilityShare))
            return PillarWeights(strength: 1 - mobilityShare, mobility: mobilityShare, primal: 0)
        }

        let primal = weightedStaleness(.primal, staleness: staleness, weighting: weighting)
        let total = strength + mobility + primal
        let floor = minExtendedBlendShare
        let free = 1 - 3 * floor
        func share(_ weight: Double) -> Double {
            total == 0 ? (1.0 / 3.0) : floor + free * (weight / total)
        }
        return PillarWeights(
            strength: share(strength),
            mobility: share(mobility),
            primal: share(primal)
        )
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
