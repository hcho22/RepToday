import XCTest
@testable import RepToday

/// US-HO04 / US-HO05: Outside Activities (decision 21) shape the Rotation, count as showing up and
/// never complete a group; Today logs, edits and deletes them and replans at once; Apple Health
/// workouts are suggested, never applied without a tap, and Rep Today's own are never suggested back.
@MainActor
final class OutsideActivityTests: XCTestCase {

    private let calendar = TrainingDayFixtures.calendar
    private var now: Date { TrainingDayFixtures.asOf }

    private func day(_ day: TrainingDay, daysAgo: Int) -> WorkoutLog {
        TrainingDayFixtures.trainingLog(day, completedAt: TrainingDayFixtures.date(daysAgo: daysAgo))
    }

    private func activity(_ type: OutsideActivityType, daysAgo: Int, hour: Int = 9) -> OutsideActivity {
        OutsideActivity(type: type, date: TrainingDayFixtures.date(daysAgo: daysAgo, hour: hour))
    }

    // MARK: The mapping (decision 21)

    func testActivityTypesMapToGroups() {
        XCTAssertEqual(OutsideActivityType.run.group, .legs)
        XCTAssertEqual(OutsideActivityType.bike.group, .legs)
        XCTAssertEqual(OutsideActivityType.hike.group, .legs)
        XCTAssertEqual(OutsideActivityType.swim.group, .pull)
        XCTAssertEqual(OutsideActivityType.row.group, .pull)
        XCTAssertEqual(OutsideActivityType.climb.group, .pull)
        XCTAssertNil(OutsideActivityType.other.group)
    }

    // MARK: The Rotation

    func testAnActivityLoggedTodayChangesTodaysPlan() {
        let logs = [day(.push, daysAgo: 1)]
        XCTAssertEqual(TrainingRotation.plan(logs: logs, asOf: now, calendar: calendar), .train(.pull))
        let swimThisMorning = OutsideActivity(type: .swim, date: calendar.date(byAdding: .hour, value: -2, to: now)!)
        XCTAssertEqual(TrainingRotation.plan(logs: logs, activities: [swimThisMorning], asOf: now, calendar: calendar), .train(.legs))
    }

    func testAnActivityNeverCompletesAGroup() {
        let run = activity(.run, daysAgo: 1)
        let state = TrainingRotation.state(logs: [day(.push, daysAgo: 3), day(.pull, daysAgo: 2)], activities: [run], asOf: now, calendar: calendar)
        XCTAssertFalse(state.completed.contains(.legs))
        XCTAssertFalse(state.restOwed)
        // Two days on, the legs have had their day off and Legs is still owed.
        let later = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(
            TrainingRotation.plan(logs: [day(.push, daysAgo: 3), day(.pull, daysAgo: 2)], activities: [run], asOf: later, calendar: calendar),
            .train(.legs)
        )
    }

    func testTheEngineReadsActivitiesThroughTheSamePlan() async throws {
        let library = try await MockExerciseService().exercises()
        let plan = SessionAssembly.trainingPlan(
            user: TrainingDayFixtures.user(),
            library: library,
            recentLogs: [day(.push, daysAgo: 3), day(.pull, daysAgo: 2)],
            activities: [activity(.hike, daysAgo: 1)],
            asOf: now,
            calendar: calendar
        )
        XCTAssertEqual(plan, .rest(next: .legs, isEarly: true))
    }

    // MARK: The Cycle strip (decision 19)

    private func strip(_ logs: [WorkoutLog], _ activities: [OutsideActivity] = []) -> [String] {
        TrainingRotation.cycleSteps(logs: logs, activities: activities, asOf: now, calendar: calendar).map { step in
            let status: String
            switch step.status {
            case .done: status = "done"
            case .today: status = "today"
            case .upcoming: status = "next"
            }
            return "\(step.title):\(status)"
        }
    }

    func testTheCycleStripShowsDoneTodayAndWhatIsToCome() {
        XCTAssertEqual(strip([]), ["Push:today", "Pull:next", "Legs:next", "Rest:next"])
        XCTAssertEqual(strip([day(.push, daysAgo: 1)]), ["Push:done", "Pull:today", "Legs:next", "Rest:next"])
        XCTAssertEqual(
            strip([day(.push, daysAgo: 3), day(.pull, daysAgo: 2), day(.legs, daysAgo: 1)]),
            ["Push:done", "Pull:done", "Legs:done", "Rest:today"]
        )
    }

    func testTheCycleStripFollowsAnOutsideActivity() {
        // A swim swaps Pull behind Legs.
        XCTAssertEqual(
            strip([day(.push, daysAgo: 2)], [activity(.swim, daysAgo: 1)]),
            ["Push:done", "Legs:today", "Pull:next", "Rest:next"]
        )
        // A run on the last group brings the Rest Day forward.
        XCTAssertEqual(
            strip([day(.push, daysAgo: 3), day(.pull, daysAgo: 2)], [activity(.run, daysAgo: 1)]),
            ["Push:done", "Pull:done", "Rest:today", "Legs:next"]
        )
        // Once that early rest is taken, the Cycle ends on Legs with no second rest.
        let restTaken = calendar.date(byAdding: .day, value: 2, to: now)!
        let steps = TrainingRotation.cycleSteps(
            logs: [day(.push, daysAgo: 3), day(.pull, daysAgo: 2)],
            activities: [activity(.run, daysAgo: 1)],
            asOf: restTaken,
            calendar: calendar
        )
        XCTAssertEqual(steps.map(\.title), ["Push", "Pull", "Rest", "Legs"])
        XCTAssertEqual(steps.map(\.status), [.done, .done, .done, .today])
    }

    func testCycleStepsReadAloudAsOneSentence() {
        let step = CycleStep(.day(.legs), .today)
        XCTAssertEqual(step.accessibilityLabel, "Legs, today")
        XCTAssertEqual(CycleStep(.rest, .upcoming).accessibilityLabel, "Rest, coming up")
    }

    // MARK: Consistency

    func testAnActivityCountsAsShowingUp() {
        let activities = [activity(.run, daysAgo: 0), activity(.swim, daysAgo: 0, hour: 7), activity(.other, daysAgo: 0, hour: 6)]
        let withActivities = ConsistencyScore.evaluate(logs: [], activities: activities, weeklyGoal: 3, asOf: now, calendar: calendar)
        XCTAssertEqual(withActivities.score, 100, accuracy: 0.001)
        XCTAssertEqual(withActivities.workoutsThisWeek, 3)
        // Sessions stay Rep Today's own totals.
        XCTAssertEqual(withActivities.totalWorkoutsCompleted, 0)

        let session = TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 0, hour: 8))
        let alone = ConsistencyScore.evaluate(logs: [session], weeklyGoal: 3, asOf: now, calendar: calendar)
        let together = ConsistencyScore.evaluate(logs: [session], activities: [activities[0]], weeklyGoal: 3, asOf: now, calendar: calendar)
        XCTAssertGreaterThan(together.score, alone.score)
    }

    /// An activity shows up exactly as a session on the same day does: the score, this week's count and
    /// the chain are the same either way, whatever week it falls in.
    func testAnActivityCountsExactlyLikeASessionOnTheSameDay() {
        let logs = [day(.push, daysAgo: 8), day(.pull, daysAgo: 7), day(.legs, daysAgo: 1)]
        for daysAgo in [0, 2, 9, 30] {
            let hike = activity(.hike, daysAgo: daysAgo, hour: 7)
            let session = TrainingDayFixtures.trainingLog(.push, completedAt: hike.date)
            let withActivity = ConsistencyScore.evaluate(logs: logs, activities: [hike], weeklyGoal: 3, asOf: now, calendar: calendar)
            let withSession = ConsistencyScore.evaluate(logs: logs + [session], weeklyGoal: 3, asOf: now, calendar: calendar)
            XCTAssertEqual(withActivity.score, withSession.score, accuracy: 0.0001, "\(daysAgo) days ago")
            XCTAssertEqual(withActivity.workoutsThisWeek, withSession.workoutsThisWeek)
            XCTAssertEqual(withActivity.longestChain, withSession.longestChain)
        }
    }

    func testTheProgressTabScoresActivitiesExactlyAsTodayDoes() async throws {
        let logs = [day(.push, daysAgo: 2)]
        let activities = [activity(.run, daysAgo: 1), activity(.swim, daysAgo: 0, hour: 7)]
        let progress = ProgressViewModel(
            userService: MockUserService(user: TrainingDayFixtures.user()),
            workoutLogService: MockWorkoutLogService(logs: logs),
            outsideActivityService: InMemoryOutsideActivityService(activities: activities),
            exerciseService: try MockExerciseService(),
            subscriptionService: MockSubscriptionService(),
            consistencyService: ConsistencyScoreService(now: { self.now }),
            now: { self.now }
        )
        await progress.load()
        let (today, _) = try makeViewModel(logs: logs, activities: activities)
        await today.load()
        let expected = ConsistencyScore.evaluate(logs: logs, activities: activities, weeklyGoal: 3, asOf: now).score
        XCTAssertEqual(progress.consistency?.score ?? -1, expected, accuracy: 0.0001)
        XCTAssertEqual(progress.consistency?.score, today.consistency?.score)
        XCTAssertGreaterThan(expected, ConsistencyScore.evaluate(logs: logs, weeklyGoal: 3, asOf: now).score)
    }

    // MARK: Today (US-HO04)

    private func makeViewModel(
        logs: [WorkoutLog],
        activities: [OutsideActivity] = [],
        health: StubHealthKitService? = nil
    ) throws -> (ReadyViewModel, InMemoryOutsideActivityService) {
        let store = InMemoryOutsideActivityService(activities: activities)
        let viewModel = ReadyViewModel(
            userService: MockUserService(user: TrainingDayFixtures.user()),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.now }),
            workoutLogService: MockWorkoutLogService(logs: logs),
            outsideActivityService: store,
            healthKitService: health,
            ownBundleIdentifier: "com.reptoday.app",
            consistencyService: ConsistencyScoreService(now: { self.now }),
            now: { self.now }
        )
        return (viewModel, store)
    }

    private var pushAndPullDone: [WorkoutLog] {
        [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 3, hour: 18)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 2, hour: 18)),
        ]
    }

    func testLoggingARunReplansTodayAtOnceAndTheRestDayComesEarly() async throws {
        let (viewModel, store) = try makeViewModel(logs: pushAndPullDone)
        await viewModel.load()
        XCTAssertEqual(viewModel.workout?.trainingDay, .legs)

        let run = OutsideActivity(type: .run, date: calendar.date(byAdding: .hour, value: -1, to: now)!, durationMinutes: 30, distanceMeters: 4828)
        let saved = await viewModel.saveActivity(run)
        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.plan, .rest(next: .legs, isEarly: true))
        XCTAssertTrue(viewModel.showsRestDay)
        XCTAssertNil(viewModel.workout)
        XCTAssertEqual(viewModel.recentActivities, [run])
        let stored = try await store.activities(from: nil, to: nil)
        XCTAssertEqual(stored, [run])
    }

    func testEditingAndDeletingAnActivityReplansToo() async throws {
        let run = OutsideActivity(type: .run, date: calendar.date(byAdding: .hour, value: -1, to: now)!)
        let (viewModel, store) = try makeViewModel(logs: pushAndPullDone, activities: [run])
        await viewModel.load()
        XCTAssertTrue(viewModel.showsRestDay)

        // Edited into a workout that works no group: Legs is back.
        var yoga = run
        yoga.type = .other
        await viewModel.saveActivity(yoga)
        XCTAssertEqual(viewModel.plan, .train(.legs))
        XCTAssertEqual(viewModel.workout?.trainingDay, .legs)
        let stored = try await store.activities(from: nil, to: nil)
        XCTAssertEqual(stored.map(\.type), [.other])

        // Edited back to a run, then deleted: Legs is back again.
        await viewModel.saveActivity(run)
        XCTAssertTrue(viewModel.showsRestDay)
        await viewModel.deleteActivity(id: run.id)
        XCTAssertEqual(viewModel.plan, .train(.legs))
        XCTAssertTrue(viewModel.recentActivities.isEmpty)
        let afterDelete = try await store.activities(from: nil, to: nil)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testTodaysScoreCountsALoggedActivity() async throws {
        let (viewModel, _) = try makeViewModel(logs: [])
        await viewModel.load()
        let before = viewModel.consistency?.score ?? 0
        await viewModel.saveActivity(OutsideActivity(type: .swim, date: calendar.date(byAdding: .hour, value: -1, to: now)!))
        XCTAssertGreaterThan(viewModel.consistency?.score ?? 0, before)
    }

    func testTodayListsOnlyThisPastWeeksActivitiesNewestFirst() async throws {
        let old = activity(.hike, daysAgo: 9)
        let recent = activity(.run, daysAgo: 2)
        let newest = activity(.swim, daysAgo: 0, hour: 8)
        let (viewModel, _) = try makeViewModel(logs: [], activities: [old, recent, newest])
        await viewModel.load()
        XCTAssertEqual(viewModel.recentActivities, [newest, recent])
        XCTAssertEqual(viewModel.activities.count, 3)
    }

    // MARK: Apple Health (US-HO05)

    private func candidate(
        _ type: OutsideActivityType = .run,
        hoursAgo: Double = 3,
        source: String = "com.apple.Health",
        externalUUID: String? = nil,
        id: UUID = UUID()
    ) -> HealthWorkoutCandidate {
        HealthWorkoutCandidate(
            id: id,
            type: type,
            start: now.addingTimeInterval(-hoursAgo * 3600),
            durationMinutes: 32,
            distanceMeters: 5000,
            sourceBundleIdentifier: source,
            externalUUID: externalUUID
        )
    }

    func testRepTodaysOwnWorkoutsAreNeverSuggestedBack() {
        let sessionId = UUID()
        let own = candidate(source: "com.reptoday.app")
        let ownSession = candidate(source: "com.other.app", externalUUID: sessionId.uuidString)
        let watch = candidate(source: "com.apple.health.ABC")
        let pending = HealthWorkoutSuggestions.pending(
            candidates: [own, ownSession, watch],
            ownBundleIdentifier: "com.reptoday.app",
            ownSessionIds: [sessionId],
            logged: [],
            dismissed: [],
            asOf: now,
            calendar: calendar
        )
        XCTAssertEqual(pending, [watch])
    }

    func testAddedIgnoredOldAndFutureWorkoutsAreNotSuggested() {
        let added = candidate(hoursAgo: 2)
        let ignored = candidate(hoursAgo: 4)
        let old = candidate(hoursAgo: 24 * 8)
        let future = candidate(hoursAgo: -2)
        let fresh = candidate(.swim, hoursAgo: 5)
        let logged = [added.outsideActivity]
        let pending = HealthWorkoutSuggestions.pending(
            candidates: [added, ignored, old, future, fresh],
            ownBundleIdentifier: "com.reptoday.app",
            ownSessionIds: [],
            logged: logged,
            dismissed: [ignored.id],
            asOf: now,
            calendar: calendar
        )
        XCTAssertEqual(pending, [fresh])
    }

    func testSuggestionsAreNewestFirstAndCapped() {
        let candidates = (1...5).map { candidate(hoursAgo: Double($0)) }
        let pending = HealthWorkoutSuggestions.pending(
            candidates: candidates.reversed(),
            ownBundleIdentifier: nil,
            ownSessionIds: [],
            logged: [],
            dismissed: [],
            asOf: now,
            calendar: calendar
        )
        XCTAssertEqual(pending, Array(candidates.prefix(HealthWorkoutSuggestions.limit)))
    }

    func testAnAddedSuggestionCarriesTheHealthWorkoutAndItsDetails() {
        let suggestion = candidate(.climb)
        let activity = suggestion.outsideActivity
        XCTAssertEqual(activity.healthWorkoutId, suggestion.id)
        XCTAssertEqual(activity.type, .climb)
        XCTAssertEqual(activity.durationMinutes, 32)
        XCTAssertNil(activity.distanceMeters, "a climb has no distance")
        XCTAssertEqual(activity.date, suggestion.start)
    }

    func testHealthIsNotReadUntilTheUserTurnsSuggestionsOn() async throws {
        let health = StubHealthKitService(workouts: [candidate()])
        let (viewModel, _) = try makeViewModel(logs: [], health: health)
        await viewModel.load()
        await viewModel.refreshHealthSuggestions(enabled: false, dismissed: [])
        XCTAssertTrue(viewModel.healthSuggestions.isEmpty)
        XCTAssertEqual(health.reads, 0)
    }

    func testASuggestionIsAppliedOnlyWhenTheUserAddsIt() async throws {
        let run = candidate(.run, hoursAgo: 2)
        let health = StubHealthKitService(workouts: [run, candidate(source: "com.reptoday.app")])
        let (viewModel, store) = try makeViewModel(logs: pushAndPullDone, health: health)
        await viewModel.load()
        await viewModel.refreshHealthSuggestions(enabled: true, dismissed: [])
        XCTAssertEqual(viewModel.healthSuggestions, [run])
        // Suggested, not applied: the plan and the store are untouched.
        XCTAssertEqual(viewModel.plan, .train(.legs))
        let untouched = try await store.activities(from: nil, to: nil)
        XCTAssertTrue(untouched.isEmpty)

        await viewModel.addHealthSuggestion(run)
        XCTAssertTrue(viewModel.healthSuggestions.isEmpty)
        XCTAssertEqual(viewModel.plan, .rest(next: .legs, isEarly: true))
        let stored = try await store.activities(from: nil, to: nil)
        XCTAssertEqual(stored.map(\.healthWorkoutId), [run.id])

        // Read again: the added workout is not offered a second time.
        await viewModel.refreshHealthSuggestions(enabled: true, dismissed: [])
        XCTAssertTrue(viewModel.healthSuggestions.isEmpty)
    }

    func testIgnoringASuggestionAppliesNothing() async throws {
        let swim = candidate(.swim)
        let health = StubHealthKitService(workouts: [swim])
        let (viewModel, store) = try makeViewModel(logs: [day(.push, daysAgo: 1)], health: health)
        await viewModel.load()
        await viewModel.refreshHealthSuggestions(enabled: true, dismissed: [])
        viewModel.ignoreHealthSuggestion(swim)
        XCTAssertTrue(viewModel.healthSuggestions.isEmpty)
        XCTAssertEqual(viewModel.plan, .train(.pull))
        let stored = try await store.activities(from: nil, to: nil)
        XCTAssertTrue(stored.isEmpty)
        // The dismissal the caller persists keeps it away on the next read.
        await viewModel.refreshHealthSuggestions(enabled: true, dismissed: [swim.id])
        XCTAssertTrue(viewModel.healthSuggestions.isEmpty)
    }
}

/// A Health stand-in returning fixed workouts and counting reads.
final class StubHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    private let workouts: [HealthWorkoutCandidate]
    private(set) var reads = 0
    private(set) var readAuthorizationRequests = 0

    init(workouts: [HealthWorkoutCandidate]) {
        self.workouts = workouts
    }

    func authorizationStatus() async throws -> HealthKitAuthorizationStatus { .notDetermined }
    func requestAuthorization() async throws -> HealthKitAuthorizationStatus { .notDetermined }
    func saveWorkoutLog(_ log: WorkoutLog, user: User) async throws {}

    func requestWorkoutReadAuthorization() async throws {
        readAuthorizationRequests += 1
    }

    func recentWorkouts(since: Date) async throws -> [HealthWorkoutCandidate] {
        reads += 1
        return workouts.filter { $0.start >= since }
    }
}
