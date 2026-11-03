import Foundation

/// The explicit engine input behind the Ready Screen's **Different workout** button.
///
/// A press asks the engine for the same-length session built from other moves. The engine stays a pure
/// function of its inputs, so the request has to be spelled out rather than drawn from a random source:
/// a variation is the set of exercise ids the earlier presses of the current sequence already put on
/// screen (`offeredExerciseIds`). `SessionAssembly` ranks those moves *behind* the alternatives at every
/// choice point - which strength patterns lead, which chain each pattern draws from, and which stretches
/// fill the warm-up and cooldown - exactly as the variety window ranks a recently worked movement behind a
/// fresh one. It is a preference, never a filter: movement access, injury flags, progression frontiers,
/// the Start Seed band, the round cap, even-round timing and the timing fit all still decide every pick.
///
/// The sequence cycles. Each press that shows anything new adds at least one id to the set, so a sequence
/// is finite; once a press can produce no move outside the set, the engine serves the default session
/// (`SessionAssembly.assemble`), and the next press starts the sequence again from it
/// (`advanced(past:)`). The same inputs and the same number of presses therefore always give the same
/// workout.
///
/// It lives only in memory on the Ready Screen. Nothing persists it, and a workout that is never started
/// writes no log, so a press never counts toward variety, progression or the Consistency Score.
struct SessionVariation: Equatable {
    /// The moves the earlier presses of this sequence already showed. Empty means "no press": the
    /// default session, byte-for-byte what the engine built before this input existed.
    let offeredExerciseIds: Set<String>

    init(offeredExerciseIds: Set<String>) {
        self.offeredExerciseIds = offeredExerciseIds
    }

    /// The default session - no press yet.
    static let none = SessionVariation(offeredExerciseIds: [])

    /// Whether this is the default request.
    var isNone: Bool { offeredExerciseIds.isEmpty }

    /// The variation for the next press, given the workout the user is looking at.
    ///
    /// Normally the shown moves are added to the set. When the shown workout held nothing outside the set,
    /// it is the default session the engine fell back to after the alternatives ran out, so the sequence
    /// starts again from it: the next press avoids only what is on screen now.
    func advanced(past shown: Workout) -> SessionVariation {
        let shownIds = Self.exerciseIds(in: shown)
        if !isNone, shownIds.isSubset(of: offeredExerciseIds) {
            return SessionVariation(offeredExerciseIds: shownIds)
        }
        return SessionVariation(offeredExerciseIds: offeredExerciseIds.union(shownIds))
    }

    /// Whether `workout` shows at least one move this variation has not already offered.
    func offersSomethingNew(_ workout: Workout) -> Bool {
        !Self.exerciseIds(in: workout).isSubset(of: offeredExerciseIds)
    }

    /// Every exercise id a workout prescribes, across all its blocks.
    static func exerciseIds(in workout: Workout) -> Set<String> {
        Set(workout.blocks.flatMap(\.exercises).map(\.exercise.id))
    }
}
