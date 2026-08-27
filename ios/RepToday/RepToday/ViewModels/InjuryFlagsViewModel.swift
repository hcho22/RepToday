import Foundation
import Observation

/// Backs the injury control (US-AC08) - the one place in the app where a safety filter is turned on or
/// off after onboarding.
///
/// It exists because `UserProfile.injuries` was written once during onboarding and never again, so
/// "flag my knee" and "actually, my knee's fine now" had nowhere to happen. The coach routes here; it
/// never writes. So does Settings, and both reach the *same* control.
///
/// Two properties make the write honest:
///
/// - **Edits are staged, then confirmed.** Toggling an area changes only `selected`; nothing reaches
///   `UserProfile` until the user taps the save control, and `changeSummary` names exactly what that
///   tap will start or stop protecting. Leaving without saving writes nothing.
/// - **Nothing outside the vocabulary is lost.** An injury tag already on the profile that is not one
///   of the six `InjuryOption` cases is carried through a save verbatim rather than silently dropped -
///   this screen edits the areas it can show, and never quietly deletes a flag it cannot render.
@Observable
@MainActor
final class InjuryFlagsViewModel {

    /// The staged selection, bound to the toggles. Differs from `savedSelection` exactly while there
    /// are unconfirmed edits.
    private(set) var selected: Set<InjuryOption> = []

    /// What is actually written on the profile right now.
    private(set) var savedSelection: Set<InjuryOption> = []

    /// True once the profile has been read, so the surface never renders an empty selection as if it
    /// were the user's real (empty) answer.
    private(set) var isLoaded = false

    /// True while a save is in flight.
    private(set) var isSaving = false

    /// A friendly, non-blocking failure line when a save could not be written. `nil` in the happy path.
    private(set) var errorMessage: String?

    /// True once a save has been written in this session, so the surface can confirm it plainly.
    private(set) var didSave = false

    /// Whether the staged selection differs from what is saved.
    var hasUnsavedChanges: Bool { selected != savedSelection }

    /// Whether the confirm control should act.
    var canSave: Bool { isLoaded && hasUnsavedChanges && !isSaving }

    /// A plain-language summary of what confirming will change, so the user is confirming a named
    /// change rather than an opaque "Save". `nil` when nothing is staged.
    var changeSummary: String? {
        guard hasUnsavedChanges else { return nil }
        let added = InjuryOption.allCases.filter { selected.contains($0) && !savedSelection.contains($0) }
        let removed = InjuryOption.allCases.filter { savedSelection.contains($0) && !selected.contains($0) }
        var parts: [String] = []
        if !added.isEmpty {
            parts.append("Will start working around: \(added.map(\.label).joined(separator: ", ")).")
        }
        if !removed.isEmpty {
            parts.append("Will stop working around: \(removed.map(\.label).joined(separator: ", ")).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private let userService: any UserServiceProtocol

    /// The profile being edited, held so a save writes back the whole aggregate rather than a
    /// reconstructed one.
    private var user: User?

    /// Injury tags on the profile that this screen has no toggle for. Preserved verbatim across a save.
    private var unrecognizedTags: [String] = []

    init(userService: any UserServiceProtocol) {
        self.userService = userService
    }

    /// Read the profile's current flags into the staged selection.
    ///
    /// `preselecting` is how the coach's route arrives pre-targeted at the area the user mentioned: it
    /// is staged **unsaved**, so the screen opens with that area switched on and the confirm control
    /// live, and the user still has to press it. A route therefore lands the user one explicit tap from
    /// the change, never past it.
    ///
    /// Idempotent by design: SwiftUI may run the view's `.task` more than once for one screen, and a
    /// second load must neither wipe the edits the user has staged nor re-stage an area they just
    /// switched back off.
    func load(preselecting area: InjuryOption? = nil) async {
        guard !isLoaded else { return }
        guard let loaded = try? await userService.currentUser() else {
            // No profile to edit (should not happen on this surface). Stay unloaded rather than
            // presenting an empty selection that a save would write over a profile we never read.
            return
        }
        user = loaded
        let tags = loaded.profile.injuries
        savedSelection = Set(InjuryOption.allCases.filter { option in tags.contains(option.tag) })
        unrecognizedTags = tags.filter { tag in !InjuryOption.allCases.contains { $0.tag == tag } }
        selected = savedSelection
        if let area { selected.insert(area) }
        isLoaded = true
    }

    /// Stage an area on or off. Purely local until `save()`.
    func toggle(_ area: InjuryOption) {
        didSave = false
        if selected.contains(area) {
            selected.remove(area)
        } else {
            selected.insert(area)
        }
    }

    /// Whether an area is currently staged on.
    func isSelected(_ area: InjuryOption) -> Bool { selected.contains(area) }

    /// Drop every unconfirmed edit. Nothing was written, so this is a pure local reset.
    func discardChanges() {
        selected = savedSelection
        errorMessage = nil
    }

    /// Write the staged selection to `UserProfile.injuries` - the one place this app sets or clears an
    /// injury safety filter after onboarding, and only ever from this explicit user action.
    ///
    /// Tag order is deterministic (`InjuryOption.allCases` order) after any tags this screen does not
    /// recognize, which are carried through untouched.
    func save() async {
        guard canSave, var user else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let tags = unrecognizedTags + InjuryOption.allCases.filter { selected.contains($0) }.map(\.tag)
        user.profile.injuries = tags
        do {
            try await userService.save(user)
            self.user = user
            savedSelection = selected
            didSave = true
        } catch {
            errorMessage = Self.saveFailureMessage
        }
    }

    /// Honest and non-alarming: the change did not stick, the previous flags still stand, and trying
    /// again is safe.
    static let saveFailureMessage = "Couldn't save that just now. Your areas are unchanged - try again."
}
