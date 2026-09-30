import Foundation

/// The four strength **foundations** the Strength Phase is earned through: Push, Pull, Legs, Core
/// (ADR-0006, and the "Foundation" term in `CONTEXT.md`).
///
/// This is the one domain definition of the foundation set. The Strength-Phase gate
/// (`PhaseEvaluator`), the Progress tab, the premium strength-journey analytics, the Coach's
/// requestable emphasis words, and the Coach's analytics insights all read it, so none of them keeps a
/// private copy of the list that could drift from the gate.
///
/// A foundation is deliberately **not** a `MovementPattern`. Movement patterns are the engine's
/// staleness/variety buckets and stay exactly as they were; a foundation is what the *user* is asked to
/// clear. Most foundations are a single movement pattern, but **Legs** groups two - Squat and Hinge -
/// and is cleared only when both are, so a user cannot earn Strength on quads alone.
enum StrengthFoundation: String, CaseIterable, Identifiable, Hashable {
    case push
    case pull
    case legs
    case core

    var id: String { rawValue }

    /// The order every surface lists foundations in: Push, Pull, Legs, Core.
    static var displayOrder: [StrengthFoundation] { allCases }

    var displayName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }

    /// The lines of progress that must all clear for this foundation to clear, in display order.
    /// Push, Pull and Core have one; Legs has two (Squat, then Hinge).
    var lines: [FoundationLine] {
        switch self {
        case .push: return [FoundationLine(foundation: self, pattern: .push)]
        case .pull: return [FoundationLine(foundation: self, pattern: .pull, countingChainIds: [FoundationLine.pullCountingChainId])]
        case .legs: return [
            FoundationLine(foundation: self, pattern: .squat),
            FoundationLine(foundation: self, pattern: .hinge),
        ]
        case .core: return [FoundationLine(foundation: self, pattern: .core)]
        }
    }

    /// Every line across every foundation, in display order - the five lines (Push, Pull, Squat,
    /// Hinge, Core) that the progress and analytics surfaces track.
    static let allLines: [FoundationLine] = allCases.flatMap(\.lines)

    /// The movement patterns that belong to some foundation (push, pull, squat, hinge, core).
    static let foundationPatterns: Set<MovementPattern> = Set(allLines.map(\.pattern))

    /// The line a movement pattern belongs to, or `nil` for a pattern that is no foundation's
    /// (mobility, locomotion). Every pattern belongs to at most one line.
    static func line(for pattern: MovementPattern) -> FoundationLine? {
        allLines.first { $0.pattern == pattern }
    }
}

/// One line of progress inside a foundation: a movement pattern, and the progression chains of that
/// pattern whose entry rung counts toward clearing the foundation.
///
/// Push, Pull and Core are single-line foundations; **Legs** has a Squat line and a Hinge line, and
/// clears only when both do. The Progress tab shows each line with its own tick, current movement,
/// ladder and dated climb; the premium analytics and Coach insights track the same lines.
struct FoundationLine: Hashable, Identifiable {

    /// The horizontal Pull chain - the only Pull chain that counts (Wall Scapular Pull, Supine Floor
    /// Row, Single-Arm Supine Floor Row). The postural chain (Superman Hold, Reverse Snow Angel,
    /// Prone Y-T-W Raises) stays in sessions as accessory and prehab work but never clears Pull.
    static let pullCountingChainId = "pull_horizontal"

    let foundation: StrengthFoundation
    let pattern: MovementPattern

    /// The chains whose entry rung counts, or `nil` when every chain of the pattern counts (a
    /// foundation line clears on any one of its counting chains' entry rung).
    let countingChainIds: Set<String>?

    init(foundation: StrengthFoundation, pattern: MovementPattern, countingChainIds: Set<String>? = nil) {
        self.foundation = foundation
        self.pattern = pattern
        self.countingChainIds = countingChainIds
    }

    var id: MovementPattern { pattern }

    /// Whether `exercise` is a movement on one of this line's counting chains.
    func counts(_ exercise: Exercise) -> Bool {
        guard exercise.movementPattern == pattern else { return false }
        guard let countingChainIds else { return true }
        return countingChainIds.contains(exercise.progressionChainId)
    }

    /// The entry rung (lowest `progressionOrder`) of each counting chain in `library`. The line is
    /// cleared when a logged, non-skipped performance of any one of these meets its advancement
    /// criteria.
    func entryExercises(in library: [Exercise]) -> [Exercise] {
        let chains = Dictionary(grouping: library.filter(counts), by: \.progressionChainId)
        return chains.keys.sorted().compactMap { chainId in
            chains[chainId]?.min { $0.progressionOrder < $1.progressionOrder }
        }
    }

    /// Whether this line is one of several inside its foundation (only Legs' Squat and Hinge).
    var isSideOfSharedFoundation: Bool { foundation.lines.count > 1 }

    /// The short name of the line: "Push", "Pull", "Squat", "Hinge", "Core".
    var displayName: String {
        switch pattern {
        case .push: return "Push"
        case .pull: return "Pull"
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .core: return "Core"
        case .mobility: return "Mobility"
        case .locomotion: return "Locomotion"
        }
    }

    /// The name a surface gives the line beside its siblings: "Squat side" for a shared foundation,
    /// the plain name for a single-line foundation.
    var sideLabel: String {
        isSideOfSharedFoundation ? "\(displayName) side" : displayName
    }

    /// The name VoiceOver speaks for the line: "Legs, squat side" or "Push".
    var spokenName: String {
        isSideOfSharedFoundation ? "\(foundation.displayName), \(displayName.lowercased()) side" : displayName
    }
}
