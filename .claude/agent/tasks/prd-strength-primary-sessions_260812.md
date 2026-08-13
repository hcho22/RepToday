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

---

# Follow-on: Movement Practice removal + pattern-matched bookends

**Opened:** 2026-08-13 · **Status:** Captain-approved follow-on, spec-only. This section supersedes the parts of the original PRD (and of `docs/adr/0001-strength-primary-sessions.md`) that keep mobility as a minority *accessory training block* - the "Movement Practice" block. It leaves everything else in the archived PRD above byte-for-byte intact; the seven original stories stayed shipped, this only retires their accessory-mobility clause. No engine or code change is authorized by this document - it is a specification for a later, separately-authorized implementation task.
**Story prefix:** `US-M##` - **M** for the Movement-Practice-removal follow-on; the prefix restarts (rather than continuing `US-008`) to mark this as a distinct, later-dated design pass on top of the completed `US-0##` set.
**Source:** captain design session, 2026-08-13.

## Introduction / Overview

The original strength-primary work (US-001 .. US-007) made strength the lead of every session but kept mobility alive as a small **Movement Practice** accessory training block on 11-60 min sessions, sized by staleness and the desk-worker `sitsLong` signal. That block is the last place a session still carries a mobility *middle*: it is where a "blend" still means a strength-vs-mobility split rather than a pure strength session with mobility bookends. The reported movement-heaviness the first pass set out to fix is therefore only partly addressed - the label changed more than the realized mix did on the longer sessions.

This follow-on removes the Movement Practice block outright and folds its role into the Warm-Up and Cooldown bookends, reallocating the freed training minutes to **strength** (not to more stretching). It also makes the bookends *earn their stretches*: each bookend leads with a stretch that complements the day's lead strength pattern, then fills the rest with the existing variety ordering. After this change, every session at every length is uniformly described as **Warm-Up -> Strength -> Cooldown** (with Primal remaining an extra block on 41-60 min sessions), and no session ever emits a mobility middle block.

## The seven captain-approved decisions

1. **Scope of "the movement portion."** The deletion targets the **Movement Practice** mobility accessory *training* block only. **Primal is explicitly out of scope** of this deletion - it stays folded into strength on short sessions and keeps its own block on 41-60 min sessions, exactly as today.

2. **Combine, not delete.** Movement Practice as a *named block* is removed, but its role is not thrown away: it folds into the **Warm-Up** and **Cooldown** bookends. Mobility survives - as bookends only, never as a middle block.

3. **Reallocate the freed minutes to strength.** The training minutes freed by removing the Movement Practice block go to the **Strength** block, **not** to more stretching. This is what fixes the actual movement-heaviness rather than just the label. Pure relocation - moving the same stretch minutes into the bookends and leaving the strength share unchanged - is **explicitly rejected**.

4. **Remove the split machinery.** The mobility/strength split engine path (`PillarBalance` / `PillarWeights`, and the mobility-accessory sizing in `SessionAssembly`) is **removed**, not neutralized or left dormant. After this change, "blend" no longer denotes a strength-vs-mobility split: the 11-40 min sessions become, structurally, a strength session wrapped in bookends.

5. **Pattern-matched bookends (prefer-then-fill).** Warm-Up and Cooldown each **lead** with a stretch that complements the day's **lead strength pattern**, then fill any remaining slots with the existing staleness / no-repeat variety ordering. This requires new per-stretch `complements: [MovementPattern]` metadata in `Exercises.json` - none exists today, since all 26 mobility movements share the single flat `mobility` pattern. The pattern match is a **preference/bias, never an exclusive filter**: it can never starve a bookend, and the general mobility pool remains the fallback when no complementary stretch is available or fresh.

6. **`sitsLong` repurposed to bias, not size.** The desk-worker `sitsLong` signal currently only *sizes* the (now-deleted) Movement Practice accessory. It is repurposed to **bias** bookend selection toward posture / hip openers (and/or to add one extra bookend stretch), never to size any block. It must **not** reintroduce a mobility middle block by any path.

7. **Uniform vocabulary, length-scaled bookends.** Every session, at every duration, is described with the same three-part shape **Warm-Up -> Strength -> Cooldown** (Primal remains an extra block on 41-60 min sessions - see decision 1). The cooldown is **not** mandatory on the shortest sessions: bookends stay lean and length-scaled so a 5-min session is not re-inflated with stretching. Strength keeps the lion's share of the clock at every length.

## Resulting session shape

| Length | Today | After this change |
|---|---|---|
| 5-10 min | Warm-Up + Strength | Warm-Up + Strength (unchanged) |
| 11-20 min | Warm-Up + Strength + Movement Practice + Cooldown | Warm-Up + Strength + Cooldown |
| 21-40 min | Warm-Up + Strength + Movement Practice + Cooldown | Warm-Up + Strength + Cooldown |
| 41-60 min | Warm-Up + Strength + Movement Practice + Primal + Cooldown | Warm-Up + Strength + Primal + Cooldown |

## The `complements` mapping (captain-approved, verbatim)

Each mobility movement is tagged with the strength pattern(s) it complements. A stretch may complement multiple patterns. Coverage: every strength pattern maps to **>= 6 stretches**, so prefer-then-fill never starves.

- **squat** -> Deep Squat Hold, 90/90 Hip Stretch, Pigeon Pose, Frog Stretch, Butterfly Stretch, Cossack Squat, Standing Quad Stretch, Figure-Four Glute Stretch, Wall Calf Stretch, Ankle Rocks, Hip Circles, Kneeling Hip-Flexor Stretch, Lizard Lunge, World's Greatest Stretch
- **hinge** -> Standing Forward Fold, Downward Dog, Kneeling Hip-Flexor Stretch, Pigeon Pose, Figure-Four Glute Stretch, 90/90 Hip Stretch, Deep Squat Hold, Cat-Cow Flow, World's Greatest Stretch, Wall Calf Stretch, Hip Circles
- **push** -> Wall Chest Opener, Arm Circles, Thoracic Rotations, Cobra Stretch, Puppy Pose, Downward Dog, Thread the Needle, World's Greatest Stretch
- **pull** -> Thoracic Rotations, Child's Pose, Supine Spinal Twist, Thread the Needle, Puppy Pose, Arm Circles
- **core** -> Cat-Cow Flow, Supine Spinal Twist, Standing Side Bend, Thread the Needle, Cobra Stretch, Thoracic Rotations

(The stretch ids in `Exercises.json` are `mobility_*`; the display names above map to them 1:1. The implementation task will encode this as a `complements` field keyed by `MovementPattern`.)

## User Stories

### US-M01: Remove the Movement Practice block; reallocate its minutes to strength

**Description:** As a user on an 11-60 min session, I want the freed mobility-accessory minutes to become strength work so my longer sessions are genuinely strength-heavy, not just labeled that way.

**Acceptance Criteria:**

- [ ] The Movement Practice mobility accessory *training* block is no longer emitted at any length.
- [ ] The split machinery (`PillarBalance` / `PillarWeights`, and the mobility-accessory sizing in `SessionAssembly`) is **removed**, not neutralized.
- [ ] The training minutes previously held by the Movement Practice block are reallocated to the **Strength** block (not to bookend stretching).
- [ ] Primal is untouched: still folded into strength short, still its own block at 41-60 min.
- [ ] Timing fit still lands every length within ±60s of the request (verified 5/10/15/20/30/45/60).
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** No-history profile; generate at 20, 30, and 45 min.
- **Steps:**
  1. Generate each session and list its blocks.
  2. Confirm no mobility *training* block appears between warm-up and cooldown.
  3. Sum training-block seconds by pillar and compute the strength share.
- **Expected Result:** No mobility middle block at any length; strength share is higher than under the archived PRD's ~0.75-0.80 accessory model; each session lands within ±60s.
- **Failure Indicator:** Any mobility middle block survives, or the freed minutes went to stretching rather than strength.

### US-M02: Pattern-matched, prefer-then-fill bookends

**Description:** As a user, I want my warm-up and cooldown stretches to complement the day's strength work so the bookends feel purposeful rather than random.

**Acceptance Criteria:**

- [ ] `Exercises.json` gains a per-stretch `complements: [MovementPattern]` field encoding the mapping above verbatim; all 26 mobility movements are tagged.
- [ ] Warm-Up and Cooldown each **lead** with a stretch complementing the day's lead strength pattern, then fill remaining slots with the existing staleness / no-repeat variety ordering.
- [ ] The match is a preference/bias, never an exclusive filter: the general mobility pool is the fallback and a bookend is never starved.
- [ ] Coverage holds: every strength pattern resolves to >= 6 complementary stretches.
- [ ] Determinism and `asOf`-purity preserved.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** No-history profile; generate sessions whose lead pattern is squat, then push, then core.
- **Steps:**
  1. For each, inspect the first warm-up stretch and first cooldown stretch.
  2. Cross-check against the `complements` mapping.
- **Expected Result:** The leading bookend stretch complements the day's lead pattern whenever a fresh complementary stretch exists; otherwise a general-pool fallback appears, never an empty bookend.
- **Failure Indicator:** A bookend is empty, or the match behaves as a hard filter that starves the bookend.

### US-M03: `sitsLong` biases bookends, never sizes a block

**Description:** As a desk worker, I want my sedentary signal to steer my bookends toward posture and hip relief without bringing back a mobility middle block.

**Acceptance Criteria:**

- [ ] `sitsLong` no longer sizes any training block (the accessory sizing it drove is gone with US-M01).
- [ ] `sitsLong` biases bookend selection toward posture / hip openers and/or adds at most one extra bookend stretch.
- [ ] No code path lets `sitsLong` reintroduce a mobility middle block.
- [ ] Bookends stay lean and length-scaled; the shortest sessions are not re-inflated with stretching.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** Two otherwise-identical no-history profiles, `sitsLong = true` and `false`; generate at 5 and 20 min.
- **Steps:**
  1. Compare bookend contents between the two profiles.
  2. Confirm block structure is identical (Warm-Up -> Strength -> Cooldown; +Primal at 41-60).
- **Expected Result:** The `sitsLong` profile's bookends lean toward posture/hip openers (or carry one extra bookend stretch); neither profile gains a mobility middle block; the 5-min session is not re-inflated.
- **Failure Indicator:** `sitsLong` changes block *count/structure* beyond a single extra bookend stretch, or a mobility middle block reappears.

### US-M04: Uniform three-part vocabulary, length-scaled bookends

**Description:** As a future contributor and as a user reading the UI, I want every session - at every length - described as Warm-Up -> Strength -> Cooldown so the vocabulary is uniform and no one re-derives a mobility split.

**Acceptance Criteria:**

- [ ] Every generated session is describable as Warm-Up -> Strength -> Cooldown (Primal an extra block at 41-60 min).
- [ ] Cooldown is not forced onto the shortest sessions; bookends remain lean and length-scaled.
- [ ] Strength keeps the majority of the clock at every length.
- [ ] No surviving prose (in the touched surfaces) describes a "blend" as a strength-vs-mobility split or names Movement Practice as a live block.
- [ ] Unit tests pass.

**Validation Test:**

- **Setup:** Generate at 5, 10, 15, 20, 30, 45, 60 min.
- **Steps:**
  1. Map each session onto the three-part (four-part at 41-60) shape.
  2. Confirm strength holds the majority of training time at each length.
- **Expected Result:** All lengths conform to the uniform shape; no mobility middle block; strength leads the clock everywhere.
- **Failure Indicator:** Any length breaks the uniform shape, or strength is not the majority.

### US-M05: Regression guard - no mobility middle block, ever

**Description:** As a maintainer, I want a test that pins "no session emits a mobility middle block" so a later tuning change cannot silently bring Movement Practice back.

**Acceptance Criteria:**

- [ ] `StrengthPrimaryRegressionTests` is extended to assert **no** session (steady-state, cold-start, or Return) at 5/10/15/20/30/45/60 min emits a mobility *training* block between warm-up and cooldown.
- [ ] The existing "strength in every session" invariants from US-007 stay green.
- [ ] Bookend pattern-match preference and `sitsLong`-as-bias behavior are covered by tests.
- [ ] Determinism and `asOf`-purity guards remain green.
- [ ] Full unit suite green.

**Validation Test:**

- **Setup:** CI / local test runner.
- **Steps:**
  1. Run the full unit suite.
- **Expected Result:** All green, including the new "no mobility middle block" invariant across all lengths and all three generation modes.
- **Failure Indicator:** Any generated session emits a mobility middle block, or a determinism guard fails.

## Functional Requirements

- FR-M1: The engine must not emit a Movement Practice (mobility accessory training) block at any length or in any generation mode.
- FR-M2: The mobility/strength split machinery (`PillarBalance` / `PillarWeights`, mobility-accessory sizing in `SessionAssembly`) must be removed, not merely neutralized.
- FR-M3: Training minutes freed by removing the Movement Practice block must be reallocated to the strength block, not to bookend stretching.
- FR-M4: Warm-Up and Cooldown must lead with a stretch complementing the day's lead strength pattern (prefer-then-fill), using a new `complements: [MovementPattern]` field on each mobility movement in `Exercises.json`; the match is a preference, never an exclusive filter, and the general pool is the fallback.
- FR-M5: Every strength pattern must resolve to >= 6 complementary stretches so prefer-then-fill never starves.
- FR-M6: `sitsLong` must only bias bookend selection (toward posture/hip openers and/or one extra bookend stretch), never size a block, and never reintroduce a mobility middle block.
- FR-M7: Every session at every length must be describable as Warm-Up -> Strength -> Cooldown (Primal an extra block at 41-60 min); bookends stay lean and length-scaled, cooldown not forced on the shortest sessions, and strength keeps the majority of the clock.
- FR-M8: Primal treatment is unchanged (folded into strength short; own block at 41-60 min).
- FR-M9: The assembled session must remain a deterministic, `asOf`-pure function of its inputs and land within ±60s of the requested minutes at every supported length.

## Non-Goals (Out of Scope)

- No change to Primal - its scope, folding, and 41-60 min block are untouched.
- No new mobility movements; only the additive `complements` metadata on the existing 26.
- No mobility "safety valve" or middle block by any path (the archived PRD's non-goal is reaffirmed and hardened).
- No change to the "discipline-first" positioning, onboarding copy, or the dormant Phase / `PrimaryGoal` systems.
- No implementation, ADR, `CONTEXT.md`, or `AGENTS.md` edits in *this* task - those are the future documentation trail below, done under a separate authorized task.

## Planned documentation trail (future work - not done in this task)

The eventual *implementation* task (separate, not yet authorized) will:

- Write **ADR-0002** superseding the Movement-Practice parts of ADR-0001. ADR-0001's "strength leads every session" invariant **stays**; its "mobility survives as a minority accessory block (Movement Practice)" clause is **retired**. This PRD follow-on supersedes that specific clause of ADR-0001 while leaving the rest intact.
- Update **CONTEXT.md**: retire the "Movement Practice" glossary term; rewrite the "Pillar" entry so mobility is bookend-only.
- Update **AGENTS.md** sections 2 ("Pillar balance") and 7, plus the `Pillar` / `Enums.swift` doc comments.
- Extend `StrengthPrimaryRegressionTests` to assert no session ever emits a mobility middle block (US-M05 above).

## Open Questions

- Exact bookend slot counts per length band once the Movement Practice minutes are reabsorbed into strength - to be pinned during implementation so timing fit still converges at 45/60 min.
- Whether `sitsLong` adds an extra bookend stretch, biases ordering only, or both - to be settled against the length-scaled bookend budget so the shortest sessions stay lean.
- The exact tie-break when several complementary stretches are equally fresh (fall back to the existing staleness / no-repeat variety ordering) - confirm no new nondeterminism is introduced.
