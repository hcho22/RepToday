import XCTest
@testable import RepToday

/// Tests US-AC08's injury control - the one place an injury safety filter is set or cleared after
/// onboarding.
///
/// The properties that matter are all about *who* changed the profile and *when*: staging a toggle
/// writes nothing, confirming writes exactly the staged set, leaving without confirming writes
/// nothing, and every flag can be switched back off through the same control. The coach's route only
/// pre-stages an area; it never lands past the confirmation.
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

    // MARK: - Nothing outside the vocabulary is lost

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
