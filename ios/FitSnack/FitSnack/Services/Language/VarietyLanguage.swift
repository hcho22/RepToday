import Foundation

/// The Variety Language for an early session (US-G03): a short, plain-language line that names what
/// today is and how it differs from yesterday - "Today's a mobility day - yesterday was strength" -
/// so a new user immediately feels the variety wedge from session one.
///
/// This is the **deterministic template** half of the slice, and the source of truth for the
/// contrast: it reads the contrast straight off the engine's own output (the assembled `Workout` and
/// the immediately preceding `WorkoutLog`), so the line can only ever name a contrast the engine
/// *actually produced*. There are no hollow callbacks - no "you're crushing it", no reference to the
/// user's `why` - only the true, mechanical fact of which pillar leads today and which led last time.
///
/// The optional LLM upgrade (via the thin proxy, US-N05) lives in `VarietyLanguageResolver`, which
/// composes this template as its always-available fallback. Every path here is pure and
/// deterministic over its inputs (no clock, no network, no persistence), always offline-safe.
enum VarietyLanguage {

    // MARK: - Contrast

    /// The genuine day-to-day contrast the engine produced: the lead pillar of today's session and,
    /// when it differs, the lead pillar of the immediately preceding one.
    struct SessionContrast: Equatable {
        /// The lead pillar of today's assembled session.
        var today: Pillar
        /// The lead pillar of the immediately preceding session, kept **only** when it differs from
        /// today - the real contrast to name. `nil` when there is no prior session or it led with the
        /// same pillar, so the line never claims a contrast that did not happen.
        var yesterday: Pillar?
    }

    /// The contrast for today's `workout` against `previousLog`, or `nil` when today's session has no
    /// identifiable lead pillar (a degenerate warm-up-only session) - in which case there is nothing
    /// truthful to say and no note is produced.
    static func contrast(for workout: Workout, previousLog: WorkoutLog?) -> SessionContrast? {
        guard let today = leadPillar(of: workout) else { return nil }
        let yesterday = previousLog.flatMap(leadPillar(of:))
        return SessionContrast(today: today, yesterday: yesterday == today ? nil : yesterday)
    }

    // MARK: - Lead pillar

    /// The pillar today's assembled session leads with: the single-focus `focusPillar` when set,
    /// otherwise the first training block's pillar. Blocks are ordered warm-up, then training blocks
    /// staler-pillar-first (US-C07/US-E02), so the first training block is the largest-share lead.
    /// `nil` for a degenerate session with no training block at all.
    static func leadPillar(of workout: Workout) -> Pillar? {
        if let focus = workout.focusPillar { return focus }
        for block in workout.blocks {
            if let pillar = SessionAssembly.pillar(of: block.category) { return pillar }
        }
        return nil
    }

    /// The pillar a completed session led with: the single-focus `focusPillar` when set, otherwise -
    /// for a blend, which records no single focus - the pillar with the most worked (non-skipped)
    /// movements, ties broken by the canonical pillar order so the result is deterministic. `nil` when
    /// nothing was worked.
    static func leadPillar(of log: WorkoutLog) -> Pillar? {
        if let focus = log.focusPillar { return focus }
        var counts: [Pillar: Int] = [:]
        for logged in log.exercises where !logged.skipped {
            counts[logged.pillar, default: 0] += 1
        }
        return Pillar.allCases
            .filter { (counts[$0] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let left = counts[lhs] ?? 0
                let right = counts[rhs] ?? 0
                if left != right { return left > right }
                let lhsRank = Pillar.allCases.firstIndex(of: lhs) ?? 0
                let rhsRank = Pillar.allCases.firstIndex(of: rhs) ?? 0
                return lhsRank < rhsRank
            }
            .first
    }

    // MARK: - Line

    /// The templated Variety Language line for a contrast: names today, and appends the "yesterday
    /// was ..." clause only when there is a genuine, different prior pillar to contrast against.
    static func line(for contrast: SessionContrast) -> String {
        let today = label(for: contrast.today)
        guard let yesterday = contrast.yesterday else {
            return "Today's a \(today) day"
        }
        return "Today's a \(today) day - yesterday was \(label(for: yesterday))"
    }

    /// The user-facing name for a pillar in Variety Language copy. Centralized so the wording is a
    /// single-line change; `primal` uses the product's own first-class vocabulary rather than a term
    /// that would blur into `mobility` ("Movement Practice").
    static func label(for pillar: Pillar) -> String {
        switch pillar {
        case .strength: return "strength"
        case .mobility: return "mobility"
        case .primal: return "primal"
        }
    }

    // MARK: - Note

    /// The templated Variety Language note for today's session against `previousLog`, or `nil` when
    /// today's session has no lead pillar to name. Always `source == .template` - the offline-safe,
    /// never-blocking default the resolver falls back to.
    static func templatedNote(for workout: Workout, previousLog: WorkoutLog?) -> SessionPolicy.Note? {
        guard let contrast = contrast(for: workout, previousLog: previousLog) else { return nil }
        return SessionPolicy.Note(text: line(for: contrast), source: .template)
    }

    /// The templated Variety Language note against the most recent of `recentLogs` (the immediately
    /// preceding session), the same "most recent log" the engine reads its signals from.
    static func templatedNote(for workout: Workout, recentLogs: [WorkoutLog]) -> SessionPolicy.Note? {
        templatedNote(for: workout, previousLog: mostRecent(recentLogs))
    }

    /// The most recently completed log, i.e. the immediately preceding session.
    static func mostRecent(_ logs: [WorkoutLog]) -> WorkoutLog? {
        logs.max { $0.completedAt < $1.completedAt }
    }
}
