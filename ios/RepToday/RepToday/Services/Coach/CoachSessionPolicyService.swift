import Foundation

/// The on-device, sovereign write path for a **coach-sourced** `SessionPolicy` change (US-AC07, FR-11):
/// the second writer of the one per-user policy, beside the deterministic Programmer
/// (`DeterministicSessionPolicyService`). It turns a bounded `CoachPolicyProposal` into a validated,
/// clamped, preference-only policy write tagged `updatedBy == .llm`, persisted through the **same**
/// `SessionPolicyStore` the Programmer uses - so the engine reads the coach's nudge on the next open,
/// exactly like a re-program (never mid-session).
///
/// It mirrors `DeterministicSessionPolicyService.reprogram`'s shape: the *pure* lever logic lives on
/// `SessionPolicy` (`applyingCoachProposal`), and this service owns only the *orchestration and
/// persistence* - increment `version`, stamp `updatedBy == .llm` and the injected `asOf` (never the wall
/// clock), write the honest note (`PolicyNote.coachTemplated`), and persist. No workout is ever generated;
/// it only writes policy.
///
/// **Two writers, one policy - safety > preference, structurally (ADR-0005).** The load-bearing move is
/// that this service *re-reads the current in-force policy from the store* and overlays only the coach's
/// preference levers onto it, rather than replacing it. Because the deterministic Programmer's safety moves
/// touch levers the coach either cannot (a de-load's/Re-entry's lever is disjoint from `patternEmphasis`)
/// or can only push further in the safe direction (`progressionRate` eased down only, `varietyWindow`
/// narrowed only), a coach write that lands *after* a deterministic de-load can never undo it - and the
/// clamp pins any out-of-range proposal to the rails first. This is not a last-writer-wins overwrite; it is
/// a safety-sovereign overlay.
protocol CoachPolicyServiceProtocol {
    /// Apply `proposal` to `user`'s current in-force policy as of `asOf`, persisting and returning the
    /// newly-written policy - or `nil` when the proposal moved no preference lever after clamping (a no-op
    /// the coach recognized but that changes nothing in force), in which case nothing is written and the
    /// in-force policy (and its note) is left untouched.
    func applyProposal(
        _ proposal: CoachPolicyProposal,
        for user: User,
        asOf: Date
    ) async throws -> SessionPolicy?
}

final class CoachSessionPolicyService: CoachPolicyServiceProtocol {

    /// The same per-user policy store the deterministic Programmer writes through, so the two writers share
    /// one in-force policy (the whole point of the two-writer safety story). An in-memory store backs tests;
    /// `CoreDataSessionPolicyStore` backs the app.
    private let store: any SessionPolicyStore

    init(store: any SessionPolicyStore) {
        self.store = store
    }

    func applyProposal(
        _ proposal: CoachPolicyProposal,
        for user: User,
        asOf: Date
    ) async throws -> SessionPolicy? {
        // 1. Re-read the *freshest* in-force policy - the safety-sovereign overlay's foundation. If a
        //    deterministic de-load / Re-entry Ramp landed since the user last spoke to the coach, it is
        //    already here, and the overlay below preserves it.
        let current = try await store.policy(for: user.id) ?? .default

        // 2. Overlay only the preference levers, each clamped to the engine's rails and direction-safe
        //    (emphasis disjoint; rate ease-down-only; window narrow-only). Pure, no clock.
        let overlaid = current.applyingCoachProposal(proposal)

        // 3. Honest no-op guard: if nothing a coach can move actually moved (everything clamped away, or
        //    already at the in-force value), write nothing and leave the in-force policy - and its note -
        //    exactly as the deterministic Programmer left it.
        guard overlaid.coachLeversDiffer(from: current) else { return nil }

        // 4. Write the honest note from the real before/after diff - guaranteed non-nil here because a
        //    moved lever always yields a clause (pinned by test).
        var next = overlaid
        next.note = PolicyNote.coachTemplated(policyBefore: current, policyAfter: next)

        // 5. Stamp provenance: newest version, coach-sourced, injected time. `updatedBy == .llm` is the
        //    inseparable mark of a coach write (the easing seams already set it; this makes an
        //    emphasis-only write carry it too).
        next.version = current.version + 1
        next.updatedBy = .llm
        next.updatedAt = asOf

        try await store.save(next, for: user.id)
        return next
    }
}
