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
/// - **The write only ever adds or keeps** - see `injuriesToWrite(mergingOnto:)`, the single rule that
///   decides what a save puts on the profile.
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

    /// True when the profile could not be read, so the surface says so and offers a retry instead of
    /// presenting live-looking toggles over a confirmation that can never act.
    private(set) var loadFailed = false

    /// Whether the toggles should accept input. A screen that has not read the profile has nothing
    /// honest to stage against, so it stages nothing.
    var canEdit: Bool { isLoaded }

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
            // No profile to edit. Stay unloaded rather than presenting an empty selection that a save
            // would write over a profile we never read - but say so and stay retryable, so the screen
            // is never a dead end with live-looking toggles above an inert confirmation.
            loadFailed = true
            errorMessage = Self.loadFailureMessage
            return
        }
        user = loaded
        savedSelection = Self.recognizedAreas(in: loaded.profile.injuries)
        selected = savedSelection
        if let area { selected.insert(area) }
        loadFailed = false
        errorMessage = nil
        isLoaded = true
    }

    /// Retry a failed load, from the surface's own "Try again" control. The screen's `.task` does not
    /// re-run for the same view identity, so without this a single failed read would leave the control
    /// unusable for the life of the screen.
    func retryLoad(preselecting area: InjuryOption? = nil) async {
        guard !isLoaded else { return }
        loadFailed = false
        errorMessage = nil
        await load(preselecting: area)
    }

    /// Stage an area on or off. Purely local until `save()`. A no-op before the profile has been read:
    /// there is nothing to stage a change *against* yet.
    func toggle(_ area: InjuryOption) {
        set(area, to: !selected.contains(area))
    }

    /// Stage an area to an explicit value. This, not `toggle`, is what a `Toggle` binding writes
    /// through: a binding reports the value it wants, and a switch can re-write its *current* value
    /// (an interrupted or cancelled drag), which an edge-driven setter would flip the wrong way.
    func set(_ area: InjuryOption, to isOn: Bool) {
        guard canEdit else { return }
        didSave = false
        if isOn {
            selected.insert(area)
        } else {
            selected.remove(area)
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
    /// The write lands on the *freshest* aggregate, not the snapshot this screen opened with. `User`
    /// carries consistency, cold-start, duration, phase and subscription beside the profile, and the
    /// user service saves the whole record - so a CloudKit merge or a background policy/duration write
    /// landing while this screen was open would otherwise be rolled back by an injury save. Same
    /// re-read `SessionCompletionService` does before its write. What the injuries array itself
    /// becomes is decided in one place, `injuriesToWrite(mergingOnto:)`.
    func save() async {
        guard canSave, let loaded = user else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        var user = (try? await userService.currentUser()) ?? loaded
        user.profile.injuries = injuriesToWrite(mergingOnto: user.profile.injuries)
        do {
            try await userService.save(user)
            self.user = user
            savedSelection = selected
            didSave = true
        } catch {
            errorMessage = Self.saveFailureMessage
        }
    }

    /// The one rule deciding what a save puts on the profile:
    ///
    /// **This screen may only ever add or keep areas that arrived from elsewhere. The only thing that
    /// removes an area is the user explicitly switching off one that was rendered to them on screen.**
    ///
    /// So the write is never-drop by construction. `fresh` is the injuries array as it stands *now*,
    /// and a tag only leaves it if it names an area this screen showed switched on (`savedSelection`)
    /// and the user switched back off (`selected`). Everything else survives: a tag outside the six
    /// `InjuryOption` cases, which this screen has no toggle for and so could not have been unticked,
    /// and equally an in-vocabulary flag another device added after this screen loaded, which was
    /// never rendered and so could not have been unticked either. For a safety filter, dropping is the
    /// unsafe direction, so the rule refuses to infer a removal it did not watch the user make.
    ///
    /// **The accepted cost**, ruled on deliberately: an area can end up flagged even though it read as
    /// switched off when the user pressed save, because another device flagged it mid-edit. Keeping it
    /// is the safe direction, and the user can switch it back off from this same screen.
    ///
    /// Tags kept from `fresh` hold their existing order and spelling; newly staged areas follow in
    /// `InjuryOption.allCases` order, and an area already protected under another spelling is not
    /// appended a second time.
    private func injuriesToWrite(mergingOnto fresh: [String]) -> [String] {
        let unticked = savedSelection.subtracting(selected)
        let kept = fresh.filter { tag in !unticked.contains { $0.isFlagged(in: [tag]) } }
        let added = InjuryOption.allCases
            .filter { selected.contains($0) && !$0.isFlagged(in: kept) }
            .map(\.tag)
        return kept + added
    }

    /// The areas this screen has a toggle for that the given tags already protect, read the engine's
    /// way (`InjuryOption.isFlagged`, over `InjuryContraindication`'s normalization) so a tag stored
    /// under another spelling is recognized rather than shown as switched off.
    private static func recognizedAreas(in tags: [String]) -> Set<InjuryOption> {
        Set(InjuryOption.allCases.filter { $0.isFlagged(in: tags) })
    }

    /// Honest and non-alarming: the change did not stick, the previous flags still stand, and trying
    /// again is safe.
    static let saveFailureMessage = "Couldn't save that just now. Your areas are unchanged - try again."

    /// The same honesty on the read side: nothing was shown, so nothing can be trusted or changed yet.
    static let loadFailureMessage = "Couldn't load your areas just now. Nothing has changed - try again."
}
