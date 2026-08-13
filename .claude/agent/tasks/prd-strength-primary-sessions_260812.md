# PRD: Strength-Primary Sessions (RepToday)

**Opened:** 2026-08-12
**Status:** Complete - shipped. All seven stories (US-001 .. US-007) landed on `main` via PRs #96-#102. The engine change, the ADR (`docs/adr/0001-strength-primary-sessions.md`), and `CONTEXT.md` are all in-repo. This file is a post-implementation archive of the source PRD, committed after the fact to record the document through the project's PRD convention; the acceptance-criteria checkboxes below reflect the specification as authored and are left unchecked because they were tracked and satisfied on the implementation branches, not here.
**Story prefix:** `US-0##`.
**Source:** design grill captured in `for-reptoday-the-workouts-smooth-stardust.md` (2026-08-12).

---

_Date: 2026-08-12 · Source: design grill captured in `for-reptoday-the-workouts-smooth-stardust.md`_

## Introduction / Overview

RepToday's deterministic session engine currently treats **strength** and **mobility** as co-primary pillars. At the 5-10 minute lengths it produces a single-pillar session, and a desk-worker mobility lean frequently selects mobility - so a short session can be 100% stretches with zero strength (the reported case: a 5-min session of Cobra Stretch / Downward Dog / Standing Forward Fold / Puppy Pose / Wall Chest Opener / Ankle Rocks).

This feature reshapes the engine so **strength is the primary pillar of every session** and mobility becomes a supporting role (warm-up, cooldown, and a small accessory block). The change is scoped to the **engine mix only** - the "discipline-first" product framing, the dormant phase system, and the inert `PrimaryGoal` are all left untouched (internally, "discipline-first" is reframed as *daily consistency*, independent of whether the day's work is strength or mobility).

The exercise catalog already supports this: 38 strength + 7 primal movements across all patterns (push 9, squat 8, hinge 6, core 9, pull 6, locomotion 7) vs 26 mobility movements. No content change is required.

## Goals

- Every generated session (5-60 min) contains a real, leading strength block; no session is mobility-led by default.
- A 5-minute session is ~80% strength: one quick mobility warm-up movement + 2-3 strength movements.
- 11+ minute blended sessions are ~75-80% strength; mobility is a small accessory block.
- Strength-primary applies to all users; the desk-worker (`sitsLong`) flag only nudges mobility-accessory volume, never the lead.
- The two gentle windows (new-user first week, returning-user comeback) also lead strength, kept gentle via reduced volume / capped difficulty.
- Preserve the engine's determinism, `asOf`-purity, and per-request timing tolerance (±60s) at every length.

## User Stories

### US-001: Single-focus sessions always lead strength

**Description:** As a user doing a short (5-10 min) session, I want it to be a strength workout so that even my quickest sessions build strength instead of being all stretches.

**Acceptance Criteria:**

- [ ] `PillarBalance.singlePillar(...)` returns `.strength` unconditionally (the `sitsLong` mobility lean and the `strengthNeglectThresholdDays` path are removed).
- [ ] A single-focus session's training block is a strength block (primal folded in as today).
- [ ] Mobility still appears only as the warm-up at these lengths (structural warm-up rule preserved).
- [ ] Doc comments asserting "co-primary" / "desk-worker mobility lean" in `PillarBalance.swift` are updated.
- [ ] Unit tests pass (`xcodebuild ... test`).

**Validation Test:**

- **Setup:** Fresh (no-history) profile with `sitsLong = true` (the reported profile).
- **Steps:**
  1. Generate a 5-min session and a 10-min session.
  2. Inspect the block list and each block's pillar/category.
- **Expected Result:** Both sessions open with a mobility warm-up and then a strength training block. No mobility *training* block appears.
- **Failure Indicator:** Either session's training block is mobility, or no strength block is present.

### US-002: Blended sessions are strength-dominant (~75-80%)

**Description:** As a user doing an 11+ min session, I want strength to dominate the training time so that longer sessions feel strength-heavy, with mobility as a supporting accessory.

**Acceptance Criteria:**

- [ ] `PillarBalance.blendWeights(...)` makes strength the leading share, targeting ~0.75-0.80 for the strength/mobility split.
- [ ] `minBlendShare` lowered from `0.3` to `~0.2` so mobility is a genuine minority accessory (and strength can reach ~0.8).
- [ ] `sitsLong` / `activeUserStrengthBias` recast as a small modulation of the mobility-accessory share, not a lead selector.
- [ ] Staleness still modulates *within* the strength family (pattern focus), not strength-vs-mobility lead.
- [ ] Warm-up and cooldown remain mobility.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** No-history profile; generate at 20 and 30 min.
- **Steps:**
  1. Generate 20-min and 30-min sessions.
  2. Sum training-block seconds by pillar (exclude warm-up/cooldown) and compute the strength share.
- **Expected Result:** Strength training share is ~0.75-0.80 at both lengths; a small mobility accessory block is present; strength block leads.
- **Failure Indicator:** Strength share ≤ 0.6, or mobility leads, or no mobility accessory at all.

### US-003: Lean, length-scaled warm-up

**Description:** As a user, I want a short warm-up that doesn't crowd out strength in a tiny session, while longer sessions still get a fuller warm-up.

**Acceptance Criteria:**

- [ ] `SessionAssembly.warmupExerciseCount(forRequestedMinutes:)` returns `1 / 2 / 3 / 4` for the `≤10 / 11-20 / 21-40 / 41-60` bands (was `2/3/4/5`).
- [ ] Every session still opens with a warm-up block (rule preserved; no zero-warm-up sessions).
- [ ] Timing fit still lands every length within `toleranceSeconds` (verified 5/10/15/20/30/45/60).
- [ ] Pool-reservation headroom + cooldown-not-starved guards updated and passing.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** Default profile.
- **Steps:**
  1. Generate sessions at 5, 15, 30, and 60 min.
  2. Count warm-up movements in each and check total wall-clock vs request.
- **Expected Result:** Warm-up counts are 1, 2, 3, 4 respectively; each session's planned time is within ±60s of the request.
- **Failure Indicator:** Warm-up count off, a session with no warm-up, or a length outside tolerance.

### US-004: Cold-start first week leads strength (kept gentle)

**Description:** As a brand-new user, I want my first sessions to build strength (while staying easy) rather than being routed to mobility- or primal-led days.

**Acceptance Criteria:**

- [ ] `ColdStartOverride` First-Week Contrast no longer forces a mobility- or primal-led day; every cold-start day leads strength.
- [ ] Cold-start gentleness preserved: capped difficulty (`cappedMaxDifficulty`) and Start-Seed volume still applied.
- [ ] Related cold-start override tests updated to expect strength-led days.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** New-user profile inside the cold-start window with an active `coldStartContract`.
- **Steps:**
  1. Generate the first three cold-start sessions (`sessionsLogged` 0, 1, 2).
  2. Inspect each session's lead pillar and the difficulty of selected strength movements.
- **Expected Result:** All three lead strength; movements stay at or below the cold-start difficulty cap and reduced volume.
- **Failure Indicator:** Any first-week day is mobility- or primal-led, or difficulty exceeds the cap.

### US-005: Returning-user comeback leads strength (kept gentle)

**Description:** As a returning user after a gap, I want a gentle strength session so my comeback day isn't the all-mobility session that prompted this change.

**Acceptance Criteria:**

- [ ] `ReturnOverride.overridePlan(...)` leads strength: `.single(.mobility)` -> `.single(.strength)`; blend re-points via `weights.favoring(.strength)`.
- [ ] Re-entry volume ramp (`reentryScale`) retained so the comeback stays gentle.
- [ ] Return override tests updated to expect strength-led comeback.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** Profile with prior history and a gap long enough to trigger a Return (not in cold-start).
- **Steps:**
  1. Generate a comeback session at 5 min and at 20 min.
  2. Inspect the lead pillar and the prescribed volume vs a steady-state session of the same length.
- **Expected Result:** Both comeback sessions lead strength; prescribed volume is reduced relative to steady state.
- **Failure Indicator:** Comeback session is mobility-led, or volume is not reduced.

### US-006: Update domain vocabulary and record the decision

**Description:** As a future contributor, I want the code's stated philosophy and the project docs to reflect strength-primary so no one re-introduces the old co-primary behavior.

**Acceptance Criteria:**

- [ ] `Models/Enums.swift` `Pillar` doc note changed from "co-primary" to strength-primary / mobility-supporting.
- [ ] `docs/implementation-log.md` and `docs/test-coverage.md` updated; `AGENTS.md` session-mix description updated.
- [ ] A new `CONTEXT.md` is created capturing the resolved glossary (Pillar, Movement Practice, discipline-first).
- [ ] An ADR is added recording the co-primary -> strength-primary shift and its trade-off (vs discipline-first / desk-worker relief).
- [ ] No stale prose left asserting the old mobility-lean/co-primary behavior anywhere the branch touches.

**Validation Test:**

- **Setup:** Post-implementation branch.
- **Steps:**
  1. Grep the codebase and docs for "co-primary" and "mobility lean".
  2. Open `CONTEXT.md` and the new ADR.
- **Expected Result:** No surviving assertion of co-primary/mobility-lean as current behavior; `CONTEXT.md` and the ADR describe strength-primary with rationale.
- **Failure Indicator:** Stale "co-primary" language remains, or the ADR/`CONTEXT.md` is missing.

### US-007: Cross-cutting strength-primary regression guard

**Description:** As a maintainer, I want a test that pins "strength in every session" so a future tuning change can't silently reintroduce a mobility-only session.

**Acceptance Criteria:**

- [ ] A regression test asserts every generated session at 5/10/15/20/30/45/60 min contains a strength training block.
- [ ] Tests assert no session (steady-state, cold-start, or Return) is mobility-led.
- [ ] Test asserts 5-min strength share ~0.8 and blend strength share ~0.75-0.80 (with a tolerance band).
- [ ] Determinism and `asOf`-purity guards remain green.
- [ ] Full unit suite green.

**Validation Test:**

- **Setup:** CI / local test runner.
- **Steps:**
  1. Run the full unit suite.
- **Expected Result:** All tests green, including the new strength-primary invariants across all lengths and the three generation modes.
- **Failure Indicator:** Any generated session lacks a strength block, or a mode leads mobility, or determinism guards fail.

## Functional Requirements

- FR-1: The engine must select strength as the leading pillar for every session shape (single-focus and blend) in the steady state.
- FR-2: Single-focus (5-10 min) sessions must produce a strength training block; mobility appears only as the warm-up.
- FR-3: Blend (11+ min) sessions must apportion ~75-80% of training time to strength, with `minBlendShare` ≈ 0.2; warm-up and cooldown remain mobility.
- FR-4: Warm-up size must scale 1/2/3/4 across the ≤10 / 11-20 / 21-40 / 41-60 bands, and every session must open with a warm-up.
- FR-5: The `sitsLong` flag must only modulate mobility-accessory volume, never the lead pillar.
- FR-6: Cold-start first-week sessions must lead strength while retaining capped difficulty and reduced start volume.
- FR-7: Returning-user comeback sessions must lead strength while retaining the reduced re-entry volume.
- FR-8: The assembled session must remain a deterministic, `asOf`-pure function of its inputs and land within ±60s of the requested minutes at every supported length.
- FR-9: Domain docs, `CONTEXT.md`, and an ADR must record the strength-primary decision; no stale co-primary/mobility-lean prose may remain.

## Non-Goals (Out of Scope)

- No changes to the "discipline-first" product positioning, onboarding copy, or marketing.
- No changes to the `Phase` system (stays dormant; all users still resolve to `discipline`).
- No wiring of `PrimaryGoal` (including `buildStrength`) into the engine - it stays inert.
- No mobility "safety valve": mobility never reclaims a full/leading session when stale.
- No new exercises or catalog changes (existing strength/primal depth is sufficient).
- No change to the `primal` pillar's existing treatment (folded into strength short; own block at 41-60 min).

## Design / Technical Considerations

- All logic changes live in `ios/RepToday/RepToday/Services/Engine/`: `PillarBalance.swift` (US-001, US-002), `SessionAssembly.swift` (US-003), `ColdStartOverride.swift` (US-004), `ReturnOverride.swift` (US-005); `Models/Enums.swift` doc note (US-006).
- Preserve the 7-step pipeline structure and the "every session opens with a warm-up; cooldown after `cooldownThresholdMinutes`" structural rules.
- Broad test churn is expected: existing tests encode the old co-primary/mobility-lean philosophy and must be rewritten, not just extended (`PillarBalanceTests`, `SessionAssemblyTests`, `DeterministicSessionPolicyServiceTests`, cold-start/return override tests, swap tests).
- Delivery: RepToday is a `no-mistakes` project - ship via the no-mistakes pipeline to a PR, CI green (iOS + Convex jobs), then captain merge.

## Success Metrics

- 100% of generated sessions (5-60 min, all three modes) contain a leading strength block; 0 mobility-led sessions.
- 5-min strength share ≈ 0.8; 20/30-min blend strength share ≈ 0.75-0.80.
- All lengths land within ±60s of the request; determinism and `asOf`-purity guards green.
- The originally-reported 5-min session, regenerated on the same profile, is strength-led.

## Open Questions

- **Accepted consequence to confirm at ship:** with "strength every session + no safety valve," mobility is never the *lead* anywhere - a user who only ever does 5-10 min sessions gets mobility solely as warm-up stretches, and desk workers lose their dedicated same-day mobility-relief day. This follows directly from the captain's decisions and is intended, but is the sharpest trade-off.
- Does the "discipline-first" copy warrant a later, separate pass for coherence with strength-led content? (Out of scope here.)
- Exact numeric target for the blend strength share within the 0.75-0.80 band, and the precise `minBlendShare` value (0.2 vs slightly lower) - to be pinned during implementation so timing fit still converges at 45/60 min.
</content>
</invoke>
