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
/// The two *plateau* signals - Physical Stall and Disengagement - are detected by
/// `PlateauDiagnosis` (US-F02), the single seam that owns plateau logic and maps each plateau to
/// the policy levers the re-weighting service writes. This module composes those predicates so
/// detection and diagnosis can never disagree; it owns only the Weekly Boundary and delegates the
/// Return to `ReturnOverride`.
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

        // The plateau signals are owned by `PlateauDiagnosis` (US-F02), the single seam so
        // detection and diagnosis can never disagree about what a stall or disengagement is.
        let disengaged = PlateauDiagnosis.isDisengaging(recentLogs: recentLogs)
        let stalled = PlateauDiagnosis.isPhysicallyStalled(recentLogs: recentLogs, library: library)

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
