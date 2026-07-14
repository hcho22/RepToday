import Foundation

/// The cold-start handoff (US-G04): the one-way retirement that hands a warmed-up user off from the
/// Step 0 cold-start overrides to the self-driving engine once there is enough history for staleness
/// and Adaptive Overload to steer sessions unassisted.
///
/// Cold start (US-E04/US-G01/US-G02) governs roughly the first five sessions - it caps Starting
/// Difficulty and forces First-Week Contrast so a brand-new user's first week is gentle and vivid. But
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
///   `ColdStartOverride.isActive` reads; once it is false, Step 0 is a no-op.
/// - **`sessionPolicy.coldStartContract`** - cleared to `nil` once cold-start is no longer active, so
///   the policy that reaches the engine carries no cold-start levers at all. Clearing the contract is
///   belt-and-suspenders with the `active` flag: Step 0 is gated on *both*, so either one retiring is
///   enough to make it a no-op, and a policy with no contract is exactly `SessionPolicy.default`'s
///   cold-start shape - the engine behaves precisely as US-E03 from the sixth session on.
///
/// Like the rest of the pipeline this is a pure function of its inputs - there is no wall-clock read;
/// the "how far into cold start" signal is the logged-session count itself - so the handoff is
/// deterministic and unit-testable. The post-session log-writer (US-L01) is the single caller: after it
/// records a completed session it advances the cold-start state and reconciles the policy, persisting
/// the user and policy aggregates separately (as US-F03 does), so the retirement survives relaunch.
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
    static func advanced(_ coldStart: User.ColdStart) -> User.ColdStart {
        guard coldStart.active else { return coldStart }
        let logged = coldStart.sessionsLogged + 1
        return User.ColdStart(sessionsLogged: logged, active: logged < handoffThreshold)
    }

    /// The user with their cold-start state advanced by one completed session (see `advanced(_:)`).
    /// Only `coldStart` changes; every other field is carried through untouched.
    static func advanced(_ user: User) -> User {
        var updated = user
        updated.coldStart = advanced(user.coldStart)
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

    /// The user and policy after a completed session, reconciled together: the user's cold-start state
    /// is advanced first, then the policy is reconciled against that *advanced* state so the contract is
    /// cleared in the same step the `active` flag flips off. This is the single entry point the
    /// post-session log-writer (US-L01) calls; the two aggregates are returned separately because they
    /// are persisted separately.
    static func afterCompletedSession(user: User, sessionPolicy: SessionPolicy) -> Outcome {
        let advancedUser = advanced(user)
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
