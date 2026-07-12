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
///   `user.coldStart.sessionsLogged` and retires cold-start once the threshold is reached, then
///   reconciles the policy (clearing the now-inert `coldStartContract`). The user and policy are
///   separate aggregates, so they are persisted separately.
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
    /// caller stability, but the Consistency Score is recomputed over the full persisted history so the
    /// all-time `longestChain` (US-H01) is never understated by a bounded window.
    func recordCompletedSession(_ log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws
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

    init(
        workoutLogService: any WorkoutLogServiceProtocol,
        userService: any UserServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol,
        policyStore: any SessionPolicyStore
    ) {
        self.workoutLogService = workoutLogService
        self.userService = userService
        self.consistencyService = consistencyService
        self.policyStore = policyStore
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

        // 3. Advance cold-start and reconcile the policy against the just-completed session (US-G04).
        //    The policy read falls back to the neutral default until the Programmer has ever written
        //    one, exactly as `currentPolicy(for:)` does.
        let currentPolicy = try await policyStore.policy(for: latest.id) ?? .default
        let handoff = ColdStartHandoff.afterCompletedSession(user: latest, sessionPolicy: currentPolicy)

        // 4. Refresh the forgiving Consistency Score onto the user aggregate over the *full* persisted
        //    history (which now includes the just-saved `log`), not the caller's bounded `recentLogs`.
        //    `longestChain` is an all-time historical maximum (US-H01: "a later break never lowers it"),
        //    so scoring over a bounded window would understate and overwrite the earned best run.
        let allLogs = try await workoutLogService.workoutLogs(from: nil, to: nil)
        var updatedUser = handoff.user
        updatedUser.consistency = try await consistencyService.consistency(
            for: allLogs,
            weeklyGoal: latest.consistency.weeklyGoal
        )

        // 5. Persist the user (advanced cold-start + refreshed consistency), then the reconciled policy
        //    only when the handoff actually changed it (i.e. cold-start just retired and cleared the
        //    contract). The two aggregates are saved separately, matching US-F03.
        try await userService.save(updatedUser)
        if handoff.sessionPolicy != currentPolicy {
            try await policyStore.save(handoff.sessionPolicy, for: latest.id)
        }
    }
}
