import Foundation

/// A Coach-written workout the user reviewed, edited and accepted (M4, US-CA04/US-CA05, decision 27,
/// `CONTEXT.md` "Custom Workout").
///
/// It is a separate artifact from the engine's sessions, never a `SessionPolicy` write (ADR-0017,
/// Two-Writer Policy Safety unchanged):
///
/// - **Nothing plays until it is accepted** (FR-11). A proposal lives only in the Coach conversation;
///   a `CustomWorkout` exists only once the user tapped Accept, and only an accepted one can be played.
/// - **Any movement is allowed.** A step naming a served catalog movement (`exerciseId`) shows its
///   Trainer art; any other step is text only and is never tracked.
/// - **It counts like an Outside Activity** and never advances progression. A played Custom Workout is
///   recorded as an `OutsideActivity` (`CustomWorkoutCompletionRecorder`), never a `WorkoutLog`, so it
///   counts as showing up and gives the group it worked at least a day off (FR-8, `trainedGroup`), but
///   no ladder, Earned Reps, Foundation or Training Day ever reads it.
///
/// Stored on the device (`CDCustomWorkout`, the Local store) and synced to the account like every
/// other record (M3), so the Coach can see what was accepted and played.
struct CustomWorkout: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var note: String
    var steps: [CustomWorkoutStep]
    /// The Coach message and proposal it came from, so the conversation can show it was accepted.
    var messageId: String?
    var proposalId: String?
    var createdAt: Date
    /// When the user accepted it. Only an accepted workout can play.
    var acceptedAt: Date?
    /// Every time it was played to the end.
    var playedAt: [Date] = []

    var isAccepted: Bool { acceptedAt != nil }
}

/// One step of a Custom Workout.
struct CustomWorkoutStep: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// A served catalog movement, or `nil` for a text-only step.
    var exerciseId: String?
    var sets: Int
    /// Reps per set, for a rep step.
    var reps: Int?
    /// Seconds per set, for a timed step.
    var seconds: Int?
    var perSide: Bool
    var restSeconds: Int

    var isTimed: Bool { seconds != nil }
}

extension CustomWorkout {
    /// The bounds the editor keeps every step inside, matching what the Coach may write.
    static let setRange = 1...6
    static let repRange = 1...100
    static let secondsRange = 5...300
    static let restRange = 0...180
    static let maxSteps = 12

    /// Builds the reviewable workout from the Coach's draft. Not yet accepted.
    init(draft: CustomWorkoutDraft, messageId: String?, proposalId: String?, library: [Exercise], now: Date) {
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.init(
            id: UUID(),
            title: draft.title,
            note: draft.note,
            steps: draft.steps.prefix(Self.maxSteps).map { step in
                let catalog = step.exerciseId.flatMap { byId[$0] }
                // A catalog hold is timed and a catalog rep movement counts reps, whatever the draft said.
                let timed = catalog?.isHold ?? (step.seconds != nil)
                return CustomWorkoutStep(
                    id: UUID(),
                    name: catalog?.displayName ?? step.name,
                    exerciseId: catalog?.id,
                    sets: step.sets.clamped(to: Self.setRange),
                    reps: timed ? nil : (step.reps ?? catalog?.defaultReps ?? 10).clamped(to: Self.repRange),
                    seconds: timed ? (step.seconds ?? catalog?.defaultDurationSeconds ?? 30).clamped(to: Self.secondsRange) : nil,
                    perSide: catalog.map { $0.isPerSide == true } ?? step.perSide,
                    restSeconds: step.restSeconds.clamped(to: Self.restRange)
                )
            },
            messageId: messageId,
            proposalId: proposalId,
            createdAt: now,
            acceptedAt: nil
        )
    }

    /// The Training Day group a played Custom Workout gives at least one day off (FR-8, ADR-0017).
    ///
    /// The rule: count the working sets of its **catalog** steps by the group their movement pattern
    /// belongs to (push -> Push; pull -> Pull; squat and hinge -> Legs). The group with strictly the most
    /// sets is the one it worked. Core, mobility and text-only steps count toward no group, and a tie -
    /// a full-body workout split evenly - or a workout with no grouped catalog steps names no group, so
    /// the Rotation is left alone, exactly as an "other" Outside Activity leaves it. Like every Outside
    /// Activity it never completes a group.
    func trainedGroup(library: [Exercise]) -> TrainingDay? {
        let patterns = Dictionary(library.map { ($0.id, $0.movementPattern) }, uniquingKeysWith: { first, _ in first })
        var sets: [TrainingDay: Int] = [:]
        for step in steps {
            guard let id = step.exerciseId, let pattern = patterns[id],
                  let day = TrainingDay.allCases.first(where: { $0.patterns.contains(pattern) }) else { continue }
            sets[day, default: 0] += step.sets
        }
        guard let top = sets.max(by: { $0.value < $1.value }) else { return nil }
        return sets.values.filter { $0 == top.value }.count == 1 ? top.key : nil
    }

    /// About how long it takes, in whole minutes: every set's work (reps at the app's generous pace,
    /// both sides of a per-side step) plus its rest.
    var estimatedMinutes: Int {
        let seconds = steps.reduce(0) { total, step in
            let sides = step.perSide ? 2 : 1
            let work = step.seconds ?? Int((Double(step.reps ?? 10) * Self.secondsPerRep).rounded(.up))
            return total + step.sets * (work * sides + step.restSeconds)
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// The pace the estimate allows per rep, in seconds.
    private static let secondsPerRep = 3.0

    /// The prefix of the id a text-only step plays under, so the player shows it as text rather than
    /// guessing a picture.
    static let textOnlyExerciseIdPrefix = "custom."

    static func isTextOnly(exerciseId: String) -> Bool {
        exerciseId.hasPrefix(textOnlyExerciseIdPrefix)
    }

    /// The workout as the hands-free player plays it (US-CA05): one circuit block of its steps, in the
    /// user's order, with the player's own work windows, holds and rests - no tap after start. A catalog
    /// step plays as its catalog movement (so it shows Trainer art); a text-only step plays under a
    /// `custom.` id the player shows as text. It carries no Training Day and no station roles, and it is
    /// never logged as a session (`CustomWorkoutCompletionRecorder`).
    func playableWorkout(library: [Exercise], now: Date) -> Workout {
        let exercises = prescriptions(library: library)
        return Workout(
            id: UUID(),
            createdAt: now,
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: estimatedMinutes,
            blocks: [
                WorkoutBlock(id: UUID(), title: title, category: .strength, exercises: exercises, transitionSeconds: 15),
            ]
        )
    }

    /// Each step as the player prescribes it - the one shape the app's target copy
    /// (`ActiveSessionView.targetText`) and the Trainer art read, so the card, the editor and the player
    /// describe a step the same way.
    func prescriptions(library: [Exercise]) -> [PrescribedExercise] {
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return steps.map { step in
            let exercise = step.exerciseId.flatMap { byId[$0] } ?? Self.textOnlyExercise(for: step)
            return PrescribedExercise(
                id: step.id,
                exercise: exercise,
                sets: step.sets,
                reps: step.isTimed ? nil : step.reps,
                durationSeconds: step.seconds,
                restSeconds: step.restSeconds
            )
        }
    }

    private static func textOnlyExercise(for step: CustomWorkoutStep) -> Exercise {
        Exercise(
            id: textOnlyExerciseIdPrefix + step.id.uuidString.lowercased(),
            displayName: step.name,
            pillar: .strength,
            movementPattern: .core,
            category: .strength,
            difficulty: 1,
            phase: .discipline,
            equipment: [],
            isHold: step.isTimed,
            defaultReps: step.reps,
            defaultDurationSeconds: step.seconds,
            isPerSide: step.perSide,
            estimatedTimePerSetSeconds: step.seconds ?? Int((Double(step.reps ?? 10) * secondsPerRep).rounded(.up)),
            metValue: 3.5,
            progressionChainId: "custom",
            progressionOrder: 0,
            advancementCriteria: "",
            apartmentFriendly: true
        )
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
