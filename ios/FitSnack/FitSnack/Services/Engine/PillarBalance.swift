import Foundation

/// Pipeline Step 2 of the deterministic engine (US-C02): balance the training pillars by
/// staleness so the neglected pillar gets worked and the pillars stay in balance.
///
/// Step 1 picks the session's *shape*; Step 2 decides *which pillar(s)* fill it:
/// - A single-focus session trains exactly one pillar - the stalest - with a desk-worker
///   lean toward mobility for same-day relief on short sessions.
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

    /// Days of neglect past which strength is "strongly stale" and reclaims a short
    /// single-focus session from the desk-worker mobility lean. Tunable.
    static let strengthNeglectThresholdDays = 5
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

    /// Selects the pillar makeup for a session (pipeline Step 2).
    ///
    /// - Parameters:
    ///   - template: the Step 1 shape; single-focus picks one pillar, a short/full blend splits
    ///     strength and mobility, and an extended blend splits all three pillars (US-E02).
    ///   - recentLogs: completed sessions, the source of per-pillar staleness.
    ///   - profile: supplies `sitsLong`, the desk-worker mobility lean.
    ///   - pillarWeighting: the Session Policy per-pillar staleness multiplier (US-E02/US-E03);
    ///     defaults to neutral (`1.0` each) so pre-policy behavior is reproduced exactly. The
    ///     engine passes the live policy's weighting once US-E03 threads it through `assemble`.
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
            return .single(singlePillar(staleness: staleness, sitsLong: profile.sitsLong))
        case .blendLight, .blendFull:
            return .blend(blendWeights(staleness: staleness, weighting: pillarWeighting, includePrimal: false))
        case .blendExtended:
            return .blend(blendWeights(staleness: staleness, weighting: pillarWeighting, includePrimal: true))
        }
    }

    // MARK: Single-focus selection

    /// Picks the one pillar a single-focus session trains.
    ///
    /// Without a desk-sitting signal it is simply the stalest pillar, with ties going to
    /// strength (the documented no-signal default). For a desk worker it leans mobility for
    /// same-day relief, unless strength has been neglected past the strong-staleness
    /// threshold - then the neglected strength reclaims the session.
    private static func singlePillar(staleness: PillarStaleness, sitsLong: Bool) -> Pillar {
        let strengthDays = staleness.days(for: .strength)
        let mobilityDays = staleness.days(for: .mobility)

        guard sitsLong else {
            return PillarStaleness.isStaler(mobilityDays, than: strengthDays) ? .mobility : .strength
        }

        let strengthStronglyStale = strengthDays.map { $0 >= strengthNeglectThresholdDays } ?? true
        if strengthStronglyStale && PillarStaleness.isStaler(strengthDays, than: mobilityDays) {
            return .strength
        }
        return .mobility
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
    private static func blendWeights(
        staleness: PillarStaleness,
        weighting: [Pillar: Double],
        includePrimal: Bool
    ) -> PillarWeights {
        let strength = weightedStaleness(.strength, staleness: staleness, weighting: weighting)
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
