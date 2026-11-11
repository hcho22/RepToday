import XCTest
@testable import RepToday

/// US-HO01 (the Welcome Page), US-HO02 (Focus Areas in onboarding and Settings) and the M2 `AppState`
/// flags behind them and the Apple Health opt-in (US-HO05).
@MainActor
final class WelcomeAndFocusSettingsTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WelcomeAndFocusSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var now: Date { TrainingDayFixtures.asOf }

    // MARK: AppState

    func testTheWelcomePageIsOwedOnEveryColdLaunchAndOnlyOnce() {
        let launch = AppState(userDefaults: defaults)
        XCTAssertTrue(launch.isWelcomePending)
        launch.markWelcomeSeen()
        XCTAssertFalse(launch.isWelcomePending, "a resume keeps the process, so it is not shown again")
        // The next cold launch builds a new AppState: the page is owed again.
        XCTAssertTrue(AppState(userDefaults: defaults).isWelcomePending)
    }

    func testHealthSuggestionsAreOffByDefaultAndTheChoicePersists() {
        let first = AppState(userDefaults: defaults)
        XCTAssertFalse(first.healthWorkoutSuggestionsEnabled)
        let workout = UUID()
        first.healthWorkoutSuggestionsEnabled = true
        first.dismissHealthWorkout(workout)

        let relaunched = AppState(userDefaults: defaults)
        XCTAssertTrue(relaunched.healthWorkoutSuggestionsEnabled)
        XCTAssertEqual(relaunched.dismissedHealthWorkoutIds, [workout])

        relaunched.resetHealthSuggestionState()
        let afterReset = AppState(userDefaults: defaults)
        XCTAssertFalse(afterReset.healthWorkoutSuggestionsEnabled)
        XCTAssertTrue(afterReset.dismissedHealthWorkoutIds.isEmpty)
    }

    func testSavingAPlanInputBumpsTheTransientRevision() {
        let state = AppState(userDefaults: defaults)
        XCTAssertEqual(state.planInputsRevision, 0)
        state.markPlanInputsChanged()
        XCTAssertEqual(state.planInputsRevision, 1)
        XCTAssertEqual(AppState(userDefaults: defaults).planInputsRevision, 0, "never persisted")
    }

    // MARK: Welcome Page

    private func welcome(
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        name: String = "Sam",
        hour: Int = 12,
        daysFromNow: Int = 0
    ) throws -> WelcomeViewModel {
        var user = TrainingDayFixtures.user()
        user.displayName = name
        let day = TrainingDayFixtures.calendar.date(byAdding: .day, value: daysFromNow, to: now)!
        let clock = TrainingDayFixtures.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return WelcomeViewModel(
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            outsideActivityService: InMemoryOutsideActivityService(activities: activities),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { clock }),
            now: { clock },
            calendar: TrainingDayFixtures.calendar
        )
    }

    func testTheWelcomePageGreetsByNameAndNamesTodaysTrainingDay() async throws {
        let viewModel = try welcome(
            logs: [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1))],
            hour: 9
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.isLoaded)
        XCTAssertEqual(viewModel.greeting, "Good morning, Sam.")
        XCTAssertEqual(viewModel.plan, .train(.pull))
        XCTAssertEqual(viewModel.dayTitle, "Pull Day")
        XCTAssertEqual(viewModel.dayDetail, TrainingDay.pull.focusLine)
        XCTAssertEqual(viewModel.steps.map(\.title), ["Push", "Pull", "Legs", "Rest"])
        XCTAssertEqual(viewModel.steps.map(\.status), [.done, .today, .upcoming, .upcoming])
    }

    func testTheWelcomePageShowsARestDayAndOneThatCameEarly() async throws {
        let cycle = [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 3)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 2)),
        ]
        let rest = try welcome(logs: cycle + [TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 1))])
        await rest.load()
        XCTAssertEqual(rest.dayTitle, "Rest Day")
        XCTAssertEqual(rest.dayDetail, WelcomeCopy.rest)

        let early = try welcome(logs: cycle, activities: [OutsideActivity(type: .run, date: TrainingDayFixtures.date(daysAgo: 1))])
        await early.load()
        XCTAssertEqual(early.plan, .rest(next: .legs, reason: .early))
        XCTAssertEqual(early.dayDetail, "Your outside workout covered Legs, so rest comes early.")
    }

    /// A run logged the same day on the last group: the page says the legs were worked outside today, and
    /// the early Rest Day is announced the next day, the day it falls.
    func testTheWelcomePageSaysARunTodayWorkedTheLegsAndAnnouncesTheEarlyRestTomorrow() async throws {
        let cycle = [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 2)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 1)),
        ]
        let run = OutsideActivity(type: .run, date: TrainingDayFixtures.date(daysAgo: 0, hour: 11))

        let today = try welcome(logs: cycle, activities: [run])
        await today.load()
        XCTAssertEqual(today.dayTitle, "Day Off")
        XCTAssertEqual(today.dayDetail, "You worked Legs outside today, so it gets a day off.")
        XCTAssertEqual(today.steps.map(\.title), ["Push", "Pull", "Day off", "Rest", "Legs"])

        let tomorrow = try welcome(logs: cycle, activities: [run], daysFromNow: 1)
        await tomorrow.load()
        XCTAssertEqual(tomorrow.dayTitle, "Rest Day")
        XCTAssertEqual(tomorrow.dayDetail, "Your outside workout covered Legs, so rest comes early.")
        XCTAssertEqual(tomorrow.steps.map(\.status), [.done, .done, .today, .upcoming])
    }

    func testTheGreetingFollowsTheClockAndWorksWithoutAName() async throws {
        XCTAssertEqual(WelcomeCopy.salutation(forHour: 6), "Good morning")
        XCTAssertEqual(WelcomeCopy.salutation(forHour: 14), "Good afternoon")
        XCTAssertEqual(WelcomeCopy.salutation(forHour: 20), "Good evening")
        XCTAssertEqual(WelcomeCopy.salutation(forHour: 2), "Hello")
        let unnamed = try welcome(logs: [], name: "  ", hour: 14)
        await unnamed.load()
        XCTAssertEqual(unnamed.greeting, "Good afternoon.")
        XCTAssertEqual(unnamed.dayTitle, "Push Day")
    }

    func testAWelcomePageThatCannotReadStillLetsTheUserThrough() async {
        let viewModel = WelcomeViewModel(
            userService: MockUserService(user: nil),
            workoutLogService: MockWorkoutLogService(),
            outsideActivityService: InMemoryOutsideActivityService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try! MockExerciseService())
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.isLoaded)
        XCTAssertNil(viewModel.plan)
        XCTAssertEqual(viewModel.dayTitle, WelcomeCopy.fallbackTitle)
        XCTAssertTrue(viewModel.steps.isEmpty)
    }

    // MARK: Onboarding (US-HO02)

    func testOnboardingAsksForFocusAreasAfterTheFitnessLevelAndSavesThem() async throws {
        let steps = OnboardingViewModel.Step.allCases
        XCTAssertEqual(steps.firstIndex(of: .focusAreas), (steps.firstIndex(of: .fitnessLevel) ?? 0) + 1)

        let users = MockUserService(user: nil)
        let viewModel = OnboardingViewModel(userService: users, sessionPolicyService: MockSessionPolicyService())
        viewModel.displayName = "Sam"
        while viewModel.step != .focusAreas { viewModel.advance() }
        XCTAssertTrue(viewModel.canAdvance, "Focus Areas are optional")
        viewModel.selectedFocusAreas = [.glutes, .chest]
        let finished = await viewModel.finish()
        XCTAssertTrue(finished)
        let saved = try await users.currentUser()
        XCTAssertEqual(saved?.profile.focusAreas, [.chest, .glutes])
    }

    func testOnboardingWithNoFocusAreasSavesNone() {
        let viewModel = OnboardingViewModel(userService: MockUserService(user: nil), sessionPolicyService: MockSessionPolicyService())
        XCTAssertEqual(viewModel.buildUser().profile.focusAreas, [])
    }

    // MARK: Settings (US-HO02)

    func testTheSettingsEditorStagesThenSavesOntoAFreshRead() async throws {
        var user = TrainingDayFixtures.user(focusAreas: [.abs])
        let users = MockUserService(user: user)
        let viewModel = FocusAreasViewModel(userService: users)
        await viewModel.load()
        XCTAssertEqual(viewModel.selection, [.abs])
        XCTAssertFalse(viewModel.hasChanges)

        viewModel.toggle(.legs)
        viewModel.toggle(.abs)
        XCTAssertTrue(viewModel.hasChanges)
        // Nothing is written until Save.
        let unsaved = try await users.currentUser()
        XCTAssertEqual(unsaved?.profile.focusAreas, [.abs])

        // Another writer changes the user meanwhile; the save keeps that change.
        user.profile.injuries = ["knees"]
        try await users.save(user)
        let saved = await viewModel.save()
        XCTAssertTrue(saved)
        XCTAssertFalse(viewModel.hasChanges)
        let stored = try await users.currentUser()
        XCTAssertEqual(stored?.profile.focusAreas, [.legs])
        XCTAssertEqual(stored?.profile.injuries, ["knees"])
    }

    func testTheSettingsEditorLoadIsIdempotentAndClearingIsAnAnswer() async throws {
        let users = MockUserService(user: TrainingDayFixtures.user(focusAreas: [.back]))
        let viewModel = FocusAreasViewModel(userService: users)
        await viewModel.load()
        viewModel.toggle(.back)
        await viewModel.load()
        XCTAssertEqual(viewModel.selection, [], "a re-run never wipes a staged change")
        await viewModel.save()
        let stored = try await users.currentUser()
        XCTAssertEqual(stored?.profile.focusAreas, [])
    }

    func testTheSettingsSummaryNamesTheAreasInOrder() {
        XCTAssertEqual(FocusAreasCopy.summary([]), "None")
        XCTAssertEqual(FocusAreasCopy.summary([.glutes, .chest]), "Chest, Glutes")
    }

    func testSavedFocusAreasRebuildTodaysSession() async throws {
        let users = MockUserService(user: TrainingDayFixtures.user())
        let ready = ReadyViewModel(
            userService: users,
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.now }),
            workoutLogService: MockWorkoutLogService(),
            now: { self.now }
        )
        await ready.load()
        let mainBefore = ready.workout?.blocks.flatMap(\.exercises).first { $0.role == .main }
        XCTAssertEqual(mainBefore?.exercise.progressionChainId, "push_horizontal")

        let editor = FocusAreasViewModel(userService: users)
        await editor.load()
        editor.toggle(.shoulders)
        await editor.save()
        // What a save's `markPlanInputsChanged()` triggers on Today: a fresh load.
        await ready.load()
        let mainAfter = ready.workout?.blocks.flatMap(\.exercises).first { $0.role == .main }
        XCTAssertEqual(mainAfter?.exercise.progressionChainId, "push_vertical")
    }
}
