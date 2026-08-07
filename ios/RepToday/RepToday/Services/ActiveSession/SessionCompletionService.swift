import Foundation

/// Records a finished session (US-L01): the single seam the active-session player calls the moment a
/// session completes, so the win is durable even if the user force-quits on the completion screen.
///
/// It writes the `WorkoutLog` (the durable record the whole app reads back) and then performs the
/// post-session bookkeeping that hangs off a completion:
///
/// - **Consistency Score refresh (US-H01).** The forgiving score is recomputed over the full
///   persisted history (including the just-saved log) and stored back on the user aggregate, so the
///   all-time `longestChain` stays honest and is never understated by a bounded log window.
/// - **Cold-start handoff (US-G04).** This is the single caller of `ColdStartHandoff`: it advances
///   `user.coldStart.sessionsLogged` and retires cold-start once the threshold is reached, recording
///   the Start Seed floor the week actually ran at, then reconciles the policy (clearing the now-inert
///   `coldStartContract`). The user and policy are separate aggregates, so they are persisted
///   separately. The floor is resolved over the *full* history, not the caller's bounded `recentLogs`,
///   so every `too_hard` rating the cold-start window produced is counted - including, once
///   `recordPerceivedDifficulty` folds it in, the retiring session's own.
/// - **HealthKit write (US-N03).** When a HealthKit service is wired, the completed session is mirrored
///   into Health as a workout. The write is fully isolated (its own `try?`) so a denied authorization or
///   a HealthKit failure never disrupts the essential bookkeeping above or blocks the completion; the
///   service enforces idempotency by the log id, so a re-record never duplicates the session in Health.
///
/// The user aggregate has a second writer - the on-open reprogram (US-J02/US-F03), which can persist a
/// learned `user.duration` between Ready-Screen open and session completion. So the cold-start/consistency
/// read-modify-write is based on the *freshest* persisted user (`currentUser()`), not the caller's
/// open-time snapshot, which would otherwise clobber that learned duration.
///
/// It deliberately does **not** fold Default Duration learning here: that is the Programmer's job
/// (US-F03), which folds each completed session's `durationMinutes` into the EWMA exactly once, keyed
/// off the policy's `updatedAt` dedup boundary. Folding here too would double-count. This service only
/// makes sure the log carries the actually-completed `durationMinutes` so the Programmer can learn
/// from it on the next open.
protocol SessionCompletionServiceProtocol {
    /// Persist a completed session and its post-session bookkeeping. `recentLogs` is retained for
    /// caller stability, but the full persisted history is what the bookkeeping reads, because neither
    /// consumer tolerates a bounded window: the Consistency Score's all-time `longestChain` (US-H01)
    /// would be understated by one, and the cold-start handoff resolves the Start Seed floor the week
    /// actually ran at (US-O02) from every down-signal that week produced.
    func recordCompletedSession(_ log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws

    /// Attach the user's perceived-difficulty rating to an already-recorded log (US-L02).
    ///
    /// The rating is collected on the completion screen, *after* `recordCompletedSession` has already
    /// written the durable record (US-L01), so this is a minimal, idempotent re-save of that one log by
    /// its stable id: it sets `perceivedDifficulty` and persists, and deliberately does **not** repeat
    /// the Consistency refresh or advance the cold-start counter. Those don't depend on the rating, and
    /// re-running the handoff would advance `coldStart.sessionsLogged` a second time for the same
    /// session. The rating is what the Asymmetric Ramp (US-E05) reads on the next session, so it only
    /// needs to land on the log record before the next generation. A `nil` difficulty is a valid
    /// "unrated" value.
    ///
    /// It does re-resolve one *derived* fact: the Start Seed band floor the cold-start week ran at
    /// (US-O02). Because the retiring session can only be rated after its handoff has run, a `tooHard`
    /// on the fifth session would otherwise be dropped entirely - the strongest signal the user can
    /// send, silently missing from the record of their own week. Only `bandFloorAtHandoff` moves; the
    /// counter is untouched, so this can never double-advance cold start.
    func recordPerceivedDifficulty(_ difficulty: PerceivedDifficulty?, forLog log: WorkoutLog) async throws
}

/// The real `SessionCompletionServiceProtocol` backing the app. Every dependency is a protocol/seam,
/// so the whole flow is testable without CoreData.
final class SessionCompletionService: SessionCompletionServiceProtocol {

    private let workoutLogService: any WorkoutLogServiceProtocol
    private let userService: any UserServiceProtocol
    private let consistencyService: any ConsistencyServiceProtocol
    /// The same policy store the deterministic Programmer writes through (US-F03), shared so the
    /// cold-start handoff's reconciled policy lands where the engine reads it on the next open.
    private let policyStore: any SessionPolicyStore
    /// Optional Health mirror (US-N03). `nil` in previews / the in-memory mock, where a completed session
    /// records nothing to Health. When wired, the completed session is written to Health as a workout,
    /// fully isolated so it can never disrupt the essential bookkeeping or block the completion.
    private let healthKitService: (any HealthKitServiceProtocol)?
    /// Anonymous product-telemetry sink (US-T11). Optional exactly like the other emission sites'
    /// (`ReadyViewModel`/`ActiveSessionViewModel`): `nil` in previews and the in-memory mock, wired only
    /// on the real completion path in `ServiceContainer.live`. This is the site the `week_active` event
    /// emits from, because it is the one place that holds both the just-completed log and the sink.
    private let analytics: (any AnalyticsServiceProtocol)?
    /// Clock seam for the emission's millisecond timestamp; production uses `Date.init`, tests inject.
    /// Never read inside the essential bookkeeping - that stays a pure function of the persisted history.
    private let now: () -> Date
    /// The calendar the `week_active` cadence is bucketed in (US-T11 decision): `AppState.cohortCalendar`
    /// (Gregorian, Sunday-start, pinned Pacific), **not** `Calendar.current`. See `emitWeekActive`.
    private let emissionCalendar: Calendar
    /// Where the persisted set of already-emitted week-starts lives (US-T11), so a second session in the
    /// same week never re-emits and the once-per-week guarantee survives relaunch. Production uses
    /// `.standard`; tests inject a restorable store.
    private let userDefaults: UserDefaults

    /// The `UserDefaults` key holding the emit-once set: an array of already-emitted week-start instants
    /// (whole seconds since the Unix epoch) in `emissionCalendar`. Internal so the tests that must write
    /// the real defaults can restore it via `restoreAfterTest`.
    static let weekActiveEmittedWeeksKey = "telemetry.weekActiveEmittedWeeks"

    init(
        workoutLogService: any WorkoutLogServiceProtocol,
        userService: any UserServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol,
        policyStore: any SessionPolicyStore,
        healthKitService: (any HealthKitServiceProtocol)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        emissionCalendar: Calendar = AppState.cohortCalendar,
        userDefaults: UserDefaults = .standard
    ) {
        self.workoutLogService = workoutLogService
        self.userService = userService
        self.consistencyService = consistencyService
        self.policyStore = policyStore
        self.healthKitService = healthKitService
        self.analytics = analytics
        self.now = now
        self.emissionCalendar = emissionCalendar
        self.userDefaults = userDefaults
    }

    func recordCompletedSession(_ log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws {
        // 1. Persist the log first - the durable record of the session, and the data Default Duration
        //    learning (US-F04) and the Consistency Score (US-H01) both read back.
        try await workoutLogService.save(log)

        // 2. Read the *freshest* persisted user, not the Ready-Screen snapshot. The on-open reprogram
        //    (US-J02/US-F03) is a second writer of the user aggregate and may have persisted a learned
        //    `user.duration` since this session's snapshot was captured; read-modifying-writing the stale
        //    snapshot would clobber it. Fall back to the snapshot only if the read is unavailable.
        let latest = (try? await userService.currentUser()) ?? user

        // 3. Read the *full* persisted history (which now includes the just-saved `log`), not the
        //    caller's bounded `recentLogs`. Both of the steps below need it and neither tolerates a
        //    window: `longestChain` is an all-time historical maximum (US-H01: "a later break never
        //    lowers it"), and the cold-start handoff records the Start Seed floor the week ran at,
        //    which is resolved from every down-signal the window produced.
        let allLogs = try await workoutLogService.workoutLogs(from: nil, to: nil)

        // 4. Advance cold-start and reconcile the policy against the just-completed session (US-G04).
        //    The policy read falls back to the neutral default until the Programmer has ever written
        //    one, exactly as `currentPolicy(for:)` does.
        let currentPolicy = try await policyStore.policy(for: latest.id) ?? .default
        let handoff = ColdStartHandoff.afterCompletedSession(
            user: latest,
            sessionPolicy: currentPolicy,
            recentLogs: allLogs
        )

        // 5. Refresh the forgiving Consistency Score onto the user aggregate.
        var updatedUser = handoff.user
        updatedUser.consistency = try await consistencyService.consistency(
            for: allLogs,
            weeklyGoal: latest.consistency.weeklyGoal
        )

        // 6. Persist the user (advanced cold-start + refreshed consistency), then the reconciled policy
        //    only when the handoff actually changed it (i.e. cold-start just retired and cleared the
        //    contract). The two aggregates are saved separately, matching US-F03.
        try await userService.save(updatedUser)
        if handoff.sessionPolicy != currentPolicy {
            try await policyStore.save(handoff.sessionPolicy, for: latest.id)
        }

        // 7. Mirror the completed session into Health (US-N03), best-effort and fully isolated: a denied
        //    authorization or any HealthKit failure must never disrupt the bookkeeping above or block the
        //    completion. The service enforces idempotency by the log id, so a re-record never duplicates.
        if let healthKitService {
            try? await healthKitService.saveWorkoutLog(log, user: latest)
        }

        // 8. Emit `week_active` at most once per distinct active week (US-T11). This is last and fully
        //    isolated from the throwing bookkeeping above - a telemetry emission must never affect
        //    whether the completion the user earned is recorded.
        await emitWeekActive(for: log)
    }

    /// Emit `week_active` iff this completed session is the first the account has logged in its calendar
    /// week - the "Weekly Active Exercisers" North Star and kill-criterion K4 signal (US-T11).
    ///
    /// **Reuses the existing rollup's bucketing rather than re-deriving one.** `ProgressAnalytics`
    /// keys its `sessionsByWeek` off `ConsistencyScore.startOfWeek(log.completedAt, calendar)`; this
    /// keys off that *same function and the same `log.completedAt` vantage*, so "which week" is defined
    /// once. What differs is the calendar handed in: the emission cadence buckets in
    /// `AppState.cohortCalendar` (Gregorian, Sunday-start, Pacific), **not** the `Calendar.current` the
    /// on-device rollup uses. That is the one decision US-T11 owns, and it mirrors the split US-T05
    /// established for `install_week`: `week_active` carries no properties, so the server can only bucket
    /// it by client timestamp; emitting on each device's own week boundary would let one install land
    /// twice inside one server week and zero in another, so K4's numerator (device-local weeks) and
    /// denominator (pinned cohort weeks) would be two different definitions of "week". The Consistency
    /// Score stays on `Calendar.current` because a user's training week is their local week - the two
    /// calendars are coupled, change one only with the other.
    ///
    /// Emit-once is enforced by a *persisted* set of already-emitted week-starts, so a second session in
    /// the same week is a no-op that survives relaunch. The week is marked before the fire-and-forget
    /// `record(_:)` and independently of consent: consent lives only in the sink (US-T06), and an
    /// emission site must never re-check the gate itself - so an opted-out week is still consumed,
    /// exactly as the app-entry return events treat their launch-state dedup.
    private func emitWeekActive(for log: WorkoutLog) async {
        guard let analytics else { return }

        let weekStart = ConsistencyScore.startOfWeek(log.completedAt, emissionCalendar)
        let weekKey = Int(weekStart.timeIntervalSince1970.rounded())

        var emitted = userDefaults.array(forKey: Self.weekActiveEmittedWeeksKey) as? [Int] ?? []
        guard !emitted.contains(weekKey) else { return }
        emitted.append(weekKey)
        userDefaults.set(emitted, forKey: Self.weekActiveEmittedWeeksKey)

        // `week_active` carries no properties, per the pre-registered schema.
        let event = AnalyticsEvent(name: .weekActive, timestampMs: Int(now().timeIntervalSince1970 * 1000))
        await analytics.record(event)
    }

    func recordPerceivedDifficulty(_ difficulty: PerceivedDifficulty?, forLog log: WorkoutLog) async throws {
        // 1. A minimal re-save of the one log by its stable id (`save` is an upsert), setting only the
        //    rating. No Consistency refresh and no counter advance - the rating changes neither, and
        //    re-running the handoff would double-advance cold-start for a session already recorded.
        var rated = log
        rated.perceivedDifficulty = difficulty
        try await workoutLogService.save(rated)

        // 2. Fold the rating into the recorded Start Seed band (US-O02). The retiring session's rating
        //    always arrives here rather than at the handoff, so without this an explicit `tooHard` on
        //    the fifth session would never reach the band the rest of the account is measured against.
        //    Best-effort and idempotent: the floor is re-resolved from the recorded aim over the
        //    cold-start sessions, so repeating or changing a rating converges rather than compounding,
        //    and a failure here must never fail the rating write the user actually asked for.
        guard let latest = try? await userService.currentUser(),
              latest.coldStart.bandAimAtHandoff != nil,
              let allLogs = try? await workoutLogService.workoutLogs(from: nil, to: nil)
        else { return }
        let revised = ColdStartHandoff.revisedBandFloor(
            latest,
            coldStartLogs: ColdStartHandoff.coldStartWindowLogs(allLogs)
        )
        if revised != latest {
            try? await userService.save(revised)
        }
    }
}
