import Foundation

/// The cold-start handoff (US-G04): the one-way retirement that hands a warmed-up user off from the
/// Step 0 cold-start overrides to the self-driving engine once there is enough history for staleness
/// and Adaptive Overload to steer sessions unassisted.
///
/// Cold start (US-E04/US-G01/US-G02/US-O02) governs roughly the first five sessions - it caps Starting
/// Difficulty, bands the strength/primal pool and its opening volume to the Start Seed, and leads
/// every day with strength (US-004, reversing the retired First-Week Contrast spread), so a brand-new
/// user's first week is gentle, level-appropriate and strength-building. But
/// those overrides are training wheels, not the engine: once the user has logged enough real sessions
/// the engine has the history it needs (worked pillars, cleared tiers, demonstrated capacity) to drive
/// itself, and the overrides must retire so they never keep flattening variety or capping difficulty
/// for a user who has outgrown them.
///
/// The handoff is deliberately a thin bookkeeping step, not a decision the engine re-litigates every
/// session. It touches exactly the two pieces of state Step 0 reads and is otherwise inert:
///
/// - **`user.coldStart`** - `sessionsLogged` increments on each completed session and `active` flips
///   off (one-way) the moment the count reaches `handoffThreshold`. This is the switch
///   `ColdStartOverride.isActive` reads; once it is false, Step 0 is a no-op. In the same move the
///   Start Seed floor the week actually ran at is recorded as `bandFloorAtHandoff` (with the
///   contract's un-eased aim beside it), so Step 5 can still tell "the engine never let this user see
///   this movement" from "they outgrew it" long after the cold-start sessions have aged out of the
///   engine's bounded log window. The retiring session's own rating arrives after this - it is
///   collected on the completion screen - so `revisedBandFloor(_:coldStartLogs:)` folds it into that
///   recorded floor without ever re-advancing the counter.
/// - **`sessionPolicy.coldStartContract`** - cleared to `nil` once cold-start is no longer active, so
///   the policy that reaches the engine carries no cold-start levers at all. Clearing the contract is
///   belt-and-suspenders with the `active` flag: Step 0 is gated on *both*, so either one retiring is
///   enough to make it a no-op, and a policy with no contract is exactly `SessionPolicy.default`'s
///   cold-start shape, so every Step 0 *override* is inert from the sixth session on.
///
/// The one thing that deliberately outlives the retirement is the recorded band. Sessions from the
/// sixth on are not quite plain US-E03: Step 5 keeps reading `bandFloorAtHandoff` through
/// `ColdStartOverride.withheldByStartSeed`, so a chain the band never put on offer is not mistaken for
/// a fresh one and handed to an advanced user as the variety pick. That is the cliff these fields
/// exist to close, and it withholds nothing for a user who never ran a band.
///
/// Like the rest of the pipeline this is a pure function of its inputs - there is no wall-clock read;
/// the "how far into cold start" signal is the logged-session count itself - so the handoff is
/// deterministic and unit-testable. `SessionCompletionService` is the only caller, through two entry
/// points: the post-session log-writer (US-L01) calls `afterCompletedSession` to advance the state,
/// record the band and reconcile the policy - persisting the user and policy aggregates separately (as
/// US-F03 does) so the retirement survives relaunch - and the rating write (US-L02) calls
/// `revisedBandFloor` to fold a late `tooHard` into the already-recorded floor, moving no counter.
enum ColdStartHandoff {

    // MARK: - Tuning constant

    /// The number of completed sessions after which cold-start retires and the engine drives itself
    /// unassisted (PRD provisional `5`; the v6 range is 5-7). The flip happens the moment
    /// `sessionsLogged` reaches this count - i.e. immediately after the fifth completed session.
    static let handoffThreshold = 5

    // MARK: - Advancing cold-start state

    /// The cold-start state after one more completed session: `sessionsLogged` incremented and `active`
    /// flipped off once the count reaches `handoffThreshold`.
    ///
    /// The retirement is **one-way** - once `active` is false the state is frozen and further completed
    /// sessions are a no-op, so a user can never fall back into cold start (a later gap is the Return
    /// override's job, US-E06, not cold start's).
    ///
    /// `band` is the Start Seed floor the week ran at, paired with the contract's un-eased aim it was
    /// eased from. It is written **only** on the session that retires cold-start, and only there,
    /// because that is the one moment the floor is still knowable: the recording is the whole point of
    /// the fields.
    ///
    /// It is deliberately a required parameter with no default. A defaulted `.unbanded` would let any
    /// caller that simply forgot the argument record "no band ran" and permanently discard the cliff
    /// protection those fields exist to provide - failing silently, in the one direction that cannot be
    /// noticed later. Callers with genuinely no band in play pass `.unbanded` explicitly.
    static func advanced(_ coldStart: User.ColdStart, band: BandRecord) -> User.ColdStart {
        guard coldStart.active else { return coldStart }
        let logged = coldStart.sessionsLogged + 1
        let retiring = logged >= handoffThreshold
        return User.ColdStart(
            sessionsLogged: logged,
            active: !retiring,
            bandFloorAtHandoff: retiring ? band.floor : coldStart.bandFloorAtHandoff,
            bandAimAtHandoff: retiring ? band.aim : coldStart.bandAimAtHandoff
        )
    }

    /// The user with their cold-start state advanced by one completed session (see `advanced(_:band:)`).
    /// Only `coldStart` changes; every other field is carried through untouched.
    static func advanced(_ user: User, band: BandRecord) -> User {
        var updated = user
        updated.coldStart = advanced(user.coldStart, band: band)
        return updated
    }

    // MARK: - The recorded band

    /// The Start Seed band a cold-start week ran under, as recorded at the handoff: the contract's
    /// un-eased floor `aim` and the `floor` that aim actually eased to. Both are recorded because the
    /// retiring session's own `tooHard` rating always arrives *after* the handoff (it is collected on
    /// the completion screen, once the log is already written), and re-resolving the floor from the aim
    /// is the only way to fold that rating in exactly rather than by guessing a step size.
    struct BandRecord: Equatable {
        /// The contract's un-eased Start Seed floor - what the self-report aimed the week at.
        var aim: Int
        /// What that aim actually eased to over the week, one tier per `tooHard` rating. This is the
        /// floor Step 5 reads afterwards; `aim` exists only to re-resolve it.
        var floor: Int

        /// The record for a user who never ran a banded cold start - a caller with no cold-start
        /// contract in play, or a contract carrying the neutral floor. Withholds nothing.
        static let unbanded = BandRecord(
            aim: SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor,
            floor: SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        )
    }

    /// The cold-start sessions themselves: the first `handoffThreshold` logs in date order. The band
    /// is a claim about *that* week, so both the recording and any later revision of it count
    /// down-signals over exactly this set - a `tooHard` rating on a much later session can neither
    /// widen nor narrow a band that retired long before it.
    static func coldStartWindowLogs(_ allLogs: [WorkoutLog]) -> [WorkoutLog] {
        Array(allLogs.sorted { $0.completedAt < $1.completedAt }.prefix(handoffThreshold))
    }

    /// The cold-start state with its recorded band floor re-resolved against the now-rated cold-start
    /// sessions, for a rating that landed after the handoff.
    ///
    /// This deliberately touches only the derived floor - `sessionsLogged` and `active` are carried
    /// through untouched - so it can be called on every rating without ever double-advancing cold
    /// start. It is idempotent: the floor is recomputed from the recorded aim and the full set of
    /// cold-start ratings, never stepped relative to its own previous value, so re-rating (or
    /// re-recording the same rating) converges on the same answer. A user who never rates keeps
    /// exactly the floor the handoff recorded.
    static func revisedBandFloor(_ user: User, coldStartLogs: [WorkoutLog]) -> User {
        guard !user.coldStart.active, let aim = user.coldStart.bandAimAtHandoff else { return user }
        var updated = user
        updated.coldStart.bandFloorAtHandoff = ColdStartOverride.easedDifficultyFloor(
            aim: aim,
            tierDownSignals: ColdStartOverride.tierDownSignalCount(recentLogs: coldStartLogs)
        )
        return updated
    }

    // MARK: - Reconciling the policy

    /// The policy with its `coldStartContract` cleared once cold-start is no longer active, so Step 0
    /// becomes a no-op and the engine runs the plain US-E03 pipeline. A no-op while cold-start is still
    /// active or the contract is already absent, and it moves no other lever - clearing the contract is
    /// a mechanical retirement, not a re-program (the version and `updatedBy` are the Programmer's, so
    /// they are deliberately left untouched here).
    static func reconciled(_ policy: SessionPolicy, with coldStart: User.ColdStart) -> SessionPolicy {
        guard !coldStart.active, policy.coldStartContract != nil else { return policy }
        var updated = policy
        updated.coldStartContract = nil
        return updated
    }

    // MARK: - Combined handoff

    /// The user and policy after a completed session, reconciled together: the Start Seed floor in
    /// force is resolved from the pre-handoff user and policy, the user's cold-start state is advanced
    /// (recording that floor if this is the retiring session), then the policy is reconciled against
    /// that *advanced* state so the contract is cleared in the same step the `active` flag flips off.
    /// This is the single entry point the post-session log-writer (US-L01) calls; the two aggregates
    /// are returned separately because they are persisted separately.
    ///
    /// `recentLogs` must include the just-completed session, so the floor recorded is the one the whole
    /// week ran at: easing is monotonic (`ColdStartOverride.startSeed` only ever steps the floor down),
    /// so the floor resolved over every cold-start session is the lowest any single one of them ran at,
    /// and a movement was "never on offer" exactly when it sits beneath it. Only the cold-start window
    /// itself is counted (`coldStartWindowLogs`); a later session's rating is not evidence about a band
    /// that had already retired.
    ///
    /// It is deliberately a required parameter rather than a defaulted one: an empty history reads as
    /// "no down-signals", which would record the contract's un-eased *aim* instead of what actually ran.
    ///
    /// The retiring session's own rating is not in yet - it is collected on the completion screen,
    /// after the log is written - so the aim is recorded alongside the floor and
    /// `revisedBandFloor(_:coldStartLogs:)` folds that rating in when it lands.
    static func afterCompletedSession(
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> Outcome {
        let coldStartLogs = coldStartWindowLogs(recentLogs)
        let band = BandRecord(
            aim: ColdStartOverride.startSeedFloorAim(user: user, sessionPolicy: sessionPolicy),
            floor: ColdStartOverride.startSeed(
                user: user,
                sessionPolicy: sessionPolicy,
                recentLogs: coldStartLogs
            ).difficultyFloor
        )
        let advancedUser = advanced(user, band: band)
        let reconciledPolicy = reconciled(sessionPolicy, with: advancedUser.coldStart)
        return Outcome(user: advancedUser, sessionPolicy: reconciledPolicy)
    }

    /// The result of a cold-start handoff: the advanced user and the reconciled policy, each persisted
    /// on its own aggregate by the caller.
    struct Outcome: Equatable {
        var user: User
        var sessionPolicy: SessionPolicy
    }

}
