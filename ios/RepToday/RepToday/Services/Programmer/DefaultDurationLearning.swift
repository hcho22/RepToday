import Foundation

/// Default Duration learning for the on-device AI Programmer (Epic F, US-F04): keeping the
/// Ready Screen's default session length honest to what the user *actually finishes*, not what
/// they ask for.
///
/// `User.Duration` carries three fields (US-D01): `onboardingSeedMinutes` (the one-time answer),
/// `completedDurationEWMA` (the running exponentially-weighted average of completed durations the
/// Programmer maintains here), and `defaultMinutes` (what the Ready Screen offers). This module
/// folds newly-completed session durations into the EWMA and snaps `defaultMinutes` to it, so a
/// user who keeps requesting 20-minute sessions but only finishes ~12 has their default drift to
/// 10 or 15 - the app "knows them" without ever being told.
///
/// Reading completed `durationMinutes` rather than `requestedMinutes` is deliberate (US-D02): the
/// requested-vs-completed gap is exactly the signal a shorter default should close, and it is the
/// same gap the Disengagement diagnosis reads - a user who *intentionally* requests shorter
/// sessions and finishes them fully is learning their duration here, not pulling away there.
///
/// Everything is a pure, deterministic function of its inputs - no wall clock, no persistence -
/// matching the engine's conventions. The re-weighting service (US-F03) folds the sessions logged
/// since the last re-program through `learned(_:completing:)` and persists the result; the double-
/// counting concern (folding a session more than once) is the caller's to avoid by supplying only
/// newly-completed durations, the same way `coldStart.sessionsLogged` increments once per session.
enum DefaultDurationLearning {

    // MARK: - Tuning constants

    /// The EWMA smoothing factor (alpha) applied to each newly-completed duration. At `0.3` the
    /// average leans toward recent behavior while still smoothing out a single anomalous session,
    /// so the default moves deliberately rather than snapping to every outlier.
    static let smoothingFactor = 0.3

    /// The valid Ready-Screen duration chips, ascending (US-C01/US-E01 session-shape buckets). The
    /// learned `defaultMinutes` is always one of these - the Ready Screen offers chips, not
    /// arbitrary minute values - and the ascending order makes chip snapping's tie-break (below)
    /// resolve to the shorter, gentler chip.
    static let chipValues = [5, 10, 15, 20, 30, 45, 60]

    // MARK: - Learning

    /// Fold newly-completed session durations (chronological, oldest -> newest) into the running
    /// EWMA and re-derive the snapped `defaultMinutes`.
    ///
    /// The EWMA's prior is the existing `completedDurationEWMA` when present, otherwise the
    /// `onboardingSeedMinutes` - so learning is anchored to the user's stated preference until real
    /// completed-session evidence accrues, never a cold surprise. Each duration then updates the
    /// average by `ewma = alpha * completed + (1 - alpha) * ewma`. `defaultMinutes` is snapped to
    /// the nearest chip; `onboardingSeedMinutes` is never touched (it is the historical seed).
    ///
    /// An empty input leaves the duration unchanged (nothing new to learn from), so the call is a
    /// no-op when no sessions have been completed since the last re-program.
    static func learned(_ duration: User.Duration, completing completedDurations: [Int]) -> User.Duration {
        guard !completedDurations.isEmpty else { return duration }

        var ewma = duration.completedDurationEWMA ?? Double(duration.onboardingSeedMinutes)
        for completed in completedDurations {
            ewma = smoothingFactor * Double(completed) + (1 - smoothingFactor) * ewma
        }

        var next = duration
        next.completedDurationEWMA = ewma
        next.defaultMinutes = snappedToChip(ewma)
        return next
    }

    /// Convenience over `learned(_:completing:)`: fold the completed `durationMinutes` of
    /// `recentLogs` (sorted by `completedAt`). The caller supplies the logs it treats as newly
    /// completed since the last re-program.
    static func learned(_ duration: User.Duration, from recentLogs: [WorkoutLog]) -> User.Duration {
        let completed = recentLogs
            .sorted { $0.completedAt < $1.completedAt }
            .map(\.durationMinutes)
        return learned(duration, completing: completed)
    }

    // MARK: - Chip snapping

    /// Snap a minute value to the nearest valid Ready-Screen chip. A value exactly between two
    /// chips resolves to the shorter one: `chipValues` is ascending and `min(by:)` keeps the first
    /// element when distances tie, so a boundary session length lands on the gentler default.
    static func snappedToChip(_ minutes: Double) -> Int {
        chipValues.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) } ?? chipValues[0]
    }
}
