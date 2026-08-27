import XCTest
@testable import RepToday

/// Tests US-AC08's injury control - the one place an injury safety filter is set or cleared after
/// onboarding.
///
/// The properties that matter are all about *who* changed the profile and *when*: staging a toggle
/// writes nothing, confirming writes the staged change, leaving without confirming writes nothing,
/// and every flag can be switched back off through the same control. The coach's route only pre-stages
/// an area; it never lands past the confirmation.
///
/// What a confirmation actually writes is one rule, pinned by
/// `testOnlyAnAreaRenderedThenSwitchedOffIsEverRemoved`: the screen may only ever *add or keep* areas
/// that arrived from elsewhere, and only an area it rendered and the user switched off is removed.
@MainActor
final class InjuryFlagsViewModelTests: XCTestCase {

    private func makeUser(injuries: [String] = []) -> User {
        var user = MockPersistence.sampleUser
        user.profile.injuries = injuries
        return user
    }

    private func makeViewModel(_ service: MockUserService) -> InjuryFlagsViewModel {
        InjuryFlagsViewModel(userService: service)
    }

    private func storedInjuries(_ service: MockUserService) async throws -> [String] {
        try await service.currentUser()?.profile.injuries ?? []
    }

    // MARK: - Loading

    func testLoadReflectsTheProfilesCurrentFlags() async {
        let service = MockUserService(user: makeUser(injuries: [InjuryOption.knees.tag, InjuryOption.hips.tag]))
        let viewModel = makeViewModel(service)

        await viewModel.load()

        XCTAssertTrue(viewModel.isLoaded)
        XCTAssertEqual(viewModel.selected, [.knees, .hips])
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.canSave, "nothing staged means nothing to confirm")
        XCTAssertNil(viewModel.changeSummary)
    }

    func testLoadWithNoProfileStaysUnloadedRatherThanPresentingAnEmptySelection() async {
        let viewModel = makeViewModel(MockUserService(user: nil))

        await viewModel.load()

        XCTAssertFalse(viewModel.isLoaded)
        XCTAssertFalse(viewModel.canSave, "an unread profile is never savable over")
    }

    /// A failed read must not be a silent dead end: the screen says so, refuses to stage edits it
    /// could never confirm, and stays retryable (its `.task` will not re-run for the same screen).
    func testAFailedLoadSaysSoAndStagesNothing() async {
        let viewModel = makeViewModel(MockUserService(user: nil))

        await viewModel.load()

        XCTAssertTrue(viewModel.loadFailed)
        XCTAssertEqual(viewModel.errorMessage, InjuryFlagsViewModel.loadFailureMessage)
        XCTAssertFalse(viewModel.canEdit, "toggles do not accept input over a profile we never read")

        viewModel.toggle(.knees)
        XCTAssertFalse(viewModel.isSelected(.knees), "a toggle cannot stage against nothing")
        XCTAssertFalse(viewModel.canSave)
    }

    func testRetryingAFailedLoadRecoversTheScreen() async throws {
        let service = MockUserService(user: nil)
        let viewModel = makeViewModel(service)
        await viewModel.load()
        XCTAssertTrue(viewModel.loadFailed)

        try await service.save(makeUser(injuries: [InjuryOption.hips.tag]))
        await viewModel.retryLoad()

        XCTAssertFalse(viewModel.loadFailed)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.isLoaded)
        XCTAssertTrue(viewModel.canEdit)
        XCTAssertTrue(viewModel.isSelected(.hips))
    }

    /// The engine already treats `"Knee"` as a flagged knee (it normalizes tags before lookup), so the
    /// control must show it switched on rather than offering to "add" a protection already in force -
    /// which would then write a duplicate canonical tag beside it.
    func testAnAlreadyProtectedAreaReadsAsFlaggedWhateverTheTagsSpelling() async throws {
        let service = MockUserService(user: makeUser(injuries: ["Knee"]))
        let viewModel = makeViewModel(service)

        await viewModel.load()

        XCTAssertTrue(viewModel.isSelected(.knees), "the engine already protects this area")
        XCTAssertFalse(viewModel.hasUnsavedChanges, "so there is no change to confirm")

        viewModel.toggle(.hips)
        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertEqual(stored.filter { InjuryContraindication.normalizedTag($0) == "knee" }.count, 1,
                       "no duplicate knee tag is appended; got \(stored)")
    }

    /// SwiftUI can run a screen's load task more than once. A second load must not wipe what the user
    /// has staged, re-stage an area they just switched back off, or - as it once did - leave the screen
    /// reading as un-loaded so its confirmation renders inert.
    func testLoadingTwiceKeepsTheScreenLoadedAndTheStagedEditsIntact() async {
        let service = MockUserService(user: makeUser(injuries: [InjuryOption.hips.tag]))
        let viewModel = makeViewModel(service)

        await viewModel.load(preselecting: .knees)
        viewModel.toggle(.knees)
        XCTAssertFalse(viewModel.isSelected(.knees), "the user switched the routed area back off")

        await viewModel.load(preselecting: .knees)

        XCTAssertTrue(viewModel.isLoaded, "a second load leaves the screen loaded and its controls live")
        XCTAssertFalse(viewModel.isSelected(.knees), "and never re-stages what the user just switched off")
        XCTAssertTrue(viewModel.isSelected(.hips), "the saved flags are still reflected")
    }

    // MARK: - Staging writes nothing

    func testTogglingStagesTheChangeWithoutWritingIt() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.knees)

        XCTAssertTrue(viewModel.isSelected(.knees))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.canSave)
        let stored = try await storedInjuries(service)
        XCTAssertTrue(stored.isEmpty, "a toggle alone never reaches the profile")
    }

    /// The toggles are bound value-driven, not edge-driven: a `Toggle` can re-write its *current*
    /// value (an interrupted or cancelled drag of the switch), and on a safety control that must leave
    /// the staged state alone rather than flip it the wrong way.
    func testStagingAnAreaToTheValueItAlreadyHasChangesNothing() async {
        let service = MockUserService(user: makeUser(injuries: [InjuryOption.knees.tag]))
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.set(.knees, to: true)
        XCTAssertTrue(viewModel.isSelected(.knees), "re-writing the value it already has is not a flip")
        XCTAssertFalse(viewModel.hasUnsavedChanges)

        viewModel.set(.hips, to: false)
        XCTAssertFalse(viewModel.isSelected(.hips))
        XCTAssertFalse(viewModel.hasUnsavedChanges, "and neither is re-writing an off switch as off")
    }

    /// Leaving the screen without confirming is the "declining changes nothing" case at the control's
    /// own level.
    func testDiscardingStagedChangesWritesNothing() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.knees)
        viewModel.discardChanges()

        XCTAssertFalse(viewModel.isSelected(.knees))
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        let stored = try await storedInjuries(service)
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Confirming writes

    func testConfirmingWritesTheFlagToTheProfile() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.knees)
        let summary = try XCTUnwrap(viewModel.changeSummary)
        XCTAssertTrue(summary.contains("Will start working around"), "the confirmation names the change; got \(summary)")
        XCTAssertTrue(summary.contains("Knees"))

        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertEqual(stored, [InjuryOption.knees.tag])
        XCTAssertTrue(viewModel.didSave)
        XCTAssertFalse(viewModel.hasUnsavedChanges, "the saved state is now the staged state")
        XCTAssertNil(viewModel.errorMessage)
    }

    /// The written tag is one the engine actually acts on - the point of the whole control.
    func testTheWrittenTagIsOneTheEngineContraindicates() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()
        viewModel.toggle(.knees)
        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertTrue(InjuryContraindication.contraindicatedPatterns(for: stored).contains(.squat),
                      "a flagged knee must actually contraindicate squats")
    }

    // MARK: - Reversibility

    func testAFlagCanBeSwitchedBackOffFromTheSameControl() async throws {
        let service = MockUserService(user: makeUser(injuries: [InjuryOption.knees.tag]))
        let viewModel = makeViewModel(service)
        await viewModel.load()
        XCTAssertTrue(viewModel.isSelected(.knees))

        viewModel.toggle(.knees)
        let summary = try XCTUnwrap(viewModel.changeSummary)
        XCTAssertTrue(summary.contains("Will stop working around"), "removal is named too; got \(summary)")
        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertTrue(stored.isEmpty, "the flag is reversible through the same screen")
        XCTAssertTrue(InjuryContraindication.contraindicatedPatterns(for: stored).isEmpty)
    }

    // MARK: - The coach's route pre-stages, never lands past the confirmation

    func testPreselectingStagesTheAreaButWritesNothing() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)

        await viewModel.load(preselecting: .knees)

        XCTAssertTrue(viewModel.isSelected(.knees), "the routed area opens switched on")
        XCTAssertTrue(viewModel.hasUnsavedChanges, "and unconfirmed")
        XCTAssertTrue(viewModel.canSave, "one explicit tap away, never past it")
        let stored = try await storedInjuries(service)
        XCTAssertTrue(stored.isEmpty, "arriving from the coach writes nothing")
    }

    func testPreselectingAnAlreadyFlaggedAreaStagesNoChange() async {
        let service = MockUserService(user: makeUser(injuries: [InjuryOption.knees.tag]))
        let viewModel = makeViewModel(service)

        await viewModel.load(preselecting: .knees)

        XCTAssertTrue(viewModel.isSelected(.knees))
        XCTAssertFalse(viewModel.hasUnsavedChanges, "nothing to confirm - it is already flagged")
    }

    // MARK: - The write only ever adds or keeps

    /// The rule itself, stated once: this screen may only ever *add or keep* areas that arrived from
    /// elsewhere, and the only thing that *removes* one is the user switching off an area that was
    /// actually rendered to them. Every other case below is a special case of this.
    func testOnlyAnAreaRenderedThenSwitchedOffIsEverRemoved() async throws {
        // Rendered at load: knees (on) and hips (on), plus a tag with no toggle for it.
        let service = MockUserService(user: makeUser(injuries: [InjuryOption.knees.tag, InjuryOption.hips.tag, "neck"]))
        let viewModel = makeViewModel(service)
        await viewModel.load()

        // The user switches off one rendered area and switches on another.
        viewModel.toggle(.hips)
        viewModel.toggle(.wrists)

        // Meanwhile another writer flags two areas this screen never rendered as flagged: one it has a
        // toggle for, one it does not.
        let loaded = try await service.currentUser()
        var moved = try XCTUnwrap(loaded)
        moved.profile.injuries.append(contentsOf: [InjuryOption.shoulders.tag, "elbow"])
        try await service.save(moved)

        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertFalse(InjuryOption.hips.isFlagged(in: stored),
                       "rendered, then switched off - the only way an area is ever removed; got \(stored)")
        XCTAssertTrue(InjuryOption.knees.isFlagged(in: stored), "rendered and left on, so it stays")
        XCTAssertTrue(InjuryOption.wrists.isFlagged(in: stored), "switched on, so it is added")
        XCTAssertTrue(InjuryOption.shoulders.isFlagged(in: stored),
                      "never rendered, so it cannot have been switched off - it is kept")
        XCTAssertTrue(stored.contains("neck"), "no toggle for it, so it is kept")
        XCTAssertTrue(stored.contains("elbow"), "no toggle for it and it arrived mid-edit, so it is kept")
    }

    /// The concrete multi-device shape of the rule: another device flags Shoulders while this screen
    /// sits open on a Knees edit. Shoulders was never rendered here, so confirming Knees keeps both.
    func testAnAreaFlaggedElsewhereMidEditSurvivesAConfirmationThatNeverShowedIt() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.knees)

        let loaded = try await service.currentUser()
        var moved = try XCTUnwrap(loaded)
        moved.profile.injuries.append(InjuryOption.shoulders.tag)
        try await service.save(moved)

        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertTrue(InjuryOption.knees.isFlagged(in: stored), "the confirmed change lands")
        XCTAssertTrue(InjuryOption.shoulders.isFlagged(in: stored),
                      "and the flag this screen never showed is not silently cleared; got \(stored)")
        XCTAssertTrue(InjuryContraindication.contraindicatedPatterns(for: stored).contains(.push),
                      "shoulder protection is still really in force")
    }

    /// The accepted cost of that rule, ruled on deliberately rather than discovered: an area can end up
    /// flagged even though it read as switched *off* when the user pressed save, because another device
    /// flagged it mid-edit. Keeping is the safe direction for a safety filter, and the user can switch
    /// it back off from this same screen.
    func testAcceptedCostAnAreaFlaggedElsewhereStaysOnEvenThoughItReadAsOffAtSaveTime() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()
        XCTAssertFalse(viewModel.isSelected(.shoulders), "the screen shows shoulders switched off")

        viewModel.toggle(.knees)

        let loaded = try await service.currentUser()
        var moved = try XCTUnwrap(loaded)
        moved.profile.injuries.append(InjuryOption.shoulders.tag)
        try await service.save(moved)

        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertTrue(InjuryOption.shoulders.isFlagged(in: stored),
                      "an off-looking switch is not a removal the user made, so it is kept")

        // And it is reversible the ordinary way: reload, see it on, switch it off, confirm.
        let reopened = makeViewModel(service)
        await reopened.load()
        XCTAssertTrue(reopened.isSelected(.shoulders), "reopening shows it as the flag it now is")
        reopened.toggle(.shoulders)
        await reopened.save()
        let afterReversal = try await storedInjuries(service)
        XCTAssertFalse(InjuryOption.shoulders.isFlagged(in: afterReversal),
                       "rendered, then switched off - now it goes")
    }

    func testAnUnrecognizedExistingTagSurvivesASave() async throws {
        let service = MockUserService(user: makeUser(injuries: ["neck", InjuryOption.knees.tag]))
        let viewModel = makeViewModel(service)
        await viewModel.load()

        XCTAssertEqual(viewModel.selected, [.knees], "only tags this screen can show are staged")

        viewModel.toggle(.hips)
        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertTrue(stored.contains("neck"), "a tag this screen cannot render is carried through, never dropped")
        XCTAssertTrue(stored.contains(InjuryOption.knees.tag))
        XCTAssertTrue(stored.contains(InjuryOption.hips.tag))
    }

    func testSavedTagOrderIsDeterministic() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.hips)
        viewModel.toggle(.knees)
        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertEqual(stored, InjuryOption.allCases.filter { [.knees, .hips].contains($0) }.map(\.tag))
    }

    /// The write must land on the *freshest* aggregate, not the snapshot the screen opened with.
    /// `User` carries consistency, cold-start, duration, phase and subscription beside the profile and
    /// the service saves the whole record, so a completed session (or a CloudKit merge) landing while
    /// this screen is open must not be rolled back by an injury save.
    func testSavingDoesNotClobberAnotherWritersChanges() async throws {
        let service = MockUserService(user: makeUser())
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.knees)

        // Another writer advances the aggregate while the edit sits staged - and, in the same merge,
        // adds an injury tag this screen has no toggle for.
        let loaded = try await service.currentUser()
        var moved = try XCTUnwrap(loaded)
        moved.consistency.longestChain += 7
        moved.profile.injuries.append("neck")
        try await service.save(moved)

        await viewModel.save()

        let written = try await service.currentUser()
        let saved = try XCTUnwrap(written)
        XCTAssertEqual(saved.profile.injuries, ["neck", InjuryOption.knees.tag],
                       "the injury change lands, and the tag that arrived while the screen was open survives it")
        XCTAssertEqual(saved.consistency.longestChain, moved.consistency.longestChain,
                       "and the other writer's progress is not rolled back")
    }

    /// The same hazard read the other way, and a special case of the rule above: a tag this screen has
    /// no toggle for could not have been switched off, so one that arrived mid-edit is kept rather than
    /// silently dropped.
    func testSavingPreservesAnUnrenderableTagAddedWhileTheScreenWasOpen() async throws {
        let service = MockUserService(user: makeUser(injuries: ["neck"]))
        let viewModel = makeViewModel(service)
        await viewModel.load()

        viewModel.toggle(.knees)

        let loaded = try await service.currentUser()
        var moved = try XCTUnwrap(loaded)
        moved.profile.injuries.append("elbow")
        try await service.save(moved)

        await viewModel.save()

        let stored = try await storedInjuries(service)
        XCTAssertTrue(stored.contains("neck"), "the tag present at load survives")
        XCTAssertTrue(stored.contains("elbow"),
                      "and so does one that arrived after it - the preserved set is recomputed, never remembered")
        XCTAssertTrue(stored.contains(InjuryOption.knees.tag), "the staged change still lands")
    }

    // MARK: - Failure is honest and non-destructive

    func testAFailedSaveSaysSoAndLeavesTheStagedEditIntact() async {
        let service = ThrowingUserService(user: makeUser())
        let viewModel = InjuryFlagsViewModel(userService: service)
        await viewModel.load()

        viewModel.toggle(.knees)
        await viewModel.save()

        XCTAssertEqual(viewModel.errorMessage, InjuryFlagsViewModel.saveFailureMessage)
        XCTAssertFalse(viewModel.didSave)
        XCTAssertTrue(viewModel.hasUnsavedChanges, "the edit is still staged so a retry is one tap")
        XCTAssertFalse(viewModel.isSaving, "saving always resolves")
    }

    /// A user service whose reads succeed and whose writes fail, so the failure path is reachable.
    private actor ThrowingUserService: UserServiceProtocol {
        private struct Boom: Error {}
        private let user: User?

        init(user: User?) { self.user = user }

        func currentUser() async throws -> User? { user }
        func save(_ user: User) async throws { throw Boom() }
        func deleteCurrentUser() async throws { throw Boom() }
    }
}
