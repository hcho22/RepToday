import Foundation

/// A reason the AI Programmer (Epic F) should rewrite the Session Policy, detected
/// deterministically on app open (US-D04 seam; US-F01 detection).
///
/// The Programmer never runs on the critical path of starting a session. Instead, on open the
/// client asks `SessionPolicyServiceProtocol.dueTriggers(...)` which triggers are due,
/// re-programs against the highest-precedence one, and the freshly written policy applies on
/// the *next* open - the user never waits on programming.
///
/// Detection is pure and deterministic for a given `(user, recentLogs, asOf)`: the clock is
/// always passed in as `asOf` and stamped onto `detectedAt`, never read from the wall clock
/// inside the logic (US-F01), matching the engine's time-injection convention.
struct ReprogramTrigger: Equatable, Codable, Identifiable {

    /// Why a re-program is due.
    ///
    /// Backed by a stable `String` raw value: a trigger may be persisted or logged, so the raw
    /// values are a contract (renaming one silently breaks stored/analyzed data). The case
    /// *names* may be refactored freely; the raw *values* must not change.
    enum Kind: String, Codable, CaseIterable, Identifiable, Equatable {
        /// A new Consistency-Score week has begun; re-tune against the week just closed.
        case weeklyBoundary = "weekly_boundary"
        /// The user is back after a gap; serve an easy, winnable Return and open a Re-entry
        /// Ramp (US-E06).
        case `return`
        /// Advancement criteria cleared repeatedly without advancing - add challenge (US-F02).
        /// Suppressed by `disengagement` under Trigger Precedence (US-F01).
        case physicalStall = "physical_stall"
        /// Sessions shrinking, skips rising, gaps lengthening - reduce friction (US-F02).
        /// Wins over `physicalStall` under Trigger Precedence (US-F01).
        case disengagement

        var id: String { rawValue }
    }

    /// Why this trigger fired.
    var kind: Kind

    /// When it was detected - stamped from the injected `asOf` clock, never a wall-clock read
    /// inside detection, so detection stays deterministic.
    var detectedAt: Date

    /// A stable identity for SwiftUI iteration: at most one trigger of each kind is due at a
    /// given moment, so the kind's raw value identifies it within a `dueTriggers` result.
    var id: String { kind.rawValue }

    init(kind: Kind, detectedAt: Date) {
        self.kind = kind
        self.detectedAt = detectedAt
    }
}
