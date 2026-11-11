import Foundation
import Observation

/// Backs the Settings editor for Focus Areas (US-HO02, decision 20).
///
/// The choice is staged on screen and written with **Save**, onto a fresh read of the user so a write
/// from elsewhere (a completed session, the injury control) is never rolled back. Focus Areas are a
/// preference, never a safety filter, so an empty selection is a complete answer.
@MainActor
@Observable
final class FocusAreasViewModel {

    /// The selection on screen.
    var selection: Set<FocusArea> = []

    /// The Focus Areas the stored profile carries, once loaded.
    private(set) var saved: Set<FocusArea> = []

    private(set) var isLoaded = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// Whether the selection on screen differs from what is stored.
    var hasChanges: Bool { isLoaded && selection != saved }

    private let userService: any UserServiceProtocol

    init(userService: any UserServiceProtocol) {
        self.userService = userService
    }

    /// Read the stored Focus Areas. Idempotent: once loaded, a re-run (SwiftUI may run a screen's
    /// `.task` again) never wipes a staged change.
    func load() async {
        guard !isLoaded else { return }
        do {
            guard let user = try await userService.currentUser() else {
                errorMessage = FocusAreasCopy.loadFailed
                return
            }
            saved = Set(user.profile.focusAreas)
            selection = saved
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = FocusAreasCopy.loadFailed
        }
    }

    func toggle(_ area: FocusArea) {
        guard isLoaded else { return }
        if selection.contains(area) { selection.remove(area) } else { selection.insert(area) }
    }

    /// Write the selection onto a fresh read of the user. Returns `true` when it was saved (or there
    /// was nothing to save), so the screen can say so and Today can rebuild.
    @discardableResult
    func save() async -> Bool {
        guard isLoaded, !isSaving else { return false }
        guard hasChanges else { return true }
        isSaving = true
        defer { isSaving = false }
        do {
            guard var user = try await userService.currentUser() else {
                errorMessage = FocusAreasCopy.saveFailed
                return false
            }
            user.profile.focusAreas = selection.canonicallyOrdered
            try await userService.save(user)
            saved = selection
            errorMessage = nil
            return true
        } catch {
            errorMessage = FocusAreasCopy.saveFailed
            return false
        }
    }
}
