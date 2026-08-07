import XCTest
@testable import RepToday

/// US-T11: the completion recorder emits `week_active` at most once per distinct calendar week that
/// contains at least one completed session, keyed off the *same* `ConsistencyScore.startOfWeek`
/// bucketing `ProgressAnalytics` uses for its weekly rollup - handed the pinned cohort calendar, the
/// one calendar decision this story owns (see `SessionCompletionService.emitWeekActive`).
///
/// The emit-once set is persisted, and on the production path it lives in `UserDefaults.standard`; these
/// tests drive that same store (not a private suite) and restore the key with `restoreAfterTest`, so a
/// leftover week never leaks into a later test in the process (see `DefaultsSnapshot`).
final class WeekActiveEventTests: XCTestCase {

    /// The calendar the emission cadence buckets in - the production choice (`AppState.cohortCalendar`):
    /// Gregorian, Sunday-start, pinned to Pacific, deliberately *not* `Calendar.current`.
    private let calendar = AppState.cohortCalendar

    /// A mutable clock the tests advance to place each session's `completedAt` in a given week; both the
    /// week bucketing and the emitted event timestamp are keyed off that same `completedAt`, so advancing
    /// "into the next week" is expressed by the log date below.
    private var clock = Date(timeIntervalSince1970: 0)

    override func setUp() {
        super.setUp()
        // The persisted emit-once set lives in `.standard` on the production path; restore it so no
        // week leaks past this test.
        restoreAfterTest(SessionCompletionService.weekActiveEmittedWeeksKey)
        UserDefaults.standard.removeObject(forKey: SessionCompletionService.weekActiveEmittedWeeksKey)
    }

    // MARK: - Fixtures

    /// A date at noon Pacific on the given calendar day, so the Sunday-start week boundary is
    /// unambiguous regardless of daylight-saving edges.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func makeUser() -> User {
        var user = MockPersistence.sampleUser
        user.id = "u1"
        user.coldStart = User.ColdStart(sessionsLogged: 0, active: true)
        user.consistency = Consistency(
            weeklyGoal: 3, score: 0, workoutsThisWeek: 0,
            longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
        )
        return user
    }

    private func makeLog(completedAt: Date) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: completedAt,
            requestedMinutes: 20,
            durationMinutes: 14,
            wasReturn: false,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: "push_up", pillar: .strength, movementPattern: .push,
                    completedSets: [CompletedSet(reps: 12, durationSeconds: nil)], skipped: false
                )
            ]
        )
    }

    private func makeService(
        analytics: MockAnalyticsService,
        logService: MockWorkoutLogService,
        userService: MockUserService
    ) -> SessionCompletionService {
        SessionCompletionService(
            workoutLogService: logService,
            userService: userService,
            consistencyService: ConsistencyScoreService(now: { self.clock }, calendar: self.calendar),
            policyStore: InMemorySessionPolicyStore(),
            healthKitService: nil,
            analytics: analytics,
            emissionCalendar: self.calendar,
            userDefaults: .standard
        )
    }

    private func weekActiveCount(_ events: [AnalyticsEvent]) -> Int {
        events.filter { $0.name == .weekActive }.count
    }

    // MARK: - Validation Test (US-T11)

    /// The full once-per-week story: first session of week W emits, a second session in W does not,
    /// and the first session of week W+1 emits again.
    func testEmitsOncePerDistinctActiveWeek() async throws {
        let analytics = MockAnalyticsService()
        let logService = MockWorkoutLogService()
        let userService = MockUserService(user: makeUser())
        let service = makeService(analytics: analytics, logService: logService, userService: userService)

        // Week W (Sun Aug 2 - Sat Aug 8, 2026): the first completed session opens the bucket.
        clock = date(2026, 8, 5)
        try await service.recordCompletedSession(makeLog(completedAt: clock), user: makeUser(), recentLogs: [])
        var events = await analytics.recordedEvents
        XCTAssertEqual(weekActiveCount(events), 1, "the first completed session of a week emits `week_active`")

        // Second session, same week W: no new emission - `week_active` is per week, not per session.
        clock = date(2026, 8, 7)
        try await service.recordCompletedSession(makeLog(completedAt: clock), user: makeUser(), recentLogs: [])
        events = await analytics.recordedEvents
        XCTAssertEqual(weekActiveCount(events), 1, "a second session in the same week does not re-emit")

        // Week W+1 (Sun Aug 9 - Sat Aug 15, 2026): the first session of the new week emits again.
        clock = date(2026, 8, 12)
        try await service.recordCompletedSession(makeLog(completedAt: clock), user: makeUser(), recentLogs: [])
        events = await analytics.recordedEvents
        XCTAssertEqual(weekActiveCount(events), 2, "the first session of a new week emits a new `week_active`")
    }

    /// `week_active` carries no properties, per the pre-registered schema.
    func testWeekActiveCarriesNoProperties() async throws {
        let analytics = MockAnalyticsService()
        let service = makeService(
            analytics: analytics,
            logService: MockWorkoutLogService(),
            userService: MockUserService(user: makeUser())
        )

        clock = date(2026, 8, 5)
        try await service.recordCompletedSession(makeLog(completedAt: clock), user: makeUser(), recentLogs: [])

        let recorded = await analytics.recordedEvents
        let event = try XCTUnwrap(recorded.first { $0.name == .weekActive })
        XCTAssertTrue(event.properties.isEmpty, "`week_active` carries no properties")
    }

    /// The once-per-week guarantee is keyed off the *persisted* set, so it survives a fresh service
    /// instance (a relaunch): a second service over the same store does not re-emit for a week the
    /// first already emitted.
    func testEmitOnceSurvivesANewServiceInstance() async throws {
        let logService = MockWorkoutLogService()
        let userService = MockUserService(user: makeUser())

        let firstAnalytics = MockAnalyticsService()
        let firstService = makeService(analytics: firstAnalytics, logService: logService, userService: userService)
        clock = date(2026, 8, 5)
        try await firstService.recordCompletedSession(makeLog(completedAt: clock), user: makeUser(), recentLogs: [])
        let firstEvents = await firstAnalytics.recordedEvents
        XCTAssertEqual(weekActiveCount(firstEvents), 1)

        // A brand-new service (the relaunch) over the same persisted emit-once store, same week.
        let secondAnalytics = MockAnalyticsService()
        let secondService = makeService(analytics: secondAnalytics, logService: logService, userService: userService)
        clock = date(2026, 8, 7)
        try await secondService.recordCompletedSession(makeLog(completedAt: clock), user: makeUser(), recentLogs: [])
        let secondEvents = await secondAnalytics.recordedEvents
        XCTAssertEqual(
            weekActiveCount(secondEvents), 0,
            "a relaunched service must not re-emit for a week already counted"
        )
    }

    /// The bucketing matches `ProgressAnalytics`'s rollup keyset exactly: the number of distinct
    /// `week_active` emissions over a history equals the number of distinct active week-starts the
    /// rollup computes over that same history (in the emission calendar). This guards against a
    /// divergent week definition, the story's named failure indicator.
    func testEmissionCountMatchesProgressAnalyticsWeekBuckets() async throws {
        let analytics = MockAnalyticsService()
        let logService = MockWorkoutLogService()
        let userService = MockUserService(user: makeUser())
        let service = makeService(analytics: analytics, logService: logService, userService: userService)

        // Three sessions across two distinct weeks (two in W, one in W+1).
        let completions = [date(2026, 8, 5), date(2026, 8, 7), date(2026, 8, 12)]
        for completedAt in completions {
            clock = completedAt
            try await service.recordCompletedSession(makeLog(completedAt: completedAt), user: makeUser(), recentLogs: [])
        }

        // The rollup's keyset over the same history, in the same calendar: the set of active week-starts.
        let allLogs = try await logService.workoutLogs(from: nil, to: nil)
        let rollupWeekStarts = Set(allLogs.map { ConsistencyScore.startOfWeek($0.completedAt, calendar) })

        let events = await analytics.recordedEvents
        XCTAssertEqual(
            weekActiveCount(events), rollupWeekStarts.count,
            "one `week_active` per distinct active week the rollup buckets"
        )
        XCTAssertEqual(rollupWeekStarts.count, 2, "sanity: the fixture spans exactly two active weeks")
    }
}
