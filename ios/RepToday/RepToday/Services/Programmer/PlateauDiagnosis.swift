import Foundation

/// Plateau diagnosis for the on-device AI Programmer (Epic F, US-F02): telling a *physical
/// plateau* (the user has earned an advance but is gated behind it) apart from a *motivation
/// plateau* (the user is pulling away), and mapping each to the Session Policy levers the
/// deterministic re-weighting service (US-F03) writes.
///
/// This is the diagnostic half of the Programmer. `ReprogramTriggerDetection` (US-F01) decides
/// *when* a re-program is due; this module decides *which plateau* recent history shows and
/// *how* the policy should move in response. The two can never disagree about what a stall or a
/// disengagement is, because the plateau predicates live here as the single seam - US-F01's
/// four-trigger detection composes `isPhysicallyStalled`/`isDisengaging` rather than
/// re-deriving them (the same pattern by which US-F01 reuses `ReturnOverride.isReturn`).
///
/// The distinction is the crux of discipline-over-optimization. A physical stall earns *more*
/// challenge - raise `progressionRate`, widen the variety window - so a capable-but-gated user
/// keeps moving forward. Disengagement earns *less friction* - ease `progressionRate`, narrow
/// variety toward the familiar - so a user pulling away is met with a gentler, more winnable
/// program and never with more challenge. When both apply, **Trigger Precedence** resolves it:
/// disengagement wins and the physical stall is suppressed.
///
/// Everything here is a pure function of `(recentLogs, library)` - no wall clock, and no
/// consistency-service call inside the logic (the completion ratio and skip rate it reads *are*
/// the consistency signals, taken straight off the logs per US-D02) - so diagnosis is
/// deterministic and unit-testable, matching the engine's conventions. The `library` is needed
/// only to resolve advancement criteria and chain position for the Physical Stall signal.
enum PlateauDiagnosis {

    // MARK: - Diagnosis

    /// The plateau recent history shows, or `nil` when neither applies.
    ///
    /// Backed by stable snake-case raw values matching the corresponding `ReprogramTrigger.Kind`
    /// cases, so a diagnosis and its trigger read the same on the wire.
    enum Plateau: String, Equatable {
        /// The user has cleared their frontier tier's advancement criteria repeatedly while a
        /// real next tier sits gated just out of reach - add challenge (US-F03).
        case physicalStall = "physical_stall"
        /// The user is completing a shrinking share of what they request, or skipping more -
        /// reduce friction (US-F03).
        case disengagement
    }

    /// Classify recent history as a physical stall, disengagement, or neither.
    ///
    /// **Trigger Precedence** is applied here exactly as in US-F01: when both signals are
    /// present, `disengagement` wins and `physicalStall` is suppressed, so a diagnosis can never
    /// hand more challenge to a user who is pulling away. Pure and deterministic over
    /// `(recentLogs, library)`.
    static func diagnose(recentLogs: [WorkoutLog], library: [Exercise]) -> Plateau? {
        if isDisengaging(recentLogs: recentLogs) { return .disengagement }
        if isPhysicallyStalled(recentLogs: recentLogs, library: library) { return .physicalStall }
        return nil
    }

    // MARK: - Detection tuning constants

    /// Distinct recent sessions in which the user must clear their frontier tier's advancement
    /// criteria - without the frontier ever rising - for a Physical Stall to register. Two is
    /// "repeatedly": if the engine could have advanced the user, the second clear would already
    /// sit on a higher tier, so a still-unchanged frontier after two clears means the (existing)
    /// next tier is gated rather than an advance about to happen. A frontier with no next tier at
    /// all never stalls (see `isPhysicallyStalled`).
    static let stallClearedSessions = 2

    /// The window of most-recent completed sessions the Disengagement signal reads. A trend
    /// needs a few sessions to be real, so fewer than this many logs never reads as
    /// disengagement.
    static let disengagementWindow = 3

    /// The completion ratio (completed `durationMinutes` over `requestedMinutes`) at or below
    /// which the newest session in a declining run reads as pulling back. Reading the
    /// requested-vs-completed *gap* rather than absolute completed minutes is deliberate
    /// (US-D02): a busy-but-engaged user who deliberately requests shorter sessions and finishes
    /// them fully is doing Default Duration learning, not disengaging, and must not be handed
    /// reduced friction.
    static let disengagementCompletionRatio = 0.6

    /// Skip rate across the disengagement window at or above which skips read as "rising". Skips
    /// are counted over the window so one skipped movement in an otherwise-complete session does
    /// not register as pulling away.
    static let disengagementSkipRate = 0.5

    // MARK: - Disengagement

    /// Whether recent history reads as the user pulling away: over the most recent
    /// `disengagementWindow` completed sessions, either completion is falling short of what was
    /// requested or the skip rate is elevated. Fewer than a full window of sessions is not enough
    /// of a trend to judge, so it reads as engaged. (Lengthening gaps, the third disengagement
    /// cue, are already surfaced by the Return trigger, so this reads the requested-vs-completed
    /// gap and rising skips.)
    static func isDisengaging(recentLogs: [WorkoutLog]) -> Bool {
        let window = Array(
            recentLogs
                .sorted { $0.completedAt < $1.completedAt }
                .suffix(disengagementWindow)
        )
        guard window.count >= disengagementWindow else { return false }
        return isCompletionFalling(window) || hasElevatedSkips(window)
    }

    /// Whether the user is completing progressively less of what they ask for across `window`
    /// (oldest -> newest): the per-session completion ratio (`durationMinutes / requestedMinutes`,
    /// clamped to `1` so finishing more than requested is fully engaged) forms a non-increasing
    /// run that actually declines and whose newest value has fallen to at most
    /// `disengagementCompletionRatio`.
    ///
    /// This reads the requested-vs-completed *gap*, not absolute completed minutes (US-D02): a
    /// user who deliberately requests shorter sessions (15 -> 10 -> 5 min) and finishes each
    /// fully holds a ratio of `1.0` and never reads as disengaging - that is Default Duration
    /// learning. Only a user bailing on a widening share of what they set out to do pulls this.
    private static func isCompletionFalling(_ window: [WorkoutLog]) -> Bool {
        let ratios = window.map { log -> Double in
            guard log.requestedMinutes > 0 else { return 1.0 }
            return min(1.0, Double(log.durationMinutes) / Double(log.requestedMinutes))
        }
        guard let first = ratios.first, let last = ratios.last else { return false }
        let nonIncreasing = zip(ratios, ratios.dropFirst()).allSatisfy { $0 >= $1 }
        return nonIncreasing && last < first && last <= disengagementCompletionRatio
    }

    /// Whether the fraction of skipped exercises across `window` reaches `disengagementSkipRate`.
    private static func hasElevatedSkips(_ window: [WorkoutLog]) -> Bool {
        let total = window.reduce(0) { $0 + $1.exercises.count }
        guard total > 0 else { return false }
        let skipped = window.reduce(0) { $0 + $1.exercises.filter(\.skipped).count }
        return Double(skipped) / Double(total) >= disengagementSkipRate
    }

    // MARK: - Physical Stall

    /// Whether the user has cleared a frontier tier's advancement criteria repeatedly while a
    /// real next tier they *could* progress to sits just out of reach - "cleared to advance but
    /// hasn't" (US-F02).
    ///
    /// For each chain the user has worked, the *frontier* is the highest-order tier they have
    /// worked (non-skipped) - the same notion Step 5 uses. A stall requires two things:
    /// - The frontier has an **existing next tier** (`progressionId != nil`). A single-tier chain
    ///   or a maxed top-of-chain movement has nothing to advance to, so it is *not* a stall - the
    ///   crucial guard that keeps routine mobility (the library's single-tier deep-squat-hold,
    ///   pigeon, cat-cow, ... chains, all with easily-met criteria) from reading as a plateau
    ///   demanding more challenge for a perfectly engaged user.
    /// - That frontier's criteria are cleared in `stallClearedSessions` or more distinct sessions
    ///   while the frontier never rises. Because Step 5 advances a user the session after their
    ///   criteria are met *when the next tier is eligible*, a next tier that exists yet was never
    ///   reached across two clears must be **gated** (phase- or difficulty-locked): the user is
    ///   genuinely stuck behind a gate and warrants more challenge within the tier, not a fresh
    ///   skill they cannot yet receive.
    ///
    /// Unparseable criteria are never "met", so such a tier never reads as a stall.
    static func isPhysicallyStalled(recentLogs: [WorkoutLog], library: [Exercise]) -> Bool {
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The frontier exercise per chain: the highest-order tier the user has worked (non-skipped).
        var frontierByChain: [String: Exercise] = [:]
        for log in recentLogs {
            for logged in log.exercises where !logged.skipped {
                guard let exercise = byId[logged.exerciseId] else { continue }
                if let current = frontierByChain[exercise.progressionChainId],
                   current.progressionOrder >= exercise.progressionOrder { continue }
                frontierByChain[exercise.progressionChainId] = exercise
            }
        }

        return frontierByChain.values.contains { frontier in
            // Only a frontier with a real (but unreached, therefore gated) next tier can stall; a
            // single-tier or top-of-chain movement has nowhere to advance and is never a plateau.
            guard frontier.progressionId != nil else { return false }
            guard let criteria = AdvancementCriteria(parsing: frontier.advancementCriteria) else {
                return false
            }
            let clearedSessions = recentLogs.filter { log in
                log.exercises.contains { logged in
                    logged.exerciseId == frontier.id
                        && !logged.skipped
                        && criteria.isMet(by: logged, isHold: frontier.isHold)
                }
            }.count
            return clearedSessions >= stallClearedSessions
        }
    }

    // MARK: - Policy lever mapping

    /// Rails on the two levers this mapping moves, so repeated re-programs can accelerate or ease
    /// but never run a program away. `progressionRate` and `varietyWindow` are the same levers the
    /// engine reads in Steps 6 and 5 (US-E03); these bounds keep them inside their sane operating
    /// range no matter how many times a plateau recurs.
    ///
    /// The `progressionRate` and `varietyWindow` bounds alias `SessionPolicy`'s centralized rails (US-AC06,
    /// US-AC07), so the deterministic Programmer's easing floors/ceilings and the coach's easing gates share
    /// one definition and can never drift apart. (The values are unchanged: rate `[0.5, 2.0]`, window
    /// `[1, 6]`.)
    static let maxProgressionRate = SessionPolicy.maxProgressionRate
    static let minProgressionRate = SessionPolicy.minProgressionRate
    static let maxVarietyWindow = SessionPolicy.maxVarietyWindow
    static let minVarietyWindow = SessionPolicy.minVarietyWindow

    /// A physical stall earns more challenge: progression accelerates by `stallProgressionBoost`
    /// and the variety window widens by `stallVarietyWiden` (fresher movement, less repetition).
    static let stallProgressionBoost = 1.15
    static let stallVarietyWiden = 1

    /// Disengagement earns less friction: progression eases by `disengagementProgressionEase`
    /// (lower difficulty) and the variety window narrows by `disengagementVarietyNarrow` (toward
    /// the familiar). The *session-length* half of "less friction" - shorter sessions - is
    /// delivered by Default Duration learning (US-F04), which drops `duration.defaultMinutes` as
    /// the user completes less; the Session Policy carries no session-length lever, so this
    /// mapping does not fabricate one.
    static let disengagementProgressionEase = 0.85
    static let disengagementVarietyNarrow = 1

    /// Re-level `policy` for `plateau`, moving only the affected levers within the rails and
    /// leaving `version`/`updatedBy`/`note`/persistence to the re-weighting service (US-F03).
    ///
    /// The mapping is intentionally explicit and total:
    /// - `.physicalStall` -> `progressionRate *= stallProgressionBoost` (clamped to
    ///   `maxProgressionRate`) and `varietyWindow += stallVarietyWiden` (clamped to
    ///   `maxVarietyWindow`): a capable-but-gated user advances faster and sees fresher movement.
    /// - `.disengagement` -> `progressionRate *= disengagementProgressionEase` (clamped to
    ///   `minProgressionRate`) and `varietyWindow -= disengagementVarietyNarrow` (clamped to
    ///   `minVarietyWindow`): lower difficulty and less novelty for a user pulling away.
    ///
    /// Disengagement never raises `progressionRate` and never widens the variety window (Trigger
    /// Precedence upheld at the lever level, per US-F03): a disengaging user is never handed more
    /// challenge. Applied to `SessionPolicy.default` (progression `1.0`, window `3`), a stall
    /// yields `~1.15`/`4` and a disengagement `~0.85`/`2`, both strictly inside the rails.
    static func reweighted(_ policy: SessionPolicy, for plateau: Plateau) -> SessionPolicy {
        var next = policy
        switch plateau {
        case .physicalStall:
            next.progressionRate = min(policy.progressionRate * stallProgressionBoost, maxProgressionRate)
            next.varietyWindow = min(policy.varietyWindow + stallVarietyWiden, maxVarietyWindow)
        case .disengagement:
            next.progressionRate = max(policy.progressionRate * disengagementProgressionEase, minProgressionRate)
            next.varietyWindow = max(policy.varietyWindow - disengagementVarietyNarrow, minVarietyWindow)
        }
        return next
    }
}
