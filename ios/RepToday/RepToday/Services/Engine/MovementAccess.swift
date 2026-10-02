import Foundation

/// The one owner of "may this user get this movement" (ADR-0007), keyed on the self-reported
/// `FitnessLevel` plus the *earned* `Phase`.
///
/// Rep Today builds discipline first, so while a user is in the Discipline Phase a beginner or
/// intermediate user is offered **staple movements** only - the ones most people already know by name
/// (push-ups, squats, planks, bridges) - and an advanced user keeps the full variety. Earning the
/// Strength Phase lifts the restriction for everyone: every movement opens at once. A movement marked
/// `.version2` is withdrawn for every user in every phase until version 2.
///
/// Three rules, applied in this order, and nothing else decides eligibility by movement:
/// 1. **Version 2** - `audience == .version2` is never available.
/// 2. **Phase gate** - a `phase == .strength` skill is available only once the user has earned the
///    Strength Phase (the long-standing US-H02 rule, now one clause of this owner).
/// 3. **Staples** - in the Discipline Phase a movement is available iff the user's level is at or above
///    the movement's `audience`; in the Strength Phase every remaining movement is.
///
/// Every consumer routes through here instead of re-deriving the rule: the eligible pool
/// (`ExercisePoolFilter`, which feeds progression-chain selection, the wide-circuit reserve, the
/// primal block, the bookend stretches and in-session swap), the Start Seed's withheld set, and the
/// read-only Progress surfaces (chain positions, the progression map's locked marking, the strength
/// journey, and through them the Coach's context bundle). Pure and clock-free like the rest of the
/// engine.
enum MovementAccess {

    /// Whether `exercise` may be offered to a user at `level` who has earned `phase`.
    static func isAvailable(_ exercise: Exercise, level: FitnessLevel, phase: Phase) -> Bool {
        let audience = exercise.audience ?? .beginner
        guard audience != .version2 else { return false }
        guard exercise.phase == .discipline || phase == .strength else { return false }
        guard isRestrictedToStaples(level: level, phase: phase) else { return true }
        guard let minimum = audience.minimumLevel else { return false }
        return level.rank >= minimum.rank
    }

    /// Whether this user is held to staple movements: a beginner or intermediate user who has not
    /// earned the Strength Phase. An advanced user keeps the whole catalog, and earning the Strength
    /// Phase lifts the restriction for everyone. Also the audience for the one-time "your sessions now
    /// focus on the classics" note, so the people told their sessions changed are exactly the people
    /// whose sessions are restricted.
    static func isRestrictedToStaples(level: FitnessLevel, phase: Phase) -> Bool {
        phase == .discipline && level != .advanced
    }

    /// `isAvailable(_:level:phase:)` read off a `User`'s onboarding level and earned phase.
    static func isAvailable(_ exercise: Exercise, for user: User) -> Bool {
        isAvailable(exercise, level: user.profile.fitnessLevel, phase: user.phase)
    }

    /// The subset of `library` this user may be offered, in catalog order.
    static func available(in library: [Exercise], level: FitnessLevel, phase: Phase) -> [Exercise] {
        library.filter { isAvailable($0, level: level, phase: phase) }
    }

    /// Whether `exercise` is withdrawn from the app for everyone until version 2.
    static func isWithdrawn(_ exercise: Exercise) -> Bool {
        exercise.audience == .version2
    }

    /// The highest-order rung of a chain this user may get at or below `order`, or - when every
    /// available rung sits above it - the lowest available rung; `nil` when the chain offers this user
    /// nothing at all. This is "the closest movement they do get on the same progression" for a user
    /// whose logged frontier is a movement they no longer receive (ADR-0007), the same clamp
    /// `ProgressionChainSelection.selectInChain` applies to the tier it serves.
    static func closestAvailableRung(
        in chain: [Exercise],
        atOrBelow order: Int,
        level: FitnessLevel,
        phase: Phase
    ) -> Exercise? {
        let available = chain
            .filter { isAvailable($0, level: level, phase: phase) }
            .sorted { $0.progressionOrder < $1.progressionOrder }
        return available.last { $0.progressionOrder <= order } ?? available.first
    }
}
