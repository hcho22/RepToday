import Foundation

/// The post-session wrap-up (US-L01): a pure, template-based summary of what the user actually did
/// and which parts of the body / mobility the session covered.
///
/// It is derived entirely from the finished session's logged exercises, so it can only ever name
/// coverage the session *actually produced* - the same honesty rule the Variety Language line and the
/// policy note follow. There is no XP, no score, and no loss-framing here; the surfacing copy leads
/// with the show-up ("You showed up. That's the whole game."), and this type only supplies the facts
/// that copy is built around.
///
/// Coverage counts every non-skipped exercise the user logged at least one set of - warm-up and
/// cooldown movements included, because they are real mobility work the user moved through. A skipped
/// exercise contributes nothing (it was abandoned), so the coverage never over-claims a movement the
/// user passed on.
struct SessionSummary: Equatable {

    /// Whole minutes actually exercised (wall-clock start to finish), the value the log records as
    /// `durationMinutes` and Default Duration learning reads (US-D02/US-F04).
    let durationMinutes: Int
    /// Total sets the user completed across the session.
    let completedSetCount: Int
    /// Exercises the user completed at least one set of (non-skipped).
    let completedExerciseCount: Int
    /// Exercises the user skipped entirely.
    let skippedExerciseCount: Int
    /// Pillars the session covered (strength / mobility / primal), in canonical order, de-duplicated.
    let pillars: [Pillar]
    /// Movement patterns the session covered, in canonical order, de-duplicated - the "muscle /
    /// mobility" areas the user trained.
    let movementPatterns: [MovementPattern]

    // MARK: - Building

    /// Build the summary from the finished session's logged rows and its completed duration.
    ///
    /// Only non-skipped exercises with at least one completed set count toward coverage and the
    /// completed-exercise tally; skipped exercises feed only `skippedExerciseCount`. Pillars and
    /// patterns are de-duplicated and returned in the canonical enum order so the copy reads the same
    /// way every time (deterministic).
    static func from(loggedExercises: [LoggedExercise], durationMinutes: Int) -> SessionSummary {
        let completed = loggedExercises.filter { !$0.skipped && !$0.completedSets.isEmpty }
        let skipped = loggedExercises.filter { $0.skipped }

        let coveredPillars = Set(completed.map(\.pillar))
        let coveredPatterns = Set(completed.map(\.movementPattern))

        return SessionSummary(
            durationMinutes: durationMinutes,
            completedSetCount: completed.reduce(0) { $0 + $1.completedSets.count },
            completedExerciseCount: completed.count,
            skippedExerciseCount: skipped.count,
            pillars: Pillar.allCases.filter(coveredPillars.contains),
            movementPatterns: MovementPattern.allCases.filter(coveredPatterns.contains)
        )
    }

    // MARK: - Copy

    /// The pillars as human labels, e.g. `["Strength", "Mobility"]`.
    var pillarLabels: [String] { pillars.map(Self.label) }

    /// The movement patterns as human labels, e.g. `["Push", "Squat", "Core"]`.
    var movementLabels: [String] { movementPatterns.map(Self.label) }

    /// A natural-language list of the pillars covered, e.g. "Strength and mobility" or
    /// "Strength, mobility, and primal". Empty when a degenerate session covered nothing.
    var coverageText: String { Self.naturalJoin(pillarLabels) }

    /// A compact list of the movement areas trained, e.g. "Push · Squat · Core". Empty when nothing
    /// was covered.
    var focusText: String { movementLabels.joined(separator: " · ") }

    // MARK: - Formatting

    private static func label(_ pillar: Pillar) -> String {
        switch pillar {
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .primal: return "Primal"
        }
    }

    private static func label(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .push: return "Push"
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .core: return "Core"
        case .pull: return "Pull"
        case .mobility: return "Mobility"
        case .locomotion: return "Locomotion"
        }
    }

    /// Join labels into a natural phrase: "A", "A and B", or "A, B, and C".
    static func naturalJoin(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last!)"
        }
    }
}
