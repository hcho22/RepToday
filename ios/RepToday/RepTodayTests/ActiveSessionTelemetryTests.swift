import XCTest
@testable import RepToday

/// Tests the *player's* half of the session-lifecycle telemetry (US-T10).
///
/// The player emits `session_started` once at `start()` (never re-emitted on resume), and
/// `session_completed` at the dismiss choke point `recordSessionEnd()` when the session actually
/// completed. A mid-session dismiss that leaves the session resumable is a *pause*, not an
/// abandonment, so the player emits no terminal event then; `session_abandoned` fires only on a true
/// give-up (Discard / overwrite) owned by `ReadyViewModel`, covered in `ReadyViewModelTests`. The
/// load-bearing property is that across the full resume path one physical session emits exactly one
/// terminal event - never both, never neither-when-an-outcome-occurred. These tests drive that
/// structurally through `MockAnalyticsService` with an injected clock, so the decisions are
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

    // MARK: - Pause is not an abandonment (US-T10 refinement)

    /// A mid-session dismiss that leaves the session *resumable* is a pause, not an abandonment: the
    /// player emits no terminal event at all (only the earlier `session_started`), so a later resume +
    /// completion cannot be double-counted against a spurious abandon. The abandonment, if it ever
    /// comes, fires from the give-up path in `ReadyViewModel` (see `ReadyViewModelTests`).
    func testMidSessionDismissEmitsNoTerminalEvent() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(requestedMinutes: 20), analytics: analytics, clock: clock)

        vm.start()
        vm.completeSet()        // past the warm-up, still mid-session
        XCTAssertFalse(vm.isComplete)
        vm.recordSessionEnd()   // the X on the player: a resumable pause

        let events = await recorded(analytics, vm)
        XCTAssertEqual(events.map(\.name), [.sessionStarted], "a pause emits started only - no terminal event")
        XCTAssertFalse(events.contains { $0.name == .sessionAbandoned }, "a pause never emits abandoned")
        XCTAssertFalse(events.contains { $0.name == .sessionCompleted }, "a pause never emits completed")
    }

    /// A resumed player restores `startedAt`, so its `start()` is a no-op for telemetry: the physical
    /// session's `session_started` is not re-emitted on resume, keeping it to one per physical session.
    func testResumedPlayerDoesNotReEmitSessionStarted() async {
        let clock = MutableClock(start)
        let seed = ActiveSessionViewModel(workout: threeBlockWorkout(), now: { clock.now })
        seed.start()                      // stamps startedAt
        let state = seed.snapshot()
        XCTAssertNotNil(state.startedAt)

        let analytics = MockAnalyticsService()
        let resumed = ActiveSessionViewModel(state: state, analytics: analytics, now: { clock.now })
        resumed.start()                   // startedAt already set -> no-op

        let started = await recorded(analytics, resumed).filter { $0.name == .sessionStarted }
        XCTAssertEqual(started.count, 0, "a resumed session's start() does not re-emit session_started")
    }

    /// The whole resume path across two physical player lifetimes: start -> pause(dismiss) -> resume ->
    /// finish emits exactly one `session_started` and one `session_completed`, and never a
    /// `session_abandoned`. Both players share one sink, exactly as production does.
    func testResumeThenFinishEmitsOneStartedAndOneCompleted() async throws {
        let store = InMemoryActiveSessionStore()
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let workout = threeBlockWorkout(requestedMinutes: 20)

        let player1 = ActiveSessionViewModel(workout: workout, store: store, userId: "u", analytics: analytics, now: { clock.now })
        player1.start()          // session_started + persists
        player1.completeSet()    // advance + persist a resumable snapshot
        player1.recordSessionEnd()   // a resumable pause: no terminal event
        await player1.persistenceTask?.value
        await player1.analyticsTask?.value

        let loaded = try await store.load(for: "u")
        let saved = try XCTUnwrap(loaded, "the paused session is resumable")
        let player2 = ActiveSessionViewModel(state: saved, store: store, userId: "u", analytics: analytics, now: { clock.now })
        player2.start()          // resumed: no re-emit
        completeAllSets(player2)
        player2.recordSessionEnd()   // session_completed
        await player2.analyticsTask?.value

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.filter { $0.name == .sessionStarted }.count, 1, "started fires once for the physical session")
        XCTAssertEqual(events.filter { $0.name == .sessionCompleted }.count, 1, "completed fires exactly once")
        XCTAssertEqual(events.filter { $0.name == .sessionAbandoned }.count, 0, "a resumed-then-completed session never abandons")
    }

    /// The exercised-minutes the give-up emission reports are captured in the snapshot at the last
    /// active moment, off the same `completedDurationMinutes` semantics the completion log uses, so a
    /// session paused and later discarded reports minutes actually exercised rather than wall-clock idle.
    func testSnapshotCapturesExercisedMinutes() {
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(requestedMinutes: 20), analytics: MockAnalyticsService(), clock: clock)

        vm.start()
        clock.advance(180)   // three minutes exercised
        vm.completeSet()     // persist captures the exercised minutes as of now

        XCTAssertEqual(vm.snapshot().exercisedMinutes, 3)
    }

    // MARK: - One-terminal-event invariant

    /// A repeated dismiss never double-fires the completion terminal event (the one-shot guard).
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

    /// A straight completion dismissed emits exactly one terminal event, and it is `session_completed`.
    func testStraightCompletionEmitsExactlyOneTerminalEvent() async {
        let analytics = MockAnalyticsService()
        let clock = MutableClock(start)
        let vm = makeViewModel(threeBlockWorkout(), analytics: analytics, clock: clock)

        vm.start()
        completeAllSets(vm)
        vm.recordSessionEnd()

        let terminals = await recorded(analytics, vm).filter {
            $0.name == .sessionCompleted || $0.name == .sessionAbandoned
        }
        XCTAssertEqual(terminals.map(\.name), [.sessionCompleted])
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
