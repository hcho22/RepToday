import Foundation

/// The player's Trainer for one session (US-TP06/US-TP10): which Trainer's art the exercise card and
/// rest overlay show, and whether the one-time choice must be asked first.
///
/// It starts from the profile the player was handed, then - on arrival - re-reads the stored user, so a
/// Trainer switched in Settings (US-TP11) or a choice made on an earlier arrival is what this session
/// shows even when the Ready Screen's snapshot predates it. The choice is asked only when a user exists
/// and their effective Trainer is unresolved (`Trainer.effective(for:)` is `nil`: a "other" answer with
/// no stored choice). A male or female answer, or any stored choice, never sees it.
///
/// A choice is used for this session the moment it is made, then written through the one Trainer write
/// (`saveTrainerChoice`). If that write fails, the session keeps the chosen Trainer and the prompt is
/// dismissed anyway (captain, Open Question 8); because nothing was persisted, the next arrival's
/// re-read finds the Trainer still unresolved and asks again - and never once a choice is stored.
@MainActor
@Observable
final class TrainerSessionModel {
    /// The Trainer whose art this session shows, or `nil` while unresolved (the art falls back to the
    /// movement glyph until a Trainer is chosen, so no Trainer is ever guessed).
    private(set) var trainer: Trainer?

    /// Whether the user has a stored profile at all. A host with no user (a preview or an evidence
    /// surface) never asks.
    private var hasUser: Bool

    private let userService: (any UserServiceProtocol)?

    init(profile: UserProfile?, userService: (any UserServiceProtocol)?) {
        self.trainer = profile.flatMap(Trainer.effective(for:))
        self.hasUser = profile != nil
        self.userService = userService
    }

    /// Whether the choice must be asked right now: a user exists and has no effective Trainer.
    var needsChoice: Bool { hasUser && trainer == nil }

    /// Re-read the stored user so this session follows the freshest Trainer, then report whether the
    /// one-time choice must be asked. A failed or empty read keeps what the player was handed.
    func refreshOnArrival() async -> Bool {
        if let userService, let fresh = try? await userService.currentUser() {
            trainer = Trainer.effective(for: fresh.profile)
            hasUser = true
        }
        return needsChoice
    }

    /// Use `choice` for this session at once, then persist it as the explicit choice in the background.
    ///
    /// The Trainer changes synchronously, so the art appears for the chosen Trainer the moment the
    /// choice is made; the returned task resolves to whether the write landed. A failure leaves `trainer`
    /// set for this session only.
    @discardableResult
    func choose(_ choice: Trainer) -> Task<Bool, Never> {
        trainer = choice
        let userService = userService
        return Task {
            guard let userService else { return false }
            do {
                try await userService.saveTrainerChoice(choice)
                return true
            } catch {
                return false
            }
        }
    }
}
