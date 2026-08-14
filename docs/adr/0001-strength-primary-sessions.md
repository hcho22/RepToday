# ADR-0001: Strength-primary sessions (co-primary -> strength-primary)

- Status: Accepted (captain-accepted)
- Date: 2026-08-12
- Deciders: captain, via the "Strength-Primary Sessions" PRD (2026-08-12)
- Supersedes: the earlier "mobility is co-primary" framing carried forward from the v5/v6 strategic PRDs (`.claude/agent/tasks/`)

This is the first ADR in the repository; `docs/adr/` is created here.

## Context

Rep Today originally framed **mobility (Movement Practice) as co-primary with strength** and explicitly "not a warm-up" - a differentiator meant to give a stiff desk worker same-day relief.
In the engine this let the pillar-balance step (Step 2) choose the leading pillar by staleness and by the `sitsLong` desk-worker signal.

That framing produced a concrete failure: a user with a short window could receive a session that was **entirely mobility** - the reported all-mobility 5-minute session, all stretches, with no strength work at all.
For a discipline-first strength product this is the wrong default: the promise is that a user who shows up trains, and strength is the earned outcome the product is built around; a day that resolves to pure stretching undercuts that on exactly the short sessions most users actually do.

## Decision

> **Update (US-M01, 2026-08-13):** the **strength-leads-every-session invariant below stands**, but the "mobility survives as a minority accessory training block (Movement Practice)" clause is **retired**. The Movement Practice block is no longer emitted at any length, its split machinery (`PillarBalance`/`PillarWeights`) is removed, and the minutes it held were reallocated to strength. Mobility now survives *only* as the warm-up and cooldown bookends, and the strength lead is structural (the engine builds every session as Warm-Up -> Strength (-> Primal at 41-60) -> Cooldown). `sitsLong` no longer sizes anything (currently inert). Read the "mobility accessory" language in this ADR as the pre-US-M01 state; the change is specified in the "Movement Practice removal" follow-on of `.claude/agent/tasks/prd-strength-primary-sessions_260812.md` (a later ADR-0002 will formally record it).

**Strength is the primary pillar of every session.**
Across single-focus, blend, cold-start, and Return sessions, strength leads; mobility is supporting only - the structural warm-up and the cooldown (before US-M01, also a minority accessory block, Movement Practice).

Specifically, and with **no mobility safety valve** that can flip the lead:

- A single-focus (5-10 min) session always trains strength, independent of staleness and `sitsLong`; mobility survives only as the warm-up (US-001).
- A blend is a fixed strength-dominant envelope with mobility a minority accessory, sized by a base share rather than by staleness (US-002). *(US-M01: the mobility accessory block is removed; a blend is now a strength session wrapped in mobility bookends.)*
- The warm-up is lean and length-scaled so it does not crowd out strength in a tiny session (US-003).
- The cold-start first week leads strength, replacing the retired First-Week Contrast rotation (US-004).
- A returning-user comeback leads strength too, kept gentle by the difficulty cap and volume floor rather than by switching to mobility (US-005).
- `sitsLong` no longer picks the lead; it only modulates the *size* of the mobility accessory.
- The vocabulary and this record close the change (US-006): the code's doc notes and the project docs describe strength-primary, and the co-primary -> strength-primary decision is recorded here so it cannot be re-introduced from stale prose.
- A cross-cutting regression guard pins the invariant structurally (US-007): a single consolidated test (`StrengthPrimaryRegressionTests`) sweeps every length across steady-state, cold-start, and Return and fails loudly if any session becomes mobility-led, so a future tuning change cannot silently re-add a mobility-only session.

The implementation is documentation-and-engine work already landed as US-001..US-007 (see `docs/implementation-log.md`); the engine mechanics live under `Services/Engine/` (`SessionAssembly.swift` builds the blocks; the Step 0 cold-start / Return overrides supply the gentleness rails - the `PillarBalance.swift` split step this ADR originally cited was removed by US-M01), and the vocabulary lives in `Models/Enums.swift` (`Pillar`) and `CONTEXT.md`.

## Consequences / Trade-offs

Positive:

- The reported all-mobility short session is structurally impossible; a user who shows up always trains strength.
- The pillar lead is now a deterministic property of the session, not a staleness/`sitsLong` accident, which is simpler to reason about and to test.
- Positioning stays discipline-first (daily consistency, identity-framed) while the engine is unambiguously strength-primary; the two are decoupled, so this is an engine decision, not a repositioning.

Accepted trade-offs (the sharpest, captain-accepted):

- **A user who only ever does 5-10 min sessions gets mobility solely as the warm-up** - there is no longer a short session that is a dedicated mobility day.
- **Desk workers (`sitsLong`) lose a dedicated same-day mobility-relief day.** `sitsLong` originally only enlarged the mobility accessory's volume within a strength-led blend; it never made mobility the lead. *(US-M01: the accessory block is gone, so `sitsLong` is currently inert - US-M03 will repurpose it to bias bookend selection.)* The same-day-relief differentiator the co-primary framing leaned on is given up on the engine side.

These trade-offs were surfaced in the PRD and **accepted by the captain**; this ADR records them so a future contributor does not re-add a mobility safety valve believing it to be a missing feature rather than a deliberately removed one.

Scope note: **GTM/marketing positioning is out of scope of this decision.** The `gtm/**` package still carries co-primary framing and is captain-owned, tracked under a separate task; this ADR governs the product/engine vocabulary and behavior only.
