import Foundation

/// The on-device, deterministic AI Programmer at option (C) (Epic F, US-F03): the real
/// `SessionPolicyServiceProtocol` that quietly re-tunes a user's Session Policy when a trigger
/// fires, so sessions stay winnable and progressive without the user ever waiting.
///
/// This is the seam where the Programmer's four pure pieces finally compose:
/// - `ReprogramTriggerDetection` (US-F01) decides *which* triggers are due on open, in precedence
///   order, from the injected clock.
/// - `PlateauDiagnosis` (US-F02) tells a Physical Stall (add challenge) from a Disengagement
///   (reduce friction) and maps each to the `progressionRate` / `varietyWindow` levers.
/// - `DefaultDurationLearning` (US-F04) folds what the user actually *finishes* into the learned
///   Default Duration surfaced on the Ready Screen.
/// - `PolicyNote` (US-F04) writes the honest, templated note from the *real* lever/duration diff.
///
/// The service owns only the *orchestration and persistence* those pure pieces deliberately left
/// to it: it increments `version`, stamps `updatedBy == .deterministic` and the injected
/// `updatedAt`, seeds the Re-entry Ramp on a Return (US-E06), writes the note, and persists the new
/// policy (via the injected `SessionPolicyStore`) plus the learned duration (via `UserServiceProtocol`).
/// It **never generates or returns a workout** - it only writes policy; the deterministic engine
/// (Epic E) reads that policy on the next open.
///
/// **Trigger Precedence is upheld end-to-end.** A `physical_stall` or `disengagement` trigger is not
/// applied blindly: the service re-diagnoses the freshest history through `PlateauDiagnosis.diagnose`
/// (which resolves precedence at the source, disengagement winning), so a stall trigger can never
/// hand more challenge to a user who has since begun pulling away.
///
/// The two policy calls are the only asynchronous work, and both are pure over their inputs plus the
/// small persistence seam. The client (US-J02) calls `dueTriggers` on open and, if any are due,
/// `reprogram` against the highest-precedence one in the background - the app renders from the
/// existing policy immediately and the freshly written one applies on the next open.
final class DeterministicSessionPolicyService: SessionPolicyServiceProtocol {

    /// Persists the single current policy per user, so the last-written policy survives relaunch
    /// and offline use (US-D03). An in-memory store backs tests and previews; the CoreData-backed
    /// store (`CoreDataSessionPolicyStore`) backs the running app.
    private let store: any SessionPolicyStore

    /// Supplies the validated catalog the stall signal needs to resolve advancement criteria and
    /// chain position (`ReprogramTriggerDetection`/`PlateauDiagnosis` take the library explicitly).
    private let exerciseService: any ExerciseServiceProtocol

    /// Persists the learned Default Duration back onto the user aggregate (US-F04). The policy and
    /// the user are separate aggregates, so folding duration learning writes through this seam
    /// rather than smuggling a user mutation back through the policy.
    private let userService: any UserServiceProtocol

    init(
        store: any SessionPolicyStore,
        exerciseService: any ExerciseServiceProtocol,
        userService: any UserServiceProtocol
    ) {
        self.store = store
        self.exerciseService = exerciseService
        self.userService = userService
    }

    // MARK: - Reading

    /// The policy currently in force for `user` - the last-written policy, or `SessionPolicy.default`
    /// until the Programmer has ever run (US-D03), so the engine always has a valid policy to read.
    func currentPolicy(for user: User) async throws -> SessionPolicy {
        try await store.policy(for: user.id) ?? .default
    }

    /// Seed and persist the freshly-onboarded user's starting policy (US-I01/US-G01): the neutral
    /// default with a cold-start contract capped from the self-reported fitness level and First-Week
    /// Contrast forced on. Written through the same `SessionPolicyStore` as a re-program so it
    /// survives relaunch and offline use, and the engine's Step 0 overrides (US-E04) apply from the
    /// very first session. This is a *seed*, not a re-program: it keeps `default`'s `version`/
    /// `updatedBy == .default`, so the first actual re-program still reads a clean starting point.
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy {
        let policy = SessionPolicy.seeded(forFitnessLevel: user.profile.fitnessLevel)
        try await store.save(policy, for: user.id)
        return policy
    }

    /// The re-program triggers due as of `asOf`, in precedence order (US-F01). Adapts the
    /// library-taking `ReprogramTriggerDetection.dueTriggers` to the protocol's library-free
    /// signature by supplying the validated catalog from the exercise service.
    func dueTriggers(
        user: User,
        recentLogs: [WorkoutLog],
        asOf: Date
    ) async throws -> [ReprogramTrigger] {
        let library = try await exerciseService.exercises()
        return ReprogramTriggerDetection.dueTriggers(
            user: user,
            recentLogs: recentLogs,
            library: library,
            asOf: asOf
        )
    }

    // MARK: - Re-programming

    /// Write and return a fresh policy in response to `trigger` (US-F03).
    ///
    /// The new policy is the current one with:
    /// - its optimization levers moved per the trigger (a Physical Stall accelerates, a
    ///   Disengagement eases, a Return seeds the Re-entry Ramp, a Weekly Boundary re-tunes only
    ///   the learned duration) - always precedence-safe, so a disengaging user is never handed more
    ///   challenge,
    /// - `version` incremented and `updatedBy == .deterministic`,
    /// - `updatedAt` stamped from the trigger's injected `detectedAt` (never the wall clock), and
    /// - an honest templated `note` naming only the changes the sessions will actually reflect.
    ///
    /// It also folds Default Duration learning over the sessions completed since the last policy
    /// write and persists both the new policy and (when it changed) the learned duration. No workout
    /// is ever generated or returned.
    func reprogram(
        user: User,
        recentLogs: [WorkoutLog],
        trigger: ReprogramTrigger
    ) async throws -> SessionPolicy {
        let current = try await currentPolicy(for: user)
        let library = try await exerciseService.exercises()

        // 1. Move the optimization levers for this trigger (precedence-safe re-diagnosis inside).
        var next = leveled(current, for: trigger, recentLogs: recentLogs, library: library)

        // 2. Fold Default Duration learning over only the newly-completed sessions, so the EWMA
        //    never double-counts a session across re-programs.
        let learnedDuration = DefaultDurationLearning.learned(
            user.duration,
            from: newlyCompletedLogs(recentLogs, since: current)
        )
        let durationChange = PolicyNote.DurationChange(
            before: user.duration.defaultMinutes,
            after: learnedDuration.defaultMinutes
        )

        // 3. Write the honest note from the real diff between the current and re-weighted policy,
        //    plus any learned-duration change - never from the trigger's intent.
        let note = PolicyNote.templated(
            policyBefore: current,
            policyAfter: next,
            durationChange: durationChange
        )

        // 4. Stamp provenance. The version increment marks this as the newest policy; the injected
        //    `detectedAt` keeps re-programming deterministic and time-injected.
        next.version = current.version + 1
        next.updatedBy = .deterministic
        next.updatedAt = trigger.detectedAt
        next.note = note

        // 5. Persist the learned duration onto the user aggregate first, then the policy. The
        //    policy's `updatedAt` is the dedup boundary for `newlyCompletedLogs`, so it must only
        //    advance after the duration derived from those sessions is durably saved. If the policy
        //    write then fails, the next re-program re-folds those sessions (a minor, self-correcting
        //    EWMA smoothing artifact) rather than permanently losing them to Default Duration learning.
        if learnedDuration != user.duration {
            var updated = user
            updated.duration = learnedDuration
            try await userService.save(updated)
        }
        try await store.save(next, for: user.id)
        return next
    }

    // MARK: - Lever mapping

    /// Move `policy`'s optimization levers for `trigger`, leaving `version`/`updatedBy`/`note` to the
    /// caller. Plateau triggers re-diagnose the freshest history so precedence holds end-to-end.
    private func leveled(
        _ policy: SessionPolicy,
        for trigger: ReprogramTrigger,
        recentLogs: [WorkoutLog],
        library: [Exercise]
    ) -> SessionPolicy {
        switch trigger.kind {
        case .physicalStall, .disengagement:
            // Re-diagnose rather than trust the trigger's kind: `diagnose` resolves Trigger
            // Precedence at the source, so a stalled-then-disengaging user eases (never accelerates),
            // and a history that has since recovered moves no lever at all.
            guard let plateau = PlateauDiagnosis.diagnose(recentLogs: recentLogs, library: library) else {
                return policy
            }
            return PlateauDiagnosis.reweighted(policy, for: plateau)

        case .return:
            // Discipline overrides optimization: the Return itself carries no readjustment. Seeding
            // the Re-entry Ramp is the only policy change; the engine (US-E06) holds difficulty
            // below normal and walks it back over these sessions. Optimization levers are untouched.
            var next = policy
            next.reentry = SessionPolicy.Reentry(rampSessionsRemaining: ReturnOverride.rampSessions)
            return next

        case .weeklyBoundary:
            // The routine weekly re-tune moves no optimization lever on its own - a genuine plateau
            // would already have fired its own higher-precedence trigger. Default Duration learning
            // (folded by the caller) is the change a weekly boundary actually delivers.
            return policy
        }
    }

    /// The sessions to fold into Default Duration learning: only those completed strictly after the
    /// current policy was last written, so an EWMA update happens once per session across re-programs.
    ///
    /// `SessionPolicy.default`'s sentinel epoch (2001) predates every real log, so the first
    /// re-program folds the full history; each later re-program folds only what accrued since it.
    ///
    /// Return sessions (`wasReturn`) are excluded: they are deliberately short, easy, and capped
    /// (US-E06), so folding their `durationMinutes` would drag the learned Default Duration down and
    /// soft-penalize a comeback - and a Return is celebrated, never penalizing (US-D02/US-E06).
    private func newlyCompletedLogs(_ logs: [WorkoutLog], since policy: SessionPolicy) -> [WorkoutLog] {
        logs.filter { $0.completedAt > policy.updatedAt && !$0.wasReturn }
    }
}

// MARK: - Policy persistence seam

/// Persists the single current `SessionPolicy` per user (US-D03), keyed by the user's id and
/// overwritten in place so a user keeps one current policy, never a growing history.
///
/// A protocol so the deterministic Programmer is testable without CoreData: `InMemorySessionPolicyStore`
/// backs tests and previews, while `CoreDataSessionPolicyStore` (Persistence) backs the running app
/// and, via `CDSessionPolicy`, lets the last-written policy survive relaunch and offline use.
protocol SessionPolicyStore {
    /// The current policy for `userId`, or `nil` when the Programmer has never written one.
    func policy(for userId: String) async throws -> SessionPolicy?
    /// Overwrite the current policy for `userId` in place (insert or update).
    func save(_ policy: SessionPolicy, for userId: String) async throws
    /// Delete the stored policy for `userId` for account deletion (US-AD02), then save so the
    /// CloudKit mirror propagates the tombstone. A no-op (never an error) when none is stored.
    func delete(for userId: String) async throws
}

/// An in-memory `SessionPolicyStore` for tests, previews, and the mock container. Deterministic and
/// isolated per instance; nothing is written to disk.
actor InMemorySessionPolicyStore: SessionPolicyStore {
    private var policies: [String: SessionPolicy]

    init(policies: [String: SessionPolicy] = [:]) {
        self.policies = policies
    }

    func policy(for userId: String) async throws -> SessionPolicy? {
        policies[userId]
    }

    func save(_ policy: SessionPolicy, for userId: String) async throws {
        policies[userId] = policy
    }

    func delete(for userId: String) async throws {
        policies.removeValue(forKey: userId)
    }
}
