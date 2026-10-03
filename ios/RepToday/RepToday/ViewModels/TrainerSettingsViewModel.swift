import Foundation

/// Backs the Settings Trainer row (US-TP11): shows the user's effective Trainer and switches it.
///
/// The row shows the effective Trainer - the explicit choice, else the onboarding sex default - and,
/// for a user who answered "other" and has not chosen, a neutral "Not chosen yet" (captain, Open
/// Question 6), never a guessed Trainer. Selecting one writes it as the explicit choice at once through
/// the one Trainer write (`saveTrainerChoice`), which also satisfies the US-TP10 one-time choice; the
/// next exercise card or rest preview re-reads it on arrival.
///
/// A failed write keeps showing the stored Trainer and says the change was not saved (captain, Open
/// Question 8), the way `InjuryFlagsViewModel` does - it never pretends the switch happened.
@Observable
@MainActor
final class TrainerSettingsViewModel {
    /// The Trainer stored for this user right now, or `nil` while unresolved or not yet read.
    private(set) var trainer: Trainer?

    /// True once the stored profile has been read. A failed or empty read leaves it `false`, so the row
    /// stays disabled and the screen's next `.task` reads again.
    private(set) var isLoaded = false

    /// True while a switch is being written.
    private(set) var isSaving = false

    /// A plain failure line when a switch could not be saved. `nil` in the happy path.
    private(set) var errorMessage: String?

    private let userService: any UserServiceProtocol

    init(userService: any UserServiceProtocol) {
        self.userService = userService
    }

    /// The value the row shows: the effective Trainer's name, the neutral unresolved state once a
    /// stored profile has been read, and nothing before then.
    var valueText: String {
        guard isLoaded else { return "" }
        return trainer?.displayName ?? TrainerChoiceCopy.notChosenValue
    }

    /// Read the stored profile. A failed or empty read stays unloaded rather than presenting a profile
    /// it never read as unresolved.
    func load() async {
        guard let user = try? await userService.currentUser() else { return }
        trainer = Trainer.effective(for: user.profile)
        isLoaded = true
    }

    /// Persist `choice` as the explicit Trainer. Shows it only once the write has landed.
    func select(_ choice: Trainer) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let saved = try await userService.saveTrainerChoice(choice)
            trainer = Trainer.effective(for: saved.profile)
        } catch {
            errorMessage = TrainerChoiceCopy.saveFailureMessage
        }
    }
}
