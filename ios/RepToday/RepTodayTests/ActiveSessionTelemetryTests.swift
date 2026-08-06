import XCTest
@testable import RepToday

/// Tests the session-lifecycle telemetry emissions (US-T10).
///
/// The player emits `session_started` once at `start()`, and exactly one *terminal* event -
/// `session_completed` xor `session_abandoned` - from the single dismiss choke point
/// `recordSessionEnd()`, keyed off `isComplete`. The load-bearing property is that a completed
/// session emits `started` then `completed` and never `abandoned`, an abandoned one emits `started`
/// then `abandoned` and never `completed`, and no lifecycle event double-fires. These tests drive
/// that structurally through `MockAnalyticsService` with an injected clock, so the decisions are
/// deterministic and no real time passes.
final class ActiveSessionTelemetryTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 760_000_000)

    // MARK: - Fixtures

    /// A mutable clock so the tests can advance time between `start()` and the terminal event and
    /// assert the whole-minute `completed_minutes` off a known elapsed span.
    private final class MutableClock {
        private(set) var now: Date
        init(_ date: Date) { now = date }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func repExercise(_ id: String) -> Exercise {
        Exercise(
            id: id, displayName: id.capitalized, pillar: .strength, movementPattern: .push,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [], isHold: false,
            defaultReps: 10, defaultDurationSeconds: nil, estimatedTimePerSetSeconds: 40, metValue: 4,
            progressionChainId: "\(id)_chain", progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "3x12", apartmentFriendly: true
        )
    }

    private func rep(_ id: String, sets: Int) -> PrescribedExercise {
        PrescribedExercise(id: UUID(), exercise: repExercise(id), sets: sets, reps: 10, durationSeconds: nil, restSeconds: 0)
    }

    /// A three-block session (warm-up -> strength -> cooldown), so every `abandon_point` bucket is
    /// reachable by advancing the player. Rest is zeroed so `completeSet` never opens an overlay,
    /// keeping the walk-through a plain sequence of set completions.
    private func threeBlockWorkout(requestedMinutes: Int = 20, wasReturn: Bool = false) -> Workout {
        Workout(
            id: UUID(), createdAt: start, shape: .blend, focusPillar: nil,
            requestedMinutes: requestedMinutes, wasReturn: wasReturn,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-up", category: .warmup, exercises: [rep("cat_cow", sets: 1)]),
                WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [rep("push_up", sets: 2)]),
                WorkoutBlock(id: UUID(), title: "Cooldown", category: .cooldown, exercises: [rep("stretch", sets: 1)])
            ]
        )
    }

    private func makeViewModel(_ workout: Workout, analytics: MockAnalyticsService, clock: MutableClock) -> ActiveSessionViewModel {
        ActiveSessionViewModel(workout: workout, analytics: analytics, now: { clock.now })
    }

    /// Drain the chained emission task, then read what the sink recorded. Awaiting the last chained
    /// task awaits the whole chain, since each emission awaits the previous one.
    private func recorded(_ analytics: MockAnalyticsService, _ vm: ActiveSessionViewModel) async -> [AnalyticsEvent] {
        await vm.analyticsTask?.value
        return await analytics.recordedEvents
    }

    /// Play every set of the session so it completes.
    private func completeAllSets(_ vm: ActiveSessionViewModel) {
        while !vm.isComplete { vm.completeSet() }
    }

    // MARK: - session_started

    /// `start()` emits exactly one `session_started` carrying the requested minutes.
    func testStartEmitsSessionStartedWithRequestedMinutes() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(requestedMinutes: 20), analytics: analytics, clock: clock)

        vm.start()

        let started = await recorded(analytics, vm).filter { $0.name == .sessionStarted }
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started[0].properties, ["requested_minutes": .int(20)])
    }

    /// `start()` is idempotent (its `startedAt == nil` guard), so a second call - e.g. the view
    /// re-appearing - never re-emits `session_started`.
    func testStartIsIdempotentForTelemetry() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(), analytics: analytics, clock: clock)

        vm.start()
        vm.start()

        let started = await recorded(analytics, vm).filter { $0.name == .sessionStarted }
        XCTAssertEqual(started.count, 1, "a second start() does not re-emit session_started")
    }

    // MARK: - session_completed

    /// A completed session emits `session_started` then `session_completed` - never `session_abandoned` -
    /// carrying all four properties read off the completion log, with `perceived_difficulty` reflecting
    /// the rating given on the completion screen (which is why the event fires at dismissal, not `finish()`).
    func testCompletedSessionEmitsStartedThenCompletedWithRating() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(requestedMinutes: 20, wasReturn: true), analytics: analytics, clock: clock)

        vm.start()
        clock.advance(300) // 5 minutes of session before the last set lands
        completeAllSets(vm)
        XCTAssertTrue(vm.isComplete)
        vm.rate(.tooHard)      // the completion-screen rating, given before Done
        vm.recordSessionEnd()  // the dismiss choke point (Done tapped)

        let events = await recorded(analytics, vm)
        XCTAssertEqual(events.map(\.name), [.sessionStarted, .sessionCompleted], "started then completed, in order")
        XCTAssertFalse(events.contains { $0.name == .sessionAbandoned }, "a completed session never emits abandoned")

        let completed = events.first { $0.name == .sessionCompleted }!
        XCTAssertEqual(completed.properties["requested_minutes"], .int(20))
        XCTAssertEqual(completed.properties["completed_minutes"], .int(5))
        XCTAssertEqual(completed.properties["was_return"], .bool(true))
        XCTAssertEqual(completed.properties["perceived_difficulty"], .string("too_hard"))
    }

    /// When the user completes but skips the rating, `perceived_difficulty` is simply absent - the
    /// property bag carries no null - while the other three are still present.
    func testCompletedWithoutRatingOmitsPerceivedDifficulty() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(requestedMinutes: 10), analytics: analytics, clock: clock)

        vm.start()
        completeAllSets(vm)
        vm.recordSessionEnd() // Done without rating

        let completed = await recorded(analytics, vm).first { $0.name == .sessionCompleted }!
        XCTAssertNil(completed.properties["perceived_difficulty"], "an unrated completion omits the key")
        XCTAssertEqual(completed.properties["requested_minutes"], .int(10))
        XCTAssertEqual(completed.properties["was_return"], .bool(false))
    }

    // MARK: - session_abandoned

    /// An abandoned session emits `session_started` then `session_abandoned` - never `session_completed` -
    /// carrying the minutes exercised so far and the `abandon_point` for where the user was.
    func testAbandonedDuringMainWorkEmitsStartedThenAbandoned() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(requestedMinutes: 20), analytics: analytics, clock: clock)

        vm.start()
        vm.completeSet()        // past the warm-up, now on the strength block (main work)
        XCTAssertEqual(vm.currentStep?.blockCategory, .strength)
        clock.advance(180)      // 3 minutes in
        vm.recordSessionEnd()   // the X on the player: dismissed before completion

        let events = await recorded(analytics, vm)
        XCTAssertEqual(events.map(\.name), [.sessionStarted, .sessionAbandoned], "started then abandoned, in order")
        XCTAssertFalse(events.contains { $0.name == .sessionCompleted }, "an abandoned session never emits completed")

        let abandoned = events.first { $0.name == .sessionAbandoned }!
        XCTAssertEqual(abandoned.properties["completed_minutes"], .int(3))
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("mainWork"))
    }

    /// `abandon_point` is derived from the block the current step sits in: the warm-up bookend.
    func testAbandonPointWarmup() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(), analytics: analytics, clock: clock)

        vm.start()             // still on the warm-up (index 0)
        vm.recordSessionEnd()

        let abandoned = await recorded(analytics, vm).first { $0.name == .sessionAbandoned }!
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("warmup"))
    }

    /// `abandon_point` for the cooldown bookend - the last block, still short of completion.
    func testAbandonPointCooldown() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(), analytics: analytics, clock: clock)

        vm.start()
        vm.completeSet() // warm-up done -> push_up set 1
        vm.completeSet() // push_up set 1 -> set 2
        vm.completeSet() // push_up set 2 done -> cooldown "stretch"
        XCTAssertEqual(vm.currentStep?.blockCategory, .cooldown)
        vm.recordSessionEnd()

        let abandoned = await recorded(analytics, vm).first { $0.name == .sessionAbandoned }!
        XCTAssertEqual(abandoned.properties["abandon_point"], .string("cooldown"))
    }

    // MARK: - One-terminal-event invariant

    /// A repeated dismiss never double-fires a terminal event (the one-shot guard), on either outcome.
    func testRecordSessionEndIsIdempotent() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(), analytics: analytics, clock: clock)

        vm.start()
        completeAllSets(vm)
        vm.recordSessionEnd()
        vm.recordSessionEnd() // a second dismiss

        let events = await recorded(analytics, vm)
        XCTAssertEqual(events.filter { $0.name == .sessionCompleted }.count, 1, "completed fires exactly once")
        XCTAssertEqual(events.filter { $0.name == .sessionAbandoned }.count, 0)
    }

    /// The dismiss choke point emits exactly one terminal event whether or not the session completed,
    /// so a completed session dismissed and an abandoned session dismissed each carry one terminal event.
    func testExactlyOneTerminalEventPerOutcome() async {
        // Abandoned.
        let abandonAnalytics = MockAnalyticsService()
        let abandonClock = MutableClock(start)
        let abandonVM = makeViewModel(threeBlockWorkout(), analytics: abandonAnalytics, clock: abandonClock)
        abandonVM.start()
        abandonVM.completeSet()
        abandonVM.recordSessionEnd()
        let abandonTerminals = await recorded(abandonAnalytics, abandonVM).filter {
            $0.name == .sessionCompleted || $0.name == .sessionAbandoned
        }
        XCTAssertEqual(abandonTerminals.map(\.name), [.sessionAbandoned])

        // Completed.
        let completeAnalytics = MockAnalyticsService()
        let completeClock = MutableClock(start)
        let completeVM = makeViewModel(threeBlockWorkout(), analytics: completeAnalytics, clock: completeClock)
        completeVM.start()
        completeAllSets(completeVM)
        completeVM.recordSessionEnd()
        let completeTerminals = await recorded(completeAnalytics, completeVM).filter {
            $0.name == .sessionCompleted || $0.name == .sessionAbandoned
        }
        XCTAssertEqual(completeTerminals.map(\.name), [.sessionCompleted])
    }

    // MARK: - Optional sink

    /// The emissions are optional: a player built with no analytics sink runs the whole lifecycle
    /// (start, complete, dismiss) without trapping.
    func testTelemetryIsOptional() {
        let clock = MutableClock(start)
        let vm = ActiveSessionViewModel(workout: threeBlockWorkout(), now: { clock.now })

        vm.start()
        completeAllSets(vm)
        vm.recordSessionEnd()

        XCTAssertTrue(vm.isComplete, "the session runs to completion with no analytics sink wired")
    }
}
