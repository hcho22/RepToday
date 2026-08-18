# PRD: Round Cap and Wide Circuits

- Status: In progress. **US-RC01** (cap rounds to `2...4` and fill longer sessions by going wider, the coupled engine core) **has landed** - see `AGENTS.md`'s Fourth PRD note and the `docs/test-coverage.md` row for what shipped, including the two latent timing-fit bugs the cap exposed and fixed. **US-RC02** (the standing "2-4 rounds, always" regression guard, `RoundCapInvariantGuardTests`) **has also landed** (test-and-docs-only, no production change). US-RC03 (accessory progression/Adaptive Overload parity), US-RC04 (pin the accepted depth mismatch), and US-RC05 (ADR-0004 + the `CONTEXT.md` "Wide Circuit" term) remain open.
- Story prefix: `US-RC##`.

## Introduction

Today the deterministic session engine fills a longer workout by adding **rounds** to a circuit: every exercise in a strength block shares the block's round count, so a 60-minute session presents each movement at 7-8 sets (e.g. `Pike Push-Up 7 x 8`).
That is too much volume per movement, and it reads alarmingly on the plan preview.

This feature caps the round count so **no exercise is ever prescribed more than four times** in a session, and fills longer sessions by going **wider** - adding more distinct movements - instead of deeper.
The extra movements come from a pattern's *second progression chain* (push has a horizontal chain and a vertical chain; squat has squat and lunge; etc.), so every prescribed movement stays an honest frontier of its own chain and progression tracking is unchanged.

This is an **engine-only** change.
The continuous-circuit player (US-CC02) already reads the number of stations and the round count off the block and renders "Round N of M," so a session with more stations and fewer rounds needs no player or UI work.

The decision behind this feature was resolved in a design grill and is recorded as ADR-0004 ("Round cap and wide circuits"); this PRD implements it.

## Goals

- Bound every training-block exercise to **2-4 rounds** (never more than 4, never fewer than 2), across every session length and fitness level.
- Fill 45-60 minute sessions by adding movements (a pattern's second-chain frontier as an **accessory**) rather than by adding rounds.
- Fill **depth-first**: take each pattern to the 4-round cap before adding any accessory, so short and medium sessions stay clean one-movement-per-pattern circuits and only long sessions go wide.
- Keep every prescribed movement an honest frontier of its own chain, so progression, variety windows, and Adaptive Overload are unchanged.
- Preserve the engine's hard constraints: land within +/-60s of the requested length, strength holds the training majority, mobility stays bookend-only, determinism and `asOf`-purity hold.
- Ship with no player, model, persistence, or UI change.

## User Stories

### US-RC01: Cap rounds and fill longer sessions by going wider (engine core)

**Description:** As a user, I want no exercise prescribed more than four times and a full-length session filled with more movements instead of more sets, so my workout has sane per-movement volume without getting shorter.

This is the coupled core change; it is landed as one unit because capping rounds without a wider accessory pool would leave a ~30-minute hole in a 60-minute session and miss the landing tolerance.

**Acceptance Criteria:**

- [x] The training-block round rails change to `minTrainingSets = 2`, `maxTrainingSets = 4` in `SessionAssembly` (was `1...8`).
- [x] `SessionAssembly` generates, for each strength movement pattern, the frontier tier of the pattern's **top-N progression chains** (not just the top-1), adding the extra ones to the block reserve as **accessories**; the per-pattern chain ranking reuses `ProgressionChainSelection` / the existing staleness ordering, and each accessory is the frontier of its own chain.
- [x] The timing fit is **depth-first**: it takes every active station to the `maxTrainingSets` cap (4) before promoting an accessory from the reserve; an accessory is only promoted when four rounds of the current stations still fall short of the request.
- [x] Every exercise in a training block still carries the **same** round count (the block stays even, per ADR-0003); an accessory joins at the block's current round count.
- [x] Sessions land within +/-60s (`toleranceSeconds`) for requested lengths 5/10/15/20/30/45/60 across beginner, intermediate, and advanced users (the existing `SessionAssemblyTests` / `UniformSessionShapeTests` tolerance checks pass unchanged).
- [x] No accessory is ever seeded at a tier the user has not cleared; a fresh (untouched) second chain is entered at its gentlest eligible tier exactly like any chain entry.
- [x] Strength still holds the majority of training time; mobility appears only as warm-up/cooldown bookends; the extended (41-60 min) session still carries a dedicated primal block that strength leads.
- [x] Determinism and `asOf`-purity are preserved (same inputs produce the same session; no wall-clock read inside the engine).
- [x] Full `xcodebuild` unit suite (`-scheme RepToday test`) passes.

**Validation Test:**

- **Setup:** Run the unit suite. Use the existing engine test harness that assembles a session for a given `requestedMinutes` and fitness level with a fixed catalog and empty history.
- **Steps:**
  1. Assemble sessions for 5, 10, 15, 20, 30, 45, and 60 minutes for each of beginner/intermediate/advanced.
  2. For each assembled session, inspect every training block's exercises: read each exercise's `sets` (round count) and the count of distinct stations.
  3. Compute the planned wall-clock and compare to the request.
  4. Assemble a 60-minute advanced session and count distinct strength movements.
- **Expected Result:** Every training-block exercise has `sets` in `2...4` at every length and level. Each block is internally even (all stations share one round count). Every session lands within +/-60s. The 60-minute session contains **more distinct strength movements** than four (it went wider), while a 15-20 minute session stays at roughly one movement per pattern (it did not).
- **Failure Indicator:** Any exercise shows `sets > 4` or `sets < 2`; a block is uneven; a session misses +/-60s; a long session is still four movements at high round counts; or a short session sprouts accessories.

### US-RC02: Guard the "2-4 rounds, always" invariant

**Description:** As a maintainer, I want a standing test that fails the build if any future change lets a training-block exercise exceed four rounds or drop below two, so the cap can never silently regress.

**Acceptance Criteria:**

- [x] A test in `RepTodayTests` assembles sessions across 5/10/15/20/30/45/60 minutes and all three fitness levels and asserts every training-block exercise has `sets` in `2...4`.
- [x] The test asserts each training block is internally even (one round count per block).
- [x] The test is in the routinely-run unit bundle (runs under `-scheme RepToday test` locally and in CI).
- [x] A row is added to `docs/test-coverage.md`.
- [x] Full `xcodebuild` unit suite passes.

**Validation Test:**

- **Setup:** The invariant guard test is present.
- **Steps:**
  1. Run the unit suite; confirm the guard passes.
  2. Temporarily set `maxTrainingSets` back to 8, rebuild, and run the guard.
- **Expected Result:** The guard passes at the shipped `2...4` rails and **fails** when the ceiling is reverted to 8 - proving it actually binds.
- **Failure Indicator:** The guard passes even with `maxTrainingSets = 8` (vacuous), or is absent from the routinely-run bundle.

### US-RC03: Accessory progression and Adaptive Overload integrity

**Description:** As a user, I want an accessory movement to progress and be dosed exactly like a primary movement, so going wider adds real training surface rather than filler.

**Acceptance Criteria:**

- [ ] An accessory (a second-chain frontier) advances its own chain when that chain's `advancementCriteria` are met in the logs, identical to a primary station (no separate "accessory" progression path exists).
- [ ] Adaptive Overload targets an accessory capacity-relative to that movement (reps/holds), so an easier second-chain movement earns proportionally more reps.
- [ ] The `varietyWindow` no-repeat preference applies per chain, so an accessory is subject to the same recent-use avoidance as any station.
- [ ] Tests cover: an accessory clearing its criteria advances that chain next session; an easier accessory receives a higher rep target than a harder primary; and an accessory used recently is de-preferred.
- [ ] A row is added to `docs/test-coverage.md`.
- [ ] Full `xcodebuild` unit suite passes.

**Validation Test:**

- **Setup:** A test user whose logs put horizontal push at its frontier and whose vertical push chain is entered as an accessory.
- **Steps:**
  1. Assemble a long session and confirm both a horizontal-push station and a vertical-push accessory appear.
  2. Log a performance that clears the vertical accessory's tier criteria.
  3. Assemble again next session.
- **Expected Result:** The vertical accessory advances to its next tier next session, exactly as a primary station would; its prescribed reps are capacity-relative to its difficulty.
- **Failure Indicator:** The accessory never advances, advances by a different rule, or is dosed with a fixed rep count ignoring its difficulty.

### US-RC04: Accept and pin the bounded depth mismatch

**Description:** As a maintainer, I want the accepted depth-mismatch behavior pinned by a test, so the deliberate decision not to gate it is documented and protected.

**Acceptance Criteria:**

- [ ] A test asserts that for beginner (difficulty cap 1-2) and intermediate (1-3) users, a pattern's accessory frontier is within the same reachable band as its primary (zero-to-negligible mismatch).
- [ ] A test asserts an advanced user maxed on a deep chain receives a second-chain accessory no more than one tier below the primary in steady state, and that an **untouched** second chain is entered at its base tier (not seeded higher).
- [ ] No code path seeds an accessory above the tier the user has cleared (the earned-progression invariant holds for accessories).
- [ ] A row is added to `docs/test-coverage.md`.
- [ ] Full `xcodebuild` unit suite passes.

**Validation Test:**

- **Setup:** Three test users (beginner, intermediate, advanced-maxed-on-horizontal-push).
- **Steps:**
  1. Assemble a long session for each and read the difficulty of each pattern's primary vs. accessory station.
  2. For the advanced user with no vertical-push history, read the accessory's tier.
- **Expected Result:** Beginner/intermediate accessories match the primary's band; the advanced accessory is at most one tier easier in steady state; the untouched vertical chain enters at its base tier, never higher.
- **Failure Indicator:** An accessory is seeded at an unearned tier, or the mismatch exceeds one tier for capped users.

### US-RC05: Record the decision (ADR-0004 + CONTEXT "Wide Circuit")

**Description:** As a future contributor, I want the round-cap/go-wider decision recorded so the reshaped fill model is not surprising.

**Acceptance Criteria:**

- [ ] `docs/adr/0004-round-cap-wide-circuit.md` is added (Status: Accepted and implemented, dated), and it notes that it supersedes ADR-0003's 45-minute "8 rounds x 4 stations" consequence.
- [ ] A "Wide Circuit" term is added to `CONTEXT.md`, pointing to ADR-0004 and the owning code (`SessionAssembly`, `ProgressionChainSelection`).
- [ ] ADR-0003's consequence note is annotated (or cross-referenced) to point forward to ADR-0004 for the retired round rail.
- [ ] `docs/implementation-log.md` records the change.
- [ ] Links between the ADRs and CONTEXT resolve.

**Validation Test:**

- **Setup:** The docs are added.
- **Steps:**
  1. Open `CONTEXT.md`, follow the "Wide Circuit" link to ADR-0004.
  2. Open ADR-0004, follow its back-link to ADR-0003.
- **Expected Result:** Both links resolve; ADR-0004 states the `2...4` rails, the second-chain accessory rule, depth-first fill, and the accepted depth mismatch; ADR-0003's superseded consequence is cross-referenced.
- **Failure Indicator:** A broken link, or ADR-0004 disagreeing with the shipped constants.

## Functional Requirements

- FR-1: The training-block round count must be bounded to `2...4` (`SessionAssembly.minTrainingSets = 2`, `maxTrainingSets = 4`).
- FR-2: For each strength movement pattern, the engine must be able to draw the frontier tier of more than one progression chain in that pattern (the top chain plus accessories from further chains), each an honest frontier of its own chain.
- FR-3: The timing fit must fill depth-first - all active stations reach the 4-round cap before any accessory is promoted from the reserve.
- FR-4: An accessory must join a training block at the block's current round count, keeping the block internally even (ADR-0003).
- FR-5: The engine must never prescribe a movement at a tier the user has not cleared; an untouched second chain enters at its gentlest eligible tier.
- FR-6: Accessory movements must use the same progression advancement, variety-window, and Adaptive Overload rules as primary stations (no separate accessory path).
- FR-7: Every assembled session must land within +/-60s of the request for 5/10/15/20/30/45/60 minutes across beginner/intermediate/advanced.
- FR-8: Strength must retain the training-time majority; mobility remains bookend-only; the 41-60 min session retains a strength-led dedicated primal block.
- FR-9: The engine must remain deterministic and `asOf`-pure (no behavior change to those guarantees).
- FR-10: No player, view-model, model, persistence, or on-screen change is required or made; the existing continuous-circuit player renders the reshaped block unchanged.

## Non-Goals (Out of Scope)

- **No player/UI change.** The continuous-circuit player already renders variable stations and "Round N of M"; this feature touches only the engine.
- **No Ready-screen preview relabel.** The preview still formats a station as `N x M` (now at most `4 x M`, far less alarming than `7 x 8`); relabeling the preview to speak in rounds/circuit terms is a separate follow-on.
- **No difficulty-floor gating of accessories.** The bounded depth mismatch is accepted as designed, not gated.
- **No back-off accessories** (a lower tier of the same chain). Accessories are always a *different* chain's frontier.
- **No revival of the mobility/Movement Practice middle block** (US-M01 stands).
- **No new exercises or catalog additions.** The feature uses the existing chains in `Exercises.json`.
- **No change to the Adaptive Overload targeting math, progression criteria, or variety-window semantics** beyond applying them to accessory stations.

## Technical Considerations

- Core files: `Services/Engine/SessionAssembly.swift` (round rails, reserve generation, depth-first fit, `blockSeconds`), `Services/Engine/ProgressionChainSelection.swift` and `orderedStrengthPatterns` (per-pattern multi-chain frontier selection).
- The block already starts with one active lead station and the remaining patterns in reserve, promoted by the fit's `addReserve` lever; this feature enlarges the reserve with second-chain accessories and reorders the fit to prefer rounds up to the cap before promoting.
- The catalog supports this directly: every strength pattern has 2-3 chains (push: horizontal/vertical; squat: squat/lunge; hinge: bridge/hip; core: plank/stability/hollow; pull: postural/horizontal), and primal has two chains.
- Difficulty caps (beginner 1-2, intermediate 1-3, advanced 1-5 with Strength-phase tips hidden in the MVP) keep the second-chain depth mismatch to at most one tier for advanced users and zero for the rest.
- ADR-0003's even-round uniformity and the +/-60s tolerance remain the hard constraints the new shape is verified against; this feature caps the round rail ADR-0003 introduced.
- Delivery follows the project's no-mistakes pipeline (the same `xcodebuild test` gate); this is engine + docs, no `convex/` toolchain involvement.

## Success Metrics

- Zero training-block exercises with more than four or fewer than two rounds, across all lengths and levels (enforced by the US-RC02 guard).
- All existing engine tests (tolerance, uniform-shape, strength-majority, determinism) remain green.
- A 60-minute session presents 6-8 distinct strength movements at <=4 rounds each, versus today's ~4 movements at 7-8 rounds.
- Short/medium sessions (5-30 min) are unchanged except for shedding rounds beyond four.

## Open Questions

- Should the Ready-screen preview eventually be relabeled to speak in circuit/round terms (e.g. "4 rounds, 6 movements") rather than `N x M`? Tracked as a separate follow-on, not this PRD.
- For the dedicated primal block at 41-60 min, should it also go wide (its two chains) or stay a single movement given its 15% minority share? Default assumption: the round cap applies to it, but strength carries all widening; revisit only if the primal block lands short.
- Is there a maximum sensible station count for a 60-minute strength block (e.g. cap at 8 movements) to avoid an unusually broad circuit, or is the pattern/chain supply a natural ceiling? Default: the chain supply is the natural ceiling; add an explicit cap only if sessions feel scattered.
