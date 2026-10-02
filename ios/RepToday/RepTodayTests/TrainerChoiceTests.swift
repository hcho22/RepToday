import XCTest
@testable import RepToday

/// US-TP10 (the one-time Trainer choice) and US-TP11 (the Settings row): when the choice is asked, what
/// a choice does, and what a failed save does (captain, Open Question 8).
@MainActor
final class TrainerChoiceTests: XCTestCase {

    private func user(sex: Sex, trainer: Trainer? = nil) -> User {
        var user = MockPersistence.sampleUser
        user.profile.sex = sex
        user.profile.trainer = trainer
        return user
    }

    // MARK: - US-TP10: gating

    func testOnlyAnUnresolvedUserIsAsked() async {
        for sex in Sex.allCases {
            for choice in [nil, Trainer.male, Trainer.female] as [Trainer?] {
                let stored = user(sex: sex, trainer: choice)
                let model = TrainerSessionModel(profile: stored.profile, userService: MockUserService(user: stored))
                let asks = await model.refreshOnArrival()
                XCTAssertEqual(asks, sex == .other && choice == nil, "sex \(sex), choice \(String(describing: choice))")
                XCTAssertEqual(model.trainer, Trainer.effective(for: stored.profile))
            }
        }
    }

    func testNoUserIsNeverAsked() async {
        let model = TrainerSessionModel(profile: nil, userService: nil)
        XCTAssertFalse(model.needsChoice)
        let asks = await model.refreshOnArrival()
        XCTAssertFalse(asks)
        XCTAssertNil(model.trainer)
    }

    /// A stale Ready-Screen snapshot says "unresolved", but the user already chose (in Settings, or on an
    /// earlier arrival): the arrival re-read finds the stored choice and does not ask again.
    func testAStoredChoiceNewerThanTheSnapshotSuppressesTheChoice() async {
        let stale = user(sex: .other)
        let model = TrainerSessionModel(profile: stale.profile, userService: MockUserService(user: user(sex: .other, trainer: .male)))
        XCTAssertTrue(model.needsChoice, "the snapshot alone would ask")
        let asks = await model.refreshOnArrival()
        XCTAssertFalse(asks)
        XCTAssertEqual(model.trainer, .male)
    }

    /// A Trainer switched in Settings since the snapshot is the one the session shows.
    func testTheArrivalFollowsATrainerSwitchedSinceTheSnapshot() async {
        let model = TrainerSessionModel(
            profile: user(sex: .male).profile,
            userService: MockUserService(user: user(sex: .male, trainer: .female))
        )
        XCTAssertEqual(model.trainer, .male)
        _ = await model.refreshOnArrival()
        XCTAssertEqual(model.trainer, .female)
    }

    // MARK: - US-TP10: choosing

    func testChoosingShowsTheTrainerAtOnceAndStoresIt() async throws {
        let service = MockUserService(user: user(sex: .other))
        let model = TrainerSessionModel(profile: user(sex: .other).profile, userService: service)
        let save = model.choose(.female)
        XCTAssertEqual(model.trainer, .female, "the art switches the moment the choice is made")
        XCTAssertFalse(model.needsChoice)
        let saved = await save.value
        XCTAssertTrue(saved)
        let stored = try await service.currentUser()
        XCTAssertEqual(stored?.profile.trainer, .female)

        // The next arrival never asks again.
        let next = TrainerSessionModel(profile: user(sex: .other).profile, userService: service)
        let asks = await next.refreshOnArrival()
        XCTAssertFalse(asks)
        XCTAssertEqual(next.trainer, .female)
    }

    /// Open Question 8: a failed save keeps the chosen Trainer for this session and dismisses the
    /// choice; because nothing was stored, the next arrival asks again.
    func testAFailedSaveKeepsTheChoiceForThisSessionAndAsksAgainNextArrival() async {
        let service = SaveFailingUserService(user: user(sex: .other))
        let model = TrainerSessionModel(profile: user(sex: .other).profile, userService: service)
        let saved = await model.choose(.male).value
        XCTAssertFalse(saved)
        XCTAssertEqual(model.trainer, .male, "this session keeps the chosen Trainer")
        XCTAssertFalse(model.needsChoice, "the choice is not asked again this session")

        let next = TrainerSessionModel(profile: user(sex: .other).profile, userService: service)
        let asks = await next.refreshOnArrival()
        XCTAssertTrue(asks, "nothing was persisted, so the next arrival asks again")
    }

    // MARK: - US-TP11: Settings row

    func testSettingsRowShowsTheEffectiveTrainerOrNotChosenYet() async {
        let male = TrainerSettingsViewModel(userService: MockUserService(user: user(sex: .male)))
        await male.load()
        XCTAssertEqual(male.trainer, .male)
        XCTAssertEqual(male.valueText, "Male Trainer")

        let other = TrainerSettingsViewModel(userService: MockUserService(user: user(sex: .other)))
        await other.load()
        XCTAssertNil(other.trainer)
        XCTAssertEqual(other.valueText, "Not chosen yet")
    }

    func testSettingsSwitchWritesThroughTheOneTrainerWriteAndSatisfiesTheChoice() async throws {
        let service = MockUserService(user: user(sex: .other))
        let model = TrainerSettingsViewModel(userService: service)
        await model.load()
        await model.select(.female)
        XCTAssertEqual(model.trainer, .female)
        XCTAssertNil(model.errorMessage)
        let stored = try await service.currentUser()
        XCTAssertEqual(stored?.profile.trainer, .female)

        // US-TP10 is satisfied: an "other" user who chose in Settings is never asked in the player.
        let player = TrainerSessionModel(profile: user(sex: .other).profile, userService: service)
        let asks = await player.refreshOnArrival()
        XCTAssertFalse(asks)
    }

    /// Open Question 8: a failed switch keeps showing the stored Trainer and says it was not saved.
    func testSettingsFailedSwitchKeepsTheStoredTrainerAndSaysSo() async {
        let model = TrainerSettingsViewModel(userService: SaveFailingUserService(user: user(sex: .male)))
        await model.load()
        await model.select(.female)
        XCTAssertEqual(model.trainer, .male)
        XCTAssertEqual(model.valueText, "Male Trainer")
        XCTAssertEqual(model.errorMessage, TrainerChoiceCopy.saveFailureMessage)
        XCTAssertFalse(model.isSaving)
    }
}

/// A user service whose reads work and whose saves always fail.
private actor SaveFailingUserService: UserServiceProtocol {
    struct SaveFailed: Error {}
    private let user: User?

    init(user: User?) { self.user = user }

    func currentUser() async throws -> User? { user }
    func save(_ user: User) async throws { throw SaveFailed() }
    func advancePhase(to earnedPhase: Phase, for userId: String) async throws -> User? { user }
    func deleteCurrentUser() async throws {}
}
