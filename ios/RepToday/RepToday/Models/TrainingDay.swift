import Foundation

// MARK: - TrainingDay

/// One group of the fixed **Push -> Pull -> Legs** rotation (ADR-0012, `CONTEXT.md` "Training Day").
///
/// A Training Day trains one group only: a Push Day push, a Pull Day pull, a Legs Day squat and hinge.
/// Its only extras are the Core Sprinkle and the warm-up and cooldown bookends. The raw value is the
/// stored form.
enum TrainingDay: String, Codable, CaseIterable, Identifiable, Hashable {
    case push
    case pull
    case legs

    var id: String { rawValue }

    /// The rotation order. A Cycle is one pass through it.
    static let rotation: [TrainingDay] = [.push, .pull, .legs]

    /// The movement patterns this day trains. Groups never share a pattern, so a log's stations name
    /// exactly one day.
    var patterns: Set<MovementPattern> {
        switch self {
        case .push: return [.push]
        case .pull: return [.pull]
        case .legs: return [.squat, .hinge]
        }
    }

    /// The day's ladders (`progressionChainId`s) in their canonical order, the tie-break when two are
    /// equally due. Push and Pull have two each, so their third and fourth main slots are Practice
    /// Movements; a Legs Day uses all four of its ladders' current rungs.
    var ladders: [String] {
        switch self {
        case .push: return ["push_horizontal", "push_vertical"]
        case .pull: return ["pull_horizontal", "pull_postural"]
        case .legs: return ["squat", "lunge", "hinge_bridge", "hinge_hip"]
        }
    }

    /// The line under Today's title: what the day works, in the user's words.
    var focusLine: String {
        switch self {
        case .push: return "Push work for chest, shoulders and arms."
        case .pull: return "Pull work for your back and posture."
        case .legs: return "Squats, lunges and hinges for legs and glutes."
        }
    }

    /// The name Today and the player show.
    var displayName: String {
        switch self {
        case .push: return "Push Day"
        case .pull: return "Pull Day"
        case .legs: return "Legs Day"
        }
    }
}

// MARK: - StationRole

/// What a station does in a session (US-TD02). Carried on the prescription and copied onto the log, so
/// progression can tell earned work from a preview: only `main` and `core` stations move a rung or the
/// Rep Ramp (`LoggedExercise.countsForProgression`).
enum StationRole: String, Codable, CaseIterable, Hashable {
    /// The current rung of one of the day's ladders.
    case main
    /// A Practice Movement: the next harder rung at low reps (or, with none, the rung below at volume
    /// reps). It never advances progression (ADR-0015).
    case practice
    /// The Core Sprinkle.
    case core
    /// A stretch in the Recovery flow offered on a Rest Day (US-TD05).
    case recovery
}
