import Foundation

/// The illustrated person who demonstrates movements during a session (US-TP03, `CONTEXT.md` ->
/// "Trainer", ADR-0008): a male and a female Trainer, each drawn in a start and an end pose.
///
/// The Trainer only demonstrates; it never talks, advises, or changes a session, and it is distinct
/// from the **Coach**, the premium AI chat. Closed on purpose: there are exactly two Trainers.
enum Trainer: String, Codable, CaseIterable, Identifiable, Hashable {
    case male
    case female

    var id: String { rawValue }

    /// The Trainer's user-facing name - the one copy source every surface (the US-TP10 choice, the
    /// US-TP11 Settings row) reads.
    var displayName: String {
        switch self {
        case .male: return "Male Trainer"
        case .female: return "Female Trainer"
        }
    }

    /// The Trainer the onboarding sex answer defaults to, or `nil` for `.other`, which has no default:
    /// that user chooses once, the first time Trainer art appears (US-TP10).
    static func defaultTrainer(for sex: Sex) -> Trainer? {
        switch sex {
        case .male: return .male
        case .female: return .female
        case .other: return nil
        }
    }

    /// The effective Trainer (FR-6): the explicit choice when one is stored, else the sex default,
    /// else unresolved (`nil`). The one resolution rule - the player, the choice prompt and Settings
    /// all read it, so they can never disagree about which Trainer a user has.
    static func effective(for profile: UserProfile) -> Trainer? {
        profile.trainer ?? defaultTrainer(for: profile.sex)
    }
}

/// Why the Trainer write could not run.
enum TrainerChoiceError: Error, Equatable {
    /// There is no stored user to write the choice onto.
    case noUser
}

extension UserServiceProtocol {
    /// The one write of the explicit Trainer choice (US-TP03, FR-5), used by the US-TP10 choice and the
    /// US-TP11 Settings row and nothing else.
    ///
    /// It re-reads the stored user immediately before saving and changes only `profile.trainer`, so a
    /// caller holding an older snapshot never rolls back what another writer (session completion, a
    /// CloudKit import, the injury control) saved since - the same re-read `InjuryFlagsViewModel` and
    /// `SessionCompletionService` do, because `save(_:)` writes the whole aggregate.
    ///
    /// - Returns: the user as saved.
    @discardableResult
    func saveTrainerChoice(_ trainer: Trainer) async throws -> User {
        guard var user = try await currentUser() else { throw TrainerChoiceError.noUser }
        user.profile.trainer = trainer
        try await save(user)
        return user
    }
}
