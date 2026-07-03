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
    struct ColdStartContract: Codable, Equatable {
        /// Force a vivid day-to-day pillar spread (First-Week Contrast), overriding the
        /// single-theme bias that `why`/`sitsLong` alone would produce.
        var forceContrastSpread: Bool
        /// Hard difficulty cap for cold-start sessions, in `1...5`. The engine serves at the
        /// gentle end of the eligible band beneath this cap so a mis-reported fitness level
        /// never yields a badly over-hard first day.
        var cappedMaxDifficulty: Int
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
