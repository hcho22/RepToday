import Foundation

/// Re-program trigger detection for the on-device AI Programmer (Epic F, US-F01): the pure,
/// deterministic logic that decides, on app open, which `ReprogramTrigger`s are currently due so the
/// Programmer can quietly re-tune the Session Policy without any server clock.
///
/// The Programmer is never on the path between opening the app and starting a session. On open the
/// client asks which triggers are due, re-programs against the highest-precedence one (US-F03), and
/// the freshly written policy applies on the *next* open - the user never waits. This module is only
/// the *detection* half of that seam; the re-weighting it feeds lands in US-F02/US-F03.
///
/// The four triggers it detects, and what each asks the Programmer to do downstream:
/// - **Weekly Boundary** - a new Consistency-Score week has begun since the user last showed up;
///   re-tune against the week just closed.
/// - **Return** - the gap since the last completed session crossed the Return threshold; serve an
///   easy, winnable Return and open the Re-entry Ramp (reuses `ReturnOverride.isReturn`, the single
///   detection seam so the Programmer and the engine can never disagree on what a Return is).
/// - **Physical Stall** - the user has cleared their frontier tier's advancement criteria across
///   several sessions while a real but gated next tier sits just out of reach, so more challenge is
///   warranted (raise `progressionRate`/variety, US-F03). A single-tier or top-of-chain movement has
///   nothing to advance to and never stalls, so routine mobility is not misread as a plateau.
/// - **Disengagement** - the user is completing progressively less of what they request (the
///   requested-vs-completed gap widening, per US-D02) or skips are rising, so friction should be
///   reduced (lower difficulty, shorten sessions, US-F03). Reading the gap - not absolute completed
///   minutes - keeps a user who deliberately requests shorter sessions and finishes them (Default
///   Duration learning) from being misread as pulling away.
///
/// **Trigger Precedence.** When both `physicalStall` and `disengagement` apply, `disengagement` wins
/// and `physicalStall` is suppressed: a user who is pulling away is never handed more challenge. This
/// is the one precedence rule the PRD pins, and it is enforced here at the source so no downstream
/// caller can re-introduce challenge for a disengaging user.
///
/// Like every engine step this is a pure function of its inputs `(user, recentLogs, library, asOf)` -
/// the clock is always passed in as `asOf` and stamped onto each trigger's `detectedAt`, never read
/// from the wall clock inside the logic - so detection stays deterministic and unit-testable. The
/// concrete `SessionPolicyServiceProtocol` (US-F03) supplies the validated `library` from its
/// exercise service and adapts this to the protocol's library-free `dueTriggers(user:recentLogs:asOf:)`.
enum ReprogramTriggerDetection {

    // MARK: - Tuning constants

    /// Distinct recent sessions in which the user must clear their frontier tier's advancement
    /// criteria - without the frontier ever rising - for a Physical Stall to register. Two is
    /// "repeatedly": if the engine could have advanced the user, the second clear would already sit on
    /// a higher tier, so a still-unchanged frontier after two clears means the (existing) next tier is
    /// gated rather than an advance about to happen. A frontier with no next tier at all never stalls
    /// (see `isPhysicallyStalled`).
    static let stallClearedSessions = 2

    /// The window of most-recent completed sessions the Disengagement signal reads. A trend needs a
    /// few sessions to be real, so fewer than this many logs never reads as disengagement.
    static let disengagementWindow = 3

    /// The completion ratio (completed `durationMinutes` over `requestedMinutes`) at or below which
    /// the newest session in a declining run reads as pulling back. Reading the requested-vs-completed
    /// *gap* rather than absolute completed minutes is deliberate (US-D02): a busy-but-engaged user who
    /// deliberately requests shorter sessions and finishes them fully is doing Default Duration
    /// learning, not disengaging, and must not be handed reduced friction.
    static let disengagementCompletionRatio = 0.6

    /// Skip rate across the disengagement window at or above which skips read as "rising". Skips are
    /// counted over the window so one skipped movement in an otherwise-complete session does not
    /// register as pulling away.
    static let disengagementSkipRate = 0.5

    // MARK: - Detection entry point

    /// The re-program triggers due as of `asOf`, in precedence order (highest precedence first).
    ///
    /// Pure and deterministic for a given `(user, recentLogs, library, asOf)`. `library` is the
    /// validated catalog, needed only to resolve advancement criteria and chain position for the
    /// Physical Stall signal; the other three triggers read logs and the injected clock alone.
    ///
    /// Trigger Precedence is enforced here: if `disengagement` is due, `physicalStall` is dropped.
    static func dueTriggers(
        user: User,
        recentLogs: [WorkoutLog],
        library: [Exercise],
        asOf: Date,
        calendar: Calendar = .current
    ) -> [ReprogramTrigger] {
        var kinds: [ReprogramTrigger.Kind] = []

        if weeklyBoundaryDue(recentLogs: recentLogs, asOf: asOf, calendar: calendar) {
            kinds.append(.weeklyBoundary)
        }
        if ReturnOverride.isReturn(recentLogs: recentLogs, asOf: asOf, calendar: calendar) {
            kinds.append(.return)
        }

        let disengaged = isDisengaging(recentLogs: recentLogs)
        let stalled = isPhysicallyStalled(recentLogs: recentLogs, library: library)

        if disengaged {
            kinds.append(.disengagement)
        }
        // Trigger Precedence: Disengagement suppresses Physical Stall - a user who is pulling away is
        // never handed more challenge.
        if stalled && !disengaged {
            kinds.append(.physicalStall)
        }

        return kinds
            .sorted { $0.precedenceRank < $1.precedenceRank }
            .map { ReprogramTrigger(kind: $0, detectedAt: asOf) }
    }

    // MARK: - Weekly Boundary

    /// Whether a new Consistency-Score week has begun since the user last showed up: `asOf` sits in a
    /// strictly later calendar week than the most recent completed session, so there is a just-closed
    /// week to re-tune against. A fresh user with no history has no closed week and never fires this.
    ///
    /// The week grid is the injected `calendar`'s own `weekOfYear` interval (aligned to the
    /// Consistency-Score week US-H01 will share), so alignment respects the calendar's `firstWeekday`
    /// and detection stays deterministic under the injected clock.
    private static func weeklyBoundaryDue(
        recentLogs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar
    ) -> Bool {
        guard
            let last = recentLogs.map(\.completedAt).max(),
            let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: last)?.start,
            let nowWeekStart = calendar.dateInterval(of: .weekOfYear, for: asOf)?.start
        else { return false }
        return nowWeekStart > lastWeekStart
    }

    // MARK: - Disengagement

    /// Whether recent history reads as the user pulling away: over the most recent
    /// `disengagementWindow` completed sessions, either completion is falling short of what was
    /// requested or the skip rate is elevated. Fewer than a full window of sessions is not enough of a
    /// trend to judge, so it reads as engaged. (Lengthening gaps, the third disengagement cue, are
    /// already surfaced by the Return trigger, so this reads the requested-vs-completed gap and rising
    /// skips.)
    private static func isDisengaging(recentLogs: [WorkoutLog]) -> Bool {
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
    /// clamped to `1` so finishing more than requested is fully engaged) forms a non-increasing run
    /// that actually declines and whose newest value has fallen to at most
    /// `disengagementCompletionRatio`.
    ///
    /// This reads the requested-vs-completed *gap*, not absolute completed minutes (US-D02): a user
    /// who deliberately requests shorter sessions (15 -> 10 -> 5 min) and finishes each fully holds a
    /// ratio of `1.0` and never reads as disengaging - that is Default Duration learning. Only a user
    /// bailing on a widening share of what they set out to do pulls this trigger.
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

    /// Whether the user has cleared a frontier tier's advancement criteria repeatedly while a real
    /// next tier they *could* progress to sits just out of reach - "cleared to advance but hasn't"
    /// (US-F02).
    ///
    /// For each chain the user has worked, the *frontier* is the highest-order tier they have worked
    /// (non-skipped) - the same notion Step 5 uses. A stall requires two things:
    /// - The frontier has an **existing next tier** (`progressionId != nil`). A single-tier chain or a
    ///   maxed top-of-chain movement has nothing to advance to, so it is *not* a stall - this is the
    ///   crucial guard that keeps routine mobility (the library's single-tier deep-squat-hold, pigeon,
    ///   cat-cow, ... chains, all with easily-met criteria) from reading as a plateau demanding more
    ///   challenge for a perfectly engaged user.
    /// - That frontier's criteria are cleared in `stallClearedSessions` or more distinct sessions while
    ///   the frontier never rises. Because Step 5 advances a user the session after their criteria are
    ///   met *when the next tier is eligible*, a next tier that exists yet was never reached across two
    ///   clears must be **gated** (phase- or difficulty-locked): the user is genuinely stuck behind a
    ///   gate and warrants more challenge within the tier, not a fresh skill they cannot yet receive.
    ///
    /// Unparseable criteria are never "met", so such a tier never reads as a stall.
    private static func isPhysicallyStalled(recentLogs: [WorkoutLog], library: [Exercise]) -> Bool {
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
}

// MARK: - Precedence

private extension ReprogramTrigger.Kind {

    /// Ordering of due triggers, lowest rank first, so `dueTriggers` returns the highest-precedence
    /// trigger first for the client to re-program against (US-F03). A Return - discipline overriding
    /// optimization - leads; then Disengagement (reduce friction) over Physical Stall (add challenge),
    /// reflecting the same precedence the suppression rule encodes; the routine Weekly Boundary is
    /// last. This is a display/selection order only; the hard suppression of Physical Stall under
    /// Disengagement is enforced in `dueTriggers`, not here.
    var precedenceRank: Int {
        switch self {
        case .return: return 0
        case .disengagement: return 1
        case .physicalStall: return 2
        case .weeklyBoundary: return 3
        }
    }
}
