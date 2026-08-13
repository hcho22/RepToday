import Foundation

/// The Return override and the Re-entry Ramp of the deterministic engine (US-E06): the mechanism by
/// which **discipline overrides optimization** after a gap. A user who has been away is never made to
/// feel behind - their first session back is served easy, winnable, and celebrated regardless of the
/// fitness they lost, and the readjustment for that lost time is spread across the following sessions,
/// never loaded onto the Return itself.
///
/// It runs alongside the Step 0 cold-start override (`ColdStartOverride`) and, like it, is a thin
/// override rather than a second engine - it touches the same three pipeline inputs the rest of the
/// pipeline already consumes and leaves everything else to Steps 1-6:
///
/// - **The Return** (a fresh gap detected at generation time, `isReturn`) discipline-overrides Step 2:
///   the day is served easy and winnable *regardless of staleness or the policy's optimization
///   levers*. `overridePlan` leads the session with **strength** (as every session does now, US-005)
///   instead of chasing the stalest pillar; the comeback's gentleness comes not from the pillar but
///   from the two rails that flank it - `returnPool` caps the eligible difficulty so a strong pre-gap
///   history can't serve a punishing tier, and `reentryScale` eases Step 6's volume to the gentle
///   floor. The Return itself carries no readjustment - it is uniformly gentle.
/// - **The Re-entry Ramp** (`sessionPolicy.reentry`, set to `rampSessions` by the Programmer after a
///   Return, US-F03) walks difficulty back up over the sessions that follow: `reentryScale` starts at
///   the same gentle floor and climbs toward neutral as `rampSessionsRemaining` decrements, so the
///   user is eased back to their real level gradually rather than in one jump. Only Step 6's volume is
///   held - the tier and pillar selection resume normally, exactly as the PRD's "Step 6 holds
///   difficulty below normal" describes.
///
/// The Return and the cold-start override are mutually exclusive by construction: the caller gates the
/// Return off while cold-start is active (`ColdStartOverride.isActive`), since cold-start already
/// serves gentle, capped, contrast sessions. Like every other step this is a pure function of its
/// inputs - the "gap" is a calendar-day difference against the injected `asOf`, never a wall-clock
/// read - so it stays deterministic and unit-testable.
enum ReturnOverride {

    // MARK: - Tuning constants

    /// Days of gap since the last completed session past which the next session is served as a Return.
    /// Tunable (PRD provisional `>= 7`); a shorter gap is just a normal session.
    static let returnThresholdDays = 7

    /// Sessions the Re-entry Ramp walks difficulty back up over after a Return (PRD provisional 3).
    /// The Programmer seeds `reentry.rampSessionsRemaining` to this after a Return (US-F03), and it
    /// decrements each session until the ramp retires.
    static let rampSessions = 3

    /// The volume floor a Return (and the start of its Re-entry Ramp) serves at: the eased per-set
    /// target is scaled to this fraction of what Step 6 would otherwise prescribe, so a returning user
    /// gets a clearly gentler, winnable session. The ramp climbs from this floor back to neutral `1.0`.
    static let reentryFloorScale = 0.7

    /// The difficulty ceiling a Return serves beneath: the eligible pool is capped here so a strong
    /// pre-gap history that advanced onto a hard tier can never make the first session back feel
    /// punishing. Served at the gentle end of the band by Step 5's existing selection, as in cold start.
    static let returnMaxDifficulty = 2

    // MARK: - Return detection

    /// Whether the next session is a Return: the gap since the most recent completed session exceeds
    /// `returnThresholdDays`. Pure over `(recentLogs, asOf)` - the gap is a calendar-day difference, no
    /// wall clock. A fresh user with no history is never "returning" (cold start owns their first
    /// sessions), so an empty log set returns `false`.
    ///
    /// This detection is the one seam US-F01's `return` trigger detection also reads, so it lives here
    /// as a pure, reusable function rather than buried inside assembly.
    static func isReturn(recentLogs: [WorkoutLog], asOf: Date, calendar: Calendar = .current) -> Bool {
        guard let gap = daysSinceLastSession(recentLogs: recentLogs, asOf: asOf, calendar: calendar) else {
            return false
        }
        return gap >= returnThresholdDays
    }

    /// Calendar days since the most recent logged session, or `nil` when there is no history. A log is
    /// a show-up (it is only written on completion), so any log - even a fully-skipped one - counts as
    /// the last time the user was here.
    static func daysSinceLastSession(
        recentLogs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar = .current
    ) -> Int? {
        guard let last = recentLogs.map(\.completedAt).max() else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: asOf)
        ).day ?? 0
        return max(0, days)
    }

    // MARK: - Return override (discipline over optimization)

    /// The eligible pool capped for a Return: only movements at or below `returnMaxDifficulty` survive,
    /// so a strong pre-gap history never serves a punishing tier on the first session back. A no-op
    /// when this is not a Return. Mirrors `ColdStartOverride.cappedPool`: if the cap would empty the
    /// pool it returns the uncapped pool rather than break generation.
    static func returnPool(_ pool: [Exercise], isReturn: Bool) -> [Exercise] {
        guard isReturn else { return pool }
        let capped = pool.filter { $0.difficulty <= returnMaxDifficulty }
        return capped.isEmpty ? pool : capped
    }

    /// The pillar plan with the Return override applied: the day is led by **strength** - as every
    /// session is now (US-005) - *regardless of staleness or the policy's optimization levers*, so a
    /// returning user gets a strength-led comeback instead of the stalest, hardest pillar the optimizer
    /// would otherwise chase. A no-op when this is not a Return. Gentleness is preserved by the rails
    /// that flank this choice, not by the pillar: `returnPool`'s difficulty cap and `reentryScale`'s
    /// volume floor keep the strength-led comeback winnable.
    ///
    /// - A single-focus Return trains strength directly.
    /// - A blend Return re-points its shares so strength owns the largest block (it leads and gets the
    ///   most time), preserving the shares' sum-to-1 and every pillar's floor - the other pillars still
    ///   appear, strength simply leads.
    static func overridePlan(_ plan: PillarPlan, isReturn: Bool) -> PillarPlan {
        guard isReturn else { return plan }
        switch plan {
        case .single:
            return .single(.strength)
        case .blend(let weights):
            return .blend(weights.favoring(.strength))
        }
    }

    // MARK: - Re-entry Ramp (Step 6 volume ease)

    /// The Step 6 volume scale for this session: the Return and its Re-entry Ramp hold the per-set
    /// target below what Adaptive Overload would otherwise prescribe, and `1.0` (neutral) otherwise.
    ///
    /// - A **Return** serves the gentle floor (`reentryFloorScale`) - uniformly easy, carrying no
    ///   readjustment.
    /// - An active **Re-entry Ramp** (`reentry.rampSessionsRemaining > 0`, set after a Return) climbs
    ///   from that floor back toward neutral as the counter decrements (`rampScale`).
    /// - Otherwise the ramp is inactive and this is `AdaptiveOverload.neutralReentryScale` (a no-op).
    static func reentryScale(isReturn: Bool, reentry: SessionPolicy.Reentry?) -> Double {
        if isReturn { return reentryFloorScale }
        guard let reentry, reentry.rampSessionsRemaining > 0 else {
            return AdaptiveOverload.neutralReentryScale
        }
        return rampScale(remaining: reentry.rampSessionsRemaining)
    }

    /// The climbing volume scale for a Re-entry Ramp session: the gentle floor when `remaining` is
    /// largest (right after the Return) rising linearly to neutral `1.0` as it decrements to zero, so
    /// difficulty is walked back up over the ramp rather than restored in one jump. `remaining` is
    /// clamped to `0...rampSessions` so an out-of-range counter can never over- or under-shoot.
    static func rampScale(remaining: Int) -> Double {
        let clamped = min(max(remaining, 0), rampSessions)
        return 1.0 - (Double(clamped) / Double(rampSessions)) * (1.0 - reentryFloorScale)
    }
}
