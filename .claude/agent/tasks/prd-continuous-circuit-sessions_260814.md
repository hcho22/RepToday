# PRD: Continuous-Circuit Sessions (hands-free follow-along player)

- Status: In progress. US-CC01 (auto-advancing work window for strength sets), US-CC03/US-CC04 (the even-round engine timing model: uniform set count per training block plus the two-gap transition/round-rest fit, engine-only), US-CC02 (circuit rotation of the training block, "Round N of M", player-only), US-CC05 (hands-free warm-up/cooldown bookend holds - auto-start plus the per-side "Switch sides" beat, player-only), US-CC06 (quiet in-flow escape hatches with an explicit user Pause, player-only), US-CC07 (skip/swap apply to all remaining rounds - Option A honest late-entrant, player-only; skip was already aggregate-correct from US-CC02 and swap needed no engine change because the substitute keeps the block's uniform round count), US-CC08 (generous runtime pace - `workSecondsPerSet` becomes the runtime window as well as the planning number via `workPaceGenerosityFactor = 1.25`, engine-only; the player needed no new value because the coupling was already structural from US-CC01), and US-CC09 (hands-free completion-logging invariant - auto-advanced and Done-advanced sets log completed, only an explicit Skip logs not-done, and `CompletedSet` stays pinned to `reps`/`durationSeconds`; hardening/lock-in with no production change because the invariant was already structural from US-CC01/US-CC02/US-CC07) have landed; all other stories remain unbuilt (specification only). Decisions locked with the captain 2026-08-14; US-CC07's completed-round-count semantics settled as Option A (honest late-entrant) 2026-08-15; US-CC08's generosity factor and its two accepted consequences (fewer rounds, and the US-M03 desk-worker bias now binding) confirmed 2026-08-15.
- Story prefix: `US-CC##`.
- Supersedes, on landing: the manual tap-to-advance active-session player (US-K01/US-K02/US-O03 interaction model).
- Related decisions: [ADR-0002](../../../docs/adr/0002-per-interval-pacer-clock.md) (per-interval pacer clock), [ADR-0003](../../../docs/adr/0003-even-round-circuit-timing.md) (even-round circuit timing). Domain term: `CONTEXT.md` -> "Continuous Circuit (planned)".

## Introduction / Overview

Today Rep Today's active-session player makes the user tap constantly.
Every warm-up and cooldown stretch requires a **Start hold** tap; every strength set requires a **Complete set** tap.
For the target user - a busy, desk-bound adult who chose a 15-20 minute session precisely because they have no spare attention - this stop-start interaction is friction on the one screen that is supposed to just carry them.

This feature replaces that manual model with a **continuous-circuit follow-along session**: the workout drives itself, like putting on a trainer video and moving along with it.
Each work window counts down on a generous timer and auto-advances into an automatic rest; the strength block runs as circuit rounds ("Round 2 of 4"); warm-up and cooldown flow linearly; and the whole session is hands-free end to end.
Self-pacing is preserved not by a second "manual mode" but by quiet escape hatches inside the one flow - most importantly **+ More time**, which extends the current work window so no user is ever rushed.

Crucially, this is a **player change plus one engine timing-model change**, not a redefinition of what a session *is*.
Strength stays rep-prescribed ("4 x 10"); the deterministic engine's rep, progression, and Adaptive-Overload model is untouched.
The single engine change is that every exercise in a training block is forced to a **uniform set count** (= the number of circuit rounds), and the engine's timing fit lands the requested minutes by tuning the **between-round rest** within a bounded band instead of by adding or dropping sets on individual exercises.

## Goals

- Deliver a hands-free, follow-along session that a user can complete without tapping the screen once, from the first warm-up stretch to the last cooldown hold.
- Preserve the deterministic engine unchanged in every respect except the even-round timing model: reps stay the currency, progression and Adaptive Overload are byte-identical, `asOf`-purity and the +/-60s landing tolerance hold.
- Run the strength block as true circuit rounds with automatic, honestly-sized rest between stations and between rounds.
- Guarantee "never rush anyone" concretely: the on-screen work window is budgeted at a generous, slower-end pace, and **+ More time** always extends it.
- Keep the experience accessible: visual-primary with non-verbal audio cues that duck (not stop) the user's own audio and coordinate with VoiceOver; full Dynamic Type, Reduce Motion, and VoiceOver behavior specified for the auto-advancing timers.
- Retire the manual tap-to-advance model as a code path (no dual-mode maintenance burden), while migrating any session paused under the old model into the new player without data loss.

## User Stories

Every UI-bearing story's Validation Test targets the running iOS app in a booted Simulator, driven by hand or by the `RepTodayUITests` XCUITest scheme (which installs and launches the app out of process). Unit-level behavior (engine timing, view-model state) is validated in the `RepToday` unit suite (`RepTodayTests`, `@testable import RepToday`).

### US-CC01: Auto-advancing work window for strength sets

**Description:** As a user mid-workout, I want each strength set to count down and advance itself so that I can keep moving without reaching for the screen after every set.

**Acceptance Criteria:**

- [x] A rep-based strength set on screen shows a countdown ring sized to the set's runtime work-window seconds (US-CC08), the movement name, and the rep target (via `ActiveSessionView.targetText`, never re-formatted).
- [x] When the countdown reaches zero the session auto-flows into the between-station transition or between-round rest (US-CC04) with no tap, and the set is recorded as completed (US-CC09). (Advances into the *existing* US-K02 rest here; the two-gap transition/round-rest model is US-CC04.)
- [x] A prominent **Done** control lets the user end the current work window early and advance immediately; being caught mid-rep at zero carries no penalty and no "did you finish" prompt.
- [x] The countdown is pure over the injected clock (built on the existing `Countdown` type used by US-K02/US-O03), so tests drive it with no real time passing and backgrounding freezes it.
- [x] Typecheck, lint, and the `RepToday` unit suite pass.
- [x] Verify in the running app (Simulator, `RepTodayUITests`).

**Validation Test:**

- **Setup:** Generate a 15-minute session (strength block with at least two rep-based exercises). Launch the active-session player.
- **Steps:**
  1. Start the session and do not touch the screen.
  2. Watch a single strength work window count down to zero.
  3. On a later work window, tap **Done** before the countdown reaches zero.
- **Expected Result:** In step 2 the window reaches zero and the player advances into a rest automatically, recording that set as completed. In step 3 **Done** advances immediately. Neither path shows a penalty, a skip, or a "confirm you finished" prompt.
- **Failure Indicator:** The window stalls waiting for a tap, requires **Complete set** to advance, records the auto-advanced set as skipped, or **Done** does nothing.

### US-CC02: Circuit rotation of the strength block ("Round N of M")

**Description:** As a user, I want the strength block to rotate through one set of each exercise per round so that the session feels like circuit training rather than grinding all sets of one movement before the next.

**Acceptance Criteria:**

- [x] The strength (and, at 41-60 min, the dedicated primal) block is played as rounds: one set of each exercise in the block, in order, then repeat, rather than all sets of exercise A then all of B. (`ActiveSessionViewModel.nextPosition(fromIndex:set:)`, gated to `SessionAssembly.isCircuit`; `testStrengthBlockRotatesABCAcrossRoundsWithRoundLabels`, `testCompleteSetRotatesToTheNextStationInTheRound`, `testCompletingARoundWrapsToTheNextRound`)
- [x] The player surfaces round progress as "Round N of M" where M is the block's uniform set count (US-CC03). (`ActiveSessionViewModel.currentRound`/`circuitRoundCount` read off the block; `ActiveSessionView.setTracker`/`nextUp`; `testBookendsAreNotCircuitsOnlyTrainingBlocks`)
- [x] Warm-up and cooldown bookends are **not** circuits - they flow linearly (US-CC05); rounds apply only to training blocks. (`testBookendsAreNotCircuitsOnlyTrainingBlocks`)
- [x] Completed-set logging is unchanged in aggregate: each exercise still logs its uniform set count of completed sets by the end (US-CC09), so `WorkoutLog` and the summary are unaffected by rotation order. (`completedSets` keyed by prescription id; `testStrengthBlockRotatesABCAcrossRoundsWithRoundLabels` asserts three sets logged per exercise)
- [x] Typecheck, lint, and the `RepToday` unit suite pass.
- [x] Verify in the running app (Simulator, `RepTodayUITests`). (`ContinuousCircuitUITests.testStrengthBlockRotatesThroughRoundsHandsFree`)

**Notes (as landed):**

- The two rest gaps the engine already sizes (US-CC04) pace the rotation in the player: a short between-station transition (`SessionAssembly.transitionSeconds`) inside a round, and the bounded between-round rest (each station's `restSeconds`, uniform per block) at a round boundary. Both flow through the existing US-K02 rest overlay, so the US-CC01 auto-advance work-window flow stays hands-free across the rotated order. The transition beat's dedicated "Next: <exercise>, get ready" styling remains US-CC11; here it reuses the rest overlay.
- **Skip inside a circuit** removes the exercise from every remaining round (the rotation passes over a skipped station), which is the only aggregate-logging-correct reading of the existing "skip this exercise" contract once the walk rotates - so it lands here rather than waiting for US-CC07. **Swap** keeps the slot's set count and works mid-circuit without breaking the rotation or the label, and keeps the user's **current round** rather than restarting at round 1 (which would re-offer and double-count already-completed peer stations - US-CC02 OPT1; a genuinely fewer-set substitute is clamped down to its last round); reconciling a swap *across all remaining rounds* (and reshaping the block's round-rest to re-absorb a swap's drift) remains US-CC07.
- No snapshot-schema change: resume restores round + station from the existing `currentStepIndex`/`currentSet` (a station's r-th set *is* round r), so US-CC12 forward-safety holds.

**Validation Test:**

- **Setup:** Generate a session whose strength block has exactly 3 exercises at a uniform 3 sets. Launch the player.
- **Steps:**
  1. Start the session and follow it hands-free through the strength block.
  2. Note the order exercises appear in and the "Round N of M" label.
- **Expected Result:** Exercises appear in the order A, B, C, A, B, C, A, B, C across three rounds; the label reads "Round 1 of 3", "Round 2 of 3", "Round 3 of 3". By the end each exercise has logged 3 completed sets.
- **Failure Indicator:** Order is A, A, A, B, B, B, C, C, C; the round label is missing or wrong; or an exercise ends with the wrong set count.

### US-CC03: Even rounds - uniform set count per training block (engine change)

**Description:** As the engine, I want every exercise in a training block to carry the same number of sets so that circuit rounds are structurally even and "Round N of M" is well-defined.

**Acceptance Criteria:**

- [x] `SessionAssembly` produces training blocks in which every exercise's `sets` equals one block-level round count (the strength block and the extended primal block are each internally uniform; they need not equal each other). (`testTrainingBlocksCarryOneUniformRoundCountEachEvenRound`, `testExtendedSessionPrimalAndStrengthBlocksAreEachInternallyUniform`)
- [x] The per-exercise set-adjust lever is no longer used to hit the time target: the timing fit does not add a set to one exercise and not another within a block (the `.addSet`/`.removeSet` per-item moves are retired; the fit's only round-count lever is the block-level `setRoundsAndRest`, which writes the same count to every station; see US-CC04 for the replacement rest lever).
- [x] The reps/hold-seconds per-set target from Step 6 (Adaptive Overload) is still never touched by the timing fit (the fit moves only round count, round-rest, and whole exercises).
- [x] Determinism and `asOf`-purity are preserved: the assembled session's content remains a pure function of inputs (only ids vary run to run), verified by existing `SessionAssemblyTests`-style structural assertions (`testAssemblyIsDeterministic`, `testExtendedAssemblyIsDeterministic`, etc. still green).
- [x] The warm-up and cooldown bookends remain one set each (`allowSetAdjust: false`), unchanged.
- [x] Typecheck, lint, and the `RepToday` unit suite pass (new test asserting uniform set count per training block across 5/10/15/20/30/45/60).

**Validation Test:**

- **Setup:** In the unit suite, assemble sessions for requested minutes 5, 10, 15, 20, 30, 45, 60 for a steady-state user.
- **Steps:**
  1. For each session, read the strength block's exercises' `sets`.
  2. For the 45 and 60 minute sessions, also read the dedicated primal block's `sets`.
- **Expected Result:** Within each training block, every exercise has an identical `sets` value equal to that block's round count. No exercise in a block differs from its peers.
- **Failure Indicator:** Two exercises in the same block carry different set counts, or a per-item set-adjust move reappears in the timing fit for a training block.

### US-CC04: Two-gap rest model (transition + bounded round rest)

**Description:** As a user, I want a short reposition beat between exercises and a real recovery rest between rounds so that the circuit paces me correctly and the session still lands on my requested minutes.

**Acceptance Criteria:**

- [x] **Between stations** (inside a round, e.g. Pike -> Split Squat): a short fixed **transition** (`SessionAssembly.transitionSeconds` = 15s) that doubles as the "Next: <exercise>, get ready" beat (US-CC11). It is not zero and not recovery (`testTwoRestGapsAreDistinctTransitionShorterThanRoundRestBand`).
- [x] **Between rounds**: a **bounded recovery rest** in a defined band (`minRoundRestSeconds`...`maxRoundRestSeconds` = 30-75s) that the engine tunes within the band to land the planned wall-clock within `SessionAssembly.toleranceSeconds` (+/-60s) of the request (this is the timing-fit lever that replaces per-exercise set adjustment; see [ADR-0003](../../../docs/adr/0003-even-round-circuit-timing.md)). (`testEveryLengthLandsWithinToleranceUnderEvenRoundModel`)
- [x] The round-rest band may flex by session intensity/length within its defined bounds, but never outside them; the chosen value is a deterministic function of the inputs (uniform per block and in band at every length: `testBetweenRoundRestStaysWithinItsBandForEveryLength`).
- [x] The planned wall-clock formula is updated to `Σ(rounds × Σ exercise work-window) + between-station transitions + (rounds - 1) × round-rest` per block, plus bookends; it remains the same quantity the fit minimizes and `plannedSeconds(of:)` reports (`SessionAssembly.blockSeconds`, summed by `plannedSeconds`/`totalSeconds`).
- [x] When the round-rest band alone cannot close the gap (very short or very long requests), the fit may still add/drop a whole round (uniformly, preserving US-CC03) or add/drop a whole exercise, but never produce an uneven block (the `setRoundsAndRest` and whole-exercise promote/drop moves; `testLongSessionsRunMultipleRounds`).
- [x] Typecheck, lint, and the `RepToday` unit suite pass (new tests: round-rest stays within band; every length lands within tolerance).

**Validation Test:**

- **Setup:** In the unit suite, assemble sessions for 5, 10, 15, 20, 30, 45, 60 requested minutes.
- **Steps:**
  1. For each, compute the planned wall-clock via the updated `plannedSeconds` and compare to `requestedMinutes * 60`.
  2. Read the chosen between-round rest value for each session.
- **Expected Result:** Every session lands within +/-60s of its target. Every between-round rest sits inside the defined band (roughly 30-75s). No block is uneven.
- **Failure Indicator:** A session misses tolerance; a round-rest value falls outside the band; or the fit landed the time by making a block uneven.

### US-CC05: Hands-free warm-up and cooldown bookends

**Description:** As a user, I want the warm-up and cooldown stretches to auto-start and flow so that I never tap **Start hold** and the whole session is hands-free.

**Acceptance Criteria:**

- [x] Each bookend stretch shows a "Next: <stretch>" transition beat, then the hold **auto-starts** (no Start-hold tap) and counts down, then flows to the next stretch - reusing the US-O03 Hold Timer mechanics (`Countdown`, `holdSecondsPerSide`, per-side `holdSide`/`holdSidesPerSet`) but auto-started rather than tap-started. (`autoStartHoldIfNeeded`/`currentStepIsBookendHold`; the transition beat reuses the US-K02 rest overlay, its dedicated styling still US-CC11; `testBookendHoldAutoStartsHandsFreeOnStart`, `testBookendHoldsFlowStationToStationHandsFree`)
- [x] A per-side bookend runs side 1, a brief "Switch sides" beat, then side 2, with no tap between sides (the per-side charging via `Exercise.isPerSide`/`sidesPerSet` is unchanged). (the beat is a shared-`Countdown` rest carrying `RestContext == .switchSides`; `testPerSideBookendRunsSide1ThenSwitchSidesThenSide2HandsFree`)
- [x] Bookends flow **linearly**, not as circuit rounds - they are single-set timed holds, one per exercise (`allowSetAdjust: false` unchanged). (`currentStepIsBookendHold` is the not-a-training-block gate; a training hold keeps the manual path, `testTrainingHoldStaysManualNotAutoStarted`)
- [x] The completion cue fires exactly once per hold leg (the existing `RestTimerFeedback` seam, extended to the tone set in US-CC10), never per tick and never on a restored/expired leg (US-O03 resume rule: a leg is never persisted, so a resumed bookend re-opens idle and auto-starts fresh). (the Switch-sides beat fires **no** cue - the cue is the leg's, once each; `testPerSideBookendRunsSide1ThenSwitchSidesThenSide2HandsFree`, `testResumedBookendHoldReopensIdleAndAutoStartsFresh`)
- [x] Typecheck, lint, and the `RepToday` unit suite pass.
- [x] Verify in the running app (Simulator, `RepTodayUITests`). (`ContinuousCircuitUITests.testWarmupBookendHoldsRunHandsFreeIncludingSwitchSides`)

**Validation Test:**

- **Setup:** Generate a 20-minute session (has warm-up, strength, cooldown; includes at least one per-side bookend stretch). Launch the player.
- **Steps:**
  1. Start the session and do not touch the screen through the entire warm-up.
  2. Observe a per-side stretch specifically.
- **Expected Result:** Each warm-up stretch shows "Next: ...", auto-starts its hold, counts down, and flows on with no tap. The per-side stretch runs side 1, shows "Switch sides", then runs side 2 automatically.
- **Failure Indicator:** A stretch waits for a **Start hold** tap; the per-side stretch records only one side; or the cue fires twice / on a resume.

### US-CC06: Escape hatches inside the one flow

**Description:** As a user who needs to self-pace, I want quiet secondary controls inside the follow-along flow so that I am never forced into a separate manual mode to slow down, skip, or swap.

**Acceptance Criteria:**

- [x] The flow exposes these quiet, non-attention-demanding controls: **+ More time** (extends the current work window / hold; US-CC14 - not built here; **+ More time during a rest** is surfaced as the existing US-K02 `extendRest` "+15s" control), **Done** (jump to the transition/rest early; US-CC01), **Pause** (freeze on-screen without backgrounding), **Skip** (US-CC07), **Swap** (the existing US-K03 engine swap, `swapCurrentExercise`), and **round-rest + / skip** during a between-round rest (reusing US-K02 `extendRest`/`skipRest`).
- [x] **Pause** freezes both the visible countdown and any audio cue timing (the `Countdown` pause semantics already used for backgrounding), and resumes from the exact remainder.
- [x] There is no user-facing "manual mode" toggle; the follow-along flow is the only player (US-CC (retirement), Non-Goals) - locked in by `NoManualModeGuardTests`.
- [x] These controls are visually secondary to the movement/countdown, per Design Considerations.
- [x] Typecheck, lint, and the `RepToday` unit suite pass.
- [x] Verify in the running app (Simulator, `RepTodayUITests`).

**Validation Test:**

- **Setup:** Generate a 15-minute session and launch the player.
- **Steps:**
  1. During a strength work window, tap **Pause**; wait; then resume.
  2. During a between-round rest, tap round-rest **+** and then **skip**.
  3. During a work window, tap **Swap** and confirm a same-pattern substitute appears (or an honest "no alternative" state).
- **Expected Result:** Pause freezes the countdown and audio; resume continues from the same remainder. Round-rest **+** extends the rest and **skip** ends it and reveals the next round. **Swap** substitutes in place or shows "no alternative"; no separate mode was entered for any of these.
- **Failure Indicator:** Pause backgrounds the app or resets the timer; a control routes through a distinct manual screen; or Swap behaves differently from US-K03.

### US-CC07: Skip and Swap apply to all remaining rounds

**Description:** As a user who skips or swaps an exercise, I want that decision to hold for the rest of the circuit so that rounds stay structurally even.

**Implementation note (2026-08-15, Option A - honest late-entrant):** The player keeps **one `Step` per station**; circuit rounds are produced by re-visiting the same step index at an incremented `currentSet` (US-CC02). So both legs of this story were already structural once US-CC02/US-CC03 landed and needed **no engine change**: a **skip** passes over the station in every round (`hasSet(_:inRound:)`), and a **swap** that replaces `steps[currentStepIndex]` carries the substitute through every remaining round while `ExerciseSwap` already keeps the block's uniform prescribed round count M. The one open question this story settled: what completed-round count a mid-circuit swap's substitute ends with, since a substitute joining in round *r* can only physically play `M - r + 1` rounds. Decided **Option A (honest late-entrant)**: the substitute logs only the rounds it was actually in the session for, the pre-swap rounds stay discarded with the replaced movement (keeping the US-K03 "discard on swap, mirroring a skip" contract and the US-CC09 no-fabrication ethos), and the block stays *structurally* even (every station still prescribed M). The accepted residual: a swapped-in substitute can end one or more completed rounds short of its peers - which is the honest log, since the user did fewer sets of it. (Option B - forcing the substitute to M by crediting/fabricating its pre-swap rounds - was rejected: it would reverse the tested discard contract and log a set the user never performed.) Reshaping the block's shared round-rest to re-absorb a swap's small in-tolerance timing drift was scoped out for the same reason it is not in the AC below: the drift is already bounded by `ExerciseSwap.slotTolerance` and the AC governs rounds/uniformity, not a tighter post-swap landing. So US-CC07 shipped as a hardening/lock-in story (new unit + XCUITest coverage, doc/comment updates) with the swap comment in `ActiveSessionViewModel.swapCurrentExercise()` recording the Option A decision.

**Acceptance Criteria:**

- [x] **Skip** on an exercise removes it from all remaining rounds (not just the current round), and it logs as not-done (US-CC09). - *already aggregate-correct from US-CC02 (`skipExercise` marks the station skipped before computing the advance; `hasSet(_:inRound:)` then passes over it in this and every later round); locked by `testSkipInsideCircuitRemovesExerciseFromAllRemainingRounds` (skip B in round 1 -> rounds 2/3 rotate only A,C; B logs zero completed sets and `skipped == true`)*
- [x] **Swap** replaces the exercise with its deterministic same-pillar/pattern peer (US-K03 `ExerciseSwap`) for all remaining rounds, keeping the block's uniform round count. - *replacing the one `Step` carries the substitute through every remaining round; `ExerciseSwap` already keeps the slot's set count = M so the circuit stays uniform; `testSwapAppliesToAllRemainingRoundsAndKeepsBlockStructurallyUniform` asserts the substitute plays rounds 2 and 3 and every strength station is still prescribed M=3*
- [x] After a skip or swap the block remains internally uniform (US-CC03) - no exercise ends with a different completed round count because of a mid-circuit skip/swap. - *the block stays structurally even (all stations prescribed M) and peers each still complete M and never over-log (`allSatisfy { completedSets.count <= 3 }`, push_up/hinge = 3); the substitute is an honest late entrant (Option A) that logs only the rounds it played - see the implementation note above*
- [x] A swap that returns `.noAlternative` leaves the exercise in place for the remaining rounds and shows the honest no-alternative state (unchanged US-K03 semantics). - *`testSwapNoAlternativeMidCircuitKeepsExerciseInAllRemainingRounds` (the exercise stays and completes all its rounds; `noSwapAlternative` flips)*
- [x] Typecheck, lint, and the `RepToday` unit suite pass. - *full `RepToday` unit suite green including the three new US-CC07 tests*
- [x] Verify in the running app (Simulator, `RepTodayUITests`). - *`ContinuousCircuitUITests.testMidCircuitSkipRemovesExerciseFromLaterRoundsHandsFree` drives a mid-circuit Skip through the shipped controls and asserts the skipped movement stays absent through the later rounds*

**Validation Test:**

- **Setup:** Generate a session with a 3-exercise strength block at 3 rounds; launch the player.
- **Steps:**
  1. In round 1, **Skip** exercise B.
  2. Continue hands-free through rounds 2 and 3.
- **Expected Result:** Exercise B does not appear in rounds 2 or 3; rounds now rotate A, C. B is logged as skipped. The remaining exercises still complete 3 rounds each.
- **Failure Indicator:** B reappears in a later round; the block becomes uneven; or B logs completed sets.

### US-CC08: Generous runtime pace - screen window equals planned work-seconds

**Description:** As the engine and player, I want the on-screen work-window duration and the engine's planning work-seconds to be the same generously-calibrated number so that a typical user comfortably finishes their reps before auto-advance and the session still lands on time.

**Acceptance Criteria:**

- [x] `SessionAssembly.workSecondsPerSet` becomes an honestly-calibrated, generous, per-exercise **runtime** pace (a slower-end pace a typical user comfortably finishes within), not a planning-only estimate. - *one documented constant governs it: `SessionAssembly.workPaceGenerosityFactor = 1.25`, applied inside `workSecondsPerSet` itself so the same inflated number feeds both the planning fit and the on-screen window (captain-confirmed 2026-08-15). Grounded in the catalog's own authored cadence rather than new data: the fundamentals derive 2.0-2.5 s/rep (`hinge_glute_bridge` 2.00, `push_wall` 2.08, `squat_bodyweight`/`squat_sumo` 2.33, `push_incline`/`hinge_good_morning` 2.50; catalog median 3.5, mean 4.4 inflated by the unilateral tail), a brisk metronome tempo under the ~2.5-3.0 s/rep a controlled bodyweight rep takes. x1.25 lands them at 2.5-2.9 s/rep and lifts the assumed per-set setup 10s -> 12.5s - read as a distribution, ~the 85th percentile of completion time if the authored estimate is a median and self-paced cadence has ~20% CV. It scales the **rep branch only**: a hold's per-second cost is *definitional* rather than estimated (`secondsPerHoldSecond`, doubled per side - prescribed seconds are elapsed seconds, so there is nothing to be generous about), so holds pass through at 1.0 - the same assumed-vs-observed split `maxSetupShareOfEstimate` already draws. The split is estimated-vs-definitional and deliberately not windowed-vs-unwindowed: every rep-based movement is paced wherever it sits, warm-up/cooldown stretches included, because those reps are estimated too and the plan must budget the slower user's real time whether or not that set runs under an on-screen countdown. Step 6's capacity-relative target is untouched*
- [x] The active-session player's work-window countdown for a set uses **exactly** the same per-set seconds the engine budgeted for that set - there is one source of truth, so the screen window can never be roomier (or tighter) than what the fit planned. A roomier screen window than the plan would make every set overrun and blow past the requested minutes; this coupling forbids that by construction. - *structural since US-CC01 (`ActiveSessionViewModel.workWindowSecondsPerSet` returns `SessionAssembly.workSecondsPerSet(of: step.prescription)`; no second value exists), and now locked over a **real assembled session** rather than a fixture: `GenerousRuntimePaceTests.testEveryAutoAdvancingSetsWindowIsTheEnginesPlannedSecondsForThatSet` walks a 20-minute session end to end and asserts at every auto-advancing set that the window seconds - and, while it is up, the running window's total and remaining - equal the engine's number for that very prescription*
- [x] Per-side and hold movements price their window the same way runtime as in planning (per-side doubles via `sidesPerSet`; a hold's window is its prescribed hold seconds per side). - *automatic, because it is one function rather than a parallel path; asserted rather than assumed by `testPerSideHoldPricesBothSidesInPlanningAndRunsPerSideInThePlayer` (planning charges `sidesPerSet x` the prescribed hold plus only the movement's own authored setup; the player's `holdSecondsPerSide` is the prescribed seconds, once per leg) and by the existing per-side rep coupling test*
- [x] The accepted trade-off is documented: generous windows fit fewer rounds per session - and at 45 minutes, one fewer **station** - and a fast user may finish a touch early (they can tap **Done**). - *documented on `workPaceGenerosityFactor`, in `docs/test-coverage.md` and in the implementation log. Measured across 5/10/15/20/30/45/60 x beginner/intermediate/advanced: 15 min 6 -> 5 rounds, 20 min 6 -> 5, 30 min 7 -> 6, 60 min strength unchanged at 8 x 5 (primal 8 -> 7), 5 min unchanged at 3. **45 min pays in stations rather than rounds**: the strength block goes 7 rounds x 5 stations -> 8 x 4, so the longest strength block now trains 4 distinct movements instead of 5, narrowing its movement-pattern coverage - and with the block pinned at the `maxTrainingSets` (8) rail, dropping a station is the fit's only remaining lever there. That station loss is accepted on its own terms; raising the rail or adding a station floor is a separate follow-on, explicitly out of US-CC08. No length loses its last round, and the round outcome is flat across 1.20-1.30 so the value inside that band is a pure pacing choice. Second accepted consequence (captain-confirmed): the desk-worker `sitsLong` bias now **binds** on the shipped catalog - a rep-based stretch paces up while a hold stretch does not, so a desk worker's 45-minute warm-up costs ~32s more (was ~10s) and the fit pays it out of a whole strength round. US-M03's byte-identical-training-middle guard was always incidental rather than structural, so it is rescoped to the real invariant (same movements at the same per-set targets, blocks still internally even, a round count differing only where the bookends genuinely cost different seconds) rather than tuned around*
- [x] Determinism/`asOf`-purity preserved; the number remains a pure function of the exercise and prescribed target. - *no clock is read; `testWorkSecondsPerSetIsAPureFunctionOfTheExerciseAndTarget` asserts identical pricing across calls and across two sessions assembled a month apart, and the existing determinism rows stay green*
- [x] Typecheck, lint, and the `RepToday` unit suite pass (test: the player's window seconds for a set equal `SessionAssembly.workSecondsPerSet(of:)` for that prescription). - *full `RepToday` unit suite green, including the new `GenerousRuntimePaceTests` and the reconciled `StartSeedTests` / `SitsLongBookendBiasTests`; the opt-in generation benchmark re-run holds the `<100ms` claim*

**Validation Test:**

- **Setup:** In the unit suite, pick a rep-based prescription and a per-side prescription from an assembled session.
- **Steps:**
  1. Read the engine's `workSecondsPerSet(of:)` for each.
  2. Read the player's work-window seconds for the same steps.
- **Expected Result:** The two numbers are identical for each prescription (including the per-side doubling). The value reflects a generous slower-end pace, not a tight one.
- **Failure Indicator:** The player window and the planned seconds differ, or the per-side window is not doubled.

### US-CC09: Auto-advanced sets log as completed; only explicit Skip logs not-done

**Description:** As the logging layer, I want an auto-advanced set to record exactly like a tapped one so that completion accounting is unchanged and only an explicit skip counts as not-done.

**Acceptance Criteria:**

- [x] An auto-advanced set records the prescribed reps/hold as performed, identical to today's tapped completion (prescribed = performed; there is no per-rep input, unchanged from US-K01/US-L01).
- [x] Only an explicit **Skip** (US-CC07) records an exercise as not-done; **Done** (early advance) records completed.
- [x] No per-set "did they really do it" tracking is added; the end-of-session perceived-difficulty rating (US-L02, `rate`) remains the sole adaptation signal into the Asymmetric Ramp.
- [x] The `>=80%` session-completion telemetry (US-T10 `session_completed`) reads a bit more generously than the old tap-gated model; this is documented as an accepted consequence in the PRD and `docs/test-coverage.md`.
- [x] The session-lifecycle telemetry contract is otherwise unchanged: `session_started`/`session_completed`/`session_abandoned` fire from the same choke points (`start()`, `recordSessionEnd()`, and `ReadyViewModel`'s give-up path), and `AbandonPoint` (warmup/mainWork/cooldown) still derives from the current step's block.
- [x] Typecheck, lint, and the `RepToday` unit suite pass.

**Implementation note (2026-08-16, hardening/lock-in - no production change):** Tracing the logging path confirmed the invariant was **already structural** once US-CC01/US-CC02/US-CC07 landed, so this story shipped as a lock-in story with no engine or player change. An auto-advanced set (`completeWorkWindowIfElapsed`) and a **Done** early-advance (`finishWorkWindowEarly`) both route through `completeSet()` -> `recordSet(for:)`, which appends a `CompletedSet(reps: prescription.reps, durationSeconds: prescription.durationSeconds)` - prescribed = performed, byte-identical to the pre-US-CC01 tapped path. A **Skip** (`skipExercise`) removes the station's `completedSets` and inserts it into `skippedStepIDs`, so `loggedExercises()` renders it `completedSets: []`, `skipped: true` across every round (US-CC02/US-CC07). `CompletedSet` carries only `reps`/`durationSeconds` - no per-set difficulty or verification field - and the sole adaptation signal remains the end-of-session `rate` (US-L02). Deliverables: the whole-session validation test `ActiveSessionViewModelTests.testWholeSessionHandsFreeWithOneSkipLogsCompletedExceptTheSkip` (drives warm-up hold + a 3x3 circuit + cooldown hold fully hands-free with one station skipped, reads the durable `WorkoutLog`), the compile-coupled `NoPerSetCompletionTrackingGuardTests` (reflection pins `CompletedSet` to exactly its two fields), and this note plus the `docs/test-coverage.md` row.

**Accepted telemetry consequence (captain-noted):** because a work window auto-records its set at countdown zero even if the user did not actually perform the reps, the US-T10 `>=80%` `session_completed` metric reads **a bit more generously** than the retired tap-gated model, where completion required an affirmative per-set tap. This is accepted, not a defect: the follow-along design deliberately trades per-set proof for a hands-free flow, the perceived-difficulty rating (US-L02) remains the real adaptation signal, and the number should be interpreted as "reached the end of the session" rather than "verifiably performed every rep." No emission site moved and no new event was added.

**Validation Test:**

- **Setup:** In the unit suite, drive a session hands-free to completion with one exercise explicitly skipped.
- **Steps:**
  1. Let all other sets auto-advance.
  2. Read the resulting `WorkoutLog`'s per-exercise rows.
- **Expected Result:** Every auto-advanced exercise logs its full uniform set count as completed; the skipped exercise logs zero completed sets and `skipped == true`. The rating remains the only difficulty signal.
- **Failure Indicator:** An auto-advanced set logs as skipped, a skip logs completed sets, or a per-set difficulty field appears.

### US-CC10: Non-verbal audio cues, ducking, and VoiceOver coordination

**Description:** As a user watching the screen like a video, I want distinct non-verbal tones for each state so that I can tell states apart by ear without any spoken callouts fighting my music or VoiceOver.

**Acceptance Criteria:**

- [x] No spoken/TTS callouts and no recorded trainer voice anywhere in the flow.
- [x] Distinct tones mark distinct states: **go** (work window starts), **halfway** (optional midpoint), **transition** (between stations), **round-rest** (between rounds), and **done** (set/hold complete), so states are tellable apart by ear (extends the existing `RestTimerFeedback` seam, now `SessionCuePlayer`).
- [x] Audio **ducks** (lowers, does not stop) the user's own music/podcast for the duration of a cue, then restores it (`AVAudioSession` `.playback` + `.duckOthers`, deactivated with `.notifyOthersOnDeactivation`; **on-device manual QA** - Simulator audio routing is a proxy).
- [x] Audio **coordinates with VoiceOver**: when VoiceOver is running, app tones do not talk over VoiceOver speech (the tone is suppressed while the haptic still fires; the decision reads `isVoiceOverRunning` at fire time and is unit-tested through the injected spy; live collision timing is **on-device manual QA**).
- [x] A haptic alternative accompanies each tone (project convention: haptics with an audio alternative), so a muted user - or a VoiceOver user whose tone is withheld - still gets state changes.
- [x] Typecheck, lint, and the `RepToday` unit suite pass; verify audio behavior on device where the audio session is real (Simulator audio routing is a proxy).

**Validation Test:**

- **Setup:** On a device (or Simulator for structure), start background music, launch a session.
- **Steps:**
  1. Follow a few work windows and one round-rest hands-free, listening.
  2. Enable VoiceOver and repeat one work window.
- **Expected Result:** Each state change plays a distinct tone; music ducks under each tone and returns to full volume after. No spoken workout callouts occur. With VoiceOver on, tones do not overlap VoiceOver speech.
- **Failure Indicator:** Music stops (instead of ducking) or never returns; a spoken callout plays; tones collide with VoiceOver; or states are indistinguishable by ear.

**Implementation note (landed):** Player-only. The single US-K02 feedback seam (`RestTimerFeedback.restDidComplete()`) is evolved into `Utilities/SessionCuePlayer.swift`: a `SessionCue` enum (`.go`/`.halfway`/`.transition`/`.roundRest`/`.done`) and `SessionCuePlayer.play(_:suppressAudio:)`, with the real `SystemSessionCuePlayer` and an injected spy in tests (same protocol shape). The five states route onto the player's existing transition points, not new advance logic: `.go` from `startWorkWindow()`; a new optional `.halfway` from `fireWorkWindowHalfwayIfReached(asOf:)` driven off the work-window ticker; `.transition`/`.roundRest` at a rest's *start* (a `cue:` argument on `startRest`, sourced from a cue kind `nextPosition` now returns); `.done` at set/hold-leg completion. A rest *ending* fires no cue (the next window's `.go` is the boundary tone), so go never doubles with a rest-completion tone; the US-CC05 switch-sides beat stays silent and each hold leg still lands exactly one `.done`. **Tone source:** distinct `AudioServicesPlaySystemSound` ids - no bundled audio asset, so no `docs/asset-attribution.md` row is owed. **Ducking:** `AVAudioSession` `.playback` + `.duckOthers`, activated around the tone and deactivated with `.notifyOthersOnDeactivation`, an in-flight counter ducking once across overlapping cues. **VoiceOver:** the view model reads `UIAccessibility.isVoiceOverRunning` at fire time (injected `voiceOverActive: () -> Bool`) and passes `suppressAudio`; the tone (and its duck) is withheld under VoiceOver while the haptic still fires. **On-device audio/VoiceOver behavior is captain-verifiable manual QA the unit suite cannot fully cover** (Simulator audio routing and VoiceOver are a proxy); units prove the decision logic - which tone for which state, switch-sides silent, audio withheld under a VoiceOver flag - through the spy. Deliverables and tests are in `docs/implementation-log.md` and `docs/test-coverage.md`. Full `RepToday` unit suite green (1019 tests, opt-in benchmark skipped).

### US-CC11: Visual-primary work window (static illustration at launch)

**Description:** As a user, I want each work window to clearly show the movement so that I can follow along visually, since there is no voice.

**Acceptance Criteria:**

- [ ] Each work window shows a clear **static illustration** of the movement plus its name, the rep/hold target (via `targetText`), and the countdown ring.
- [ ] During the between-station transition beat, an "Next: <exercise>" cue is **visually prominent** (this is the visual substitute for a spoken "next up").
- [ ] Looping per-exercise animations are an explicit **fast-follow**, out of scope here: the existing US-O01 Lottie seam (`ExerciseDemoView` / `LottieDemoView` / `Exercise.animationName`) is preserved so that dropping in ~71 per-movement clips later is a data change, not a rewrite. Where a clip already exists it may play; where it does not, the static illustration shows.
- [ ] Text-and-ring-only (no illustration) is explicitly rejected as too bare - a static illustration must be present at launch.
- [ ] Reduce Motion is honored: with Reduce Motion on, any animation is stilled to the static illustration (matches the existing `reduceMotion` handling in `LottieDemoView`).
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in the running app (Simulator, `RepTodayUITests`).

**Validation Test:**

- **Setup:** Launch a session; ensure the illustration asset ledger (`docs/asset-attribution.md`) has cleared rows for any shipped illustration.
- **Steps:**
  1. Observe a work window: illustration, name, rep target, ring.
  2. Observe the transition beat before the next exercise.
  3. Toggle Reduce Motion on and re-observe.
- **Expected Result:** Every work window shows an illustration + name + target + ring; the transition beat prominently shows "Next: <exercise>". With Reduce Motion on, the view is a still illustration, not an animation.
- **Failure Indicator:** A work window shows only text and a ring; the "Next" cue is absent or buried; or Reduce Motion still animates.

### US-CC12: Migration - resume an old paused session in the new player

**Description:** As a user who paused a session before this update, I want it to resume from where I left off in the new player so that the update never costs me my in-progress workout.

**Acceptance Criteria:**

- [ ] A persisted `ActiveSessionState` written by the old manual player (US-K04) loads and resumes in the new continuous-circuit player from its saved position (current step index, current set, completed sets, skips, session-clock origin).
- [ ] Because the old snapshot may carry uneven per-exercise set counts (pre-US-CC03), the resumed player maps the saved position into round/station terms deterministically without losing completed work or double-counting a set; any per-side `hold.side` restores idle per the US-O03 rule.
- [ ] No migration writes a new snapshot schema that the prior build could not read back in the same session (forward safety); the `exercisedMinutes`/`hold` optional-and-defaulted fields decode unchanged.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass (test: an old-shape `ActiveSessionState` resumes with completed work preserved).

**Validation Test:**

- **Setup:** In the unit suite, construct an `ActiveSessionState` in the pre-CC shape (a mid-block position with some completed sets, one skipped exercise, a `hold.side == 2`).
- **Steps:**
  1. Construct the new player from that state.
  2. Read its position, completed sets, skips, and hold side.
- **Expected Result:** The player resumes at the saved position with all completed sets and skips intact; the hold restores idle on side 2; no set is lost or double-counted.
- **Failure Indicator:** Resume drops completed work, double-counts a set, crashes on an old snapshot, or restores a running hold leg.

### US-CC13: First-run explainer for the self-driving session

**Description:** As a first-time user of the new player, I want a brief explainer so that I am not surprised the workout now drives itself and the manual model is gone.

**Acceptance Criteria:**

- [ ] The first time a user reaches the continuous-circuit player (once), a short, dismissible explainer states: the session auto-advances, **+ More time** never rushes you, **Done** jumps ahead, and tones mark state changes.
- [ ] The explainer is shown at most once (a persisted one-shot flag), does not block the session from starting, and is fully accessible (VoiceOver-readable, Dynamic Type).
- [ ] Copy is identity-framed and non-loss-framed, consistent with the product voice.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in the running app (Simulator, `RepTodayUITests`).

**Validation Test:**

- **Setup:** Fresh install (clear the explainer flag). Launch a session.
- **Steps:**
  1. Observe the explainer on first arrival; dismiss it.
  2. Start and finish a session; start another.
- **Expected Result:** The explainer appears once on first arrival, is dismissible, and does not reappear on the second session. It reads correctly under VoiceOver.
- **Failure Indicator:** The explainer reappears every session, blocks the start, or is not VoiceOver-accessible.

### US-CC14: Accessibility acceptance for the auto-advancing flow (+ More time first-class)

**Description:** As a user who needs more time - for any reason - I want **+ More time** to be a first-class, always-available control and the auto-advancing timers to be fully accessible so that "never rush anyone" is a real guarantee, not a slogan.

**Acceptance Criteria:**

- [ ] **+ More time** is present on every auto-advancing work window and hold, always extends the current window by a meaningful increment, and is reachable by VoiceOver (a labeled, hittable control at the project's touch-target size for active screens, 60pt).
- [ ] The auto-advancing countdown does not steal VoiceOver focus or fire rapid per-second VoiceOver announcements; remaining time is available on demand (e.g. an accessibility value the user can query) rather than continuously spoken.
- [ ] Dynamic Type: the movement name, rep target, round label, and control labels scale with Dynamic Type without truncation or overlap at the largest accessibility sizes.
- [ ] Reduce Motion: the countdown ring and any transition animation degrade to a non-animated indicator when Reduce Motion is on (the ring may show remaining time as a static value/step rather than a sweeping animation).
- [ ] With VoiceOver on, an auto-advance that would fire mid-announcement is coordinated so the user is not cut off (ties into US-CC10).
- [ ] Typecheck, lint, and the `RepToday` unit suite pass; accessibility behavior verified in the running app (`RepTodayUITests`, and manual VoiceOver on device).

**Validation Test:**

- **Setup:** Enable VoiceOver, set Dynamic Type to the largest accessibility size, launch a session.
- **Steps:**
  1. Navigate to the work window with VoiceOver; find and activate **+ More time**.
  2. Query the remaining-time element with VoiceOver.
  3. Read the movement name, target, and round label at the largest text size.
  4. Enable Reduce Motion and observe the ring.
- **Expected Result:** **+ More time** is found, labeled, and extends the window. Remaining time is queryable, not spammed. All labels are readable without truncation. The ring is non-animated under Reduce Motion.
- **Failure Indicator:** **+ More time** is missing or unreachable by VoiceOver; the timer spams announcements or steals focus; labels truncate/overlap; or the ring keeps animating under Reduce Motion.

## Functional Requirements

- FR-1: The active-session player MUST auto-advance a work window at countdown zero into the next state with no user tap, recording the set as completed (US-CC01, US-CC09).
- FR-2: The player MUST offer a **Done** control that advances the current window early, recording completed (US-CC01).
- FR-3: Training blocks MUST be played as circuit rounds (one set of each exercise per round), surfaced as "Round N of M" (US-CC02).
- FR-4: `SessionAssembly` MUST assign every exercise in a training block the same set count (the block's round count); the timing fit MUST NOT create uneven per-exercise set counts within a block (US-CC03).
- FR-5: The engine MUST land the planned wall-clock within `toleranceSeconds` (+/-60s) using a bounded between-round rest as the primary fit lever, falling back to whole-round or whole-exercise add/drop that preserves uniformity (US-CC04).
- FR-6: The engine MUST model two rest gaps: a short fixed between-station transition (~10-15s) and a bounded between-round rest (~30-75s band) (US-CC04).
- FR-7: Warm-up and cooldown holds MUST auto-start (no Start-hold tap) and flow linearly, running per-side stretches side 1 -> "Switch sides" -> side 2 without a tap (US-CC05).
- FR-8: `workSecondsPerSet` MUST be a generous per-exercise runtime pace, and the player's work-window seconds MUST equal the engine's planned per-set seconds for that prescription (single source of truth) (US-CC08).
- FR-9: Only an explicit **Skip** MUST log an exercise as not-done; auto-advanced and **Done**-advanced sets MUST log completed; no per-set completion tracking is added (US-CC09).
- FR-10: **Skip** and **Swap** MUST apply to all remaining rounds so blocks stay uniform (US-CC07).
- FR-11: The player MUST expose quiet in-flow escape hatches - **+ More time**, **Done**, **Pause**, **Skip**, **Swap**, round-rest **+/skip** - with no separate manual mode (US-CC06).
- FR-12: Audio cues MUST be non-verbal, distinct per state, MUST duck (not stop) the user's audio, and MUST coordinate with VoiceOver; each MUST have a haptic alternative (US-CC10).
- FR-13: Each work window MUST show a static illustration + name + target + countdown ring; the transition beat MUST prominently show "Next: <exercise>"; looping animations remain a fast-follow behind the US-O01 Lottie seam (US-CC11).
- FR-14: A session persisted by the old manual player MUST resume in the new player from its saved position without losing or double-counting completed work (US-CC12).
- FR-15: A one-time, dismissible, accessible first-run explainer MUST introduce the self-driving flow (US-CC13).
- FR-16: **+ More time** MUST be first-class and always available; auto-advancing timers MUST be fully accessible (VoiceOver, Dynamic Type, Reduce Motion) per US-CC14.
- FR-17: The whole feature MUST preserve engine determinism and `asOf`-purity; reps stay the currency; progression and Adaptive Overload are unchanged except for the uniform-set-count timing model.

## Non-Goals (Out of Scope)

- No conversion of strength to timed intervals: reps stay the prescription; the countdown paces the window, it does not redefine the target.
- No changes to progression-chain selection, Adaptive Overload's per-set targets, pattern focus, pillar structure, cold-start/Return overrides, or the exercise catalog.
- No user-selectable "manual mode" or per-session pacing setting; the follow-along flow is the only player.
- No per-rep input, per-set "did you finish" tracking, or new adaptation signals beyond the existing end-of-session perceived-difficulty rating.
- No spoken/TTS or recorded-voice coaching.
- No production of the ~71 per-movement looping animations in this feature (fast-follow); this PRD ships static illustrations plus the preserved Lottie seam.
- No changes to the analytics event schema or the set of 13 events; the completion metric's slightly more generous reading is an accepted consequence, not a schema change.
- No Apple Watch / Live Activity / background-audio-workout mode; the session remains an on-screen, foreground experience (backgrounding still pauses timers as today).

## Design Considerations

- **Visual hierarchy:** the movement illustration and the countdown ring are primary; the rep target and "Round N of M" are secondary but always visible; escape hatches (**+ More time**, **Done**, **Pause**, **Skip**, **Swap**) are tertiary, quiet, and never demand attention. Use `Theme.Colors`/`Theme.Typography`/`Theme.Spacing`; active-screen touch targets are 60pt.
- **Transition beat:** the between-station gap is a designed moment ("Next: <exercise>", get-ready), not dead time - it is where the visual-primary experience announces what is coming, compensating for the absence of voice.
- **One prescription-copy source:** the window's target text and its spoken form come from `ActiveSessionView.targetText` / `targetAccessibilityText`, never re-formatted.
- **Reuse existing seams:** `Countdown` (pause/resume, clock-injected) backs every timer; `RestTimerFeedback` is extended for the tone set; `ExerciseDemoView`/`LottieDemoView`/`Exercise.animationName` remain the illustration/animation seam; `ExerciseSwap` (US-K03) is the swap; `ActiveSessionStore`/`ActiveSessionState` remain resume persistence.
- **First-run explainer** copy is identity-framed, consistent with the product voice; it is a one-shot, non-blocking sheet.

## Technical Considerations

- **Player restructuring (`ActiveSessionViewModel`):** the flattened linear `steps` model must gain a round/station structure for training blocks while keeping bookends linear. The auto-advance replaces the manual `completeSet()` tap path; `Done` maps onto an early-advance; the rest overlay is driven automatically. Persistence (`snapshot()`/`persist()`) and telemetry choke points (`start()`, `recordSessionEnd()`) must keep their invariants (one terminal event per physical session; completed sets logged as today).
- **Engine timing model (`SessionAssembly`):** uniform set count per training block plus a bounded round-rest fit lever is the single biggest change. The planned-seconds formula, the `additions`/`removals` candidate generation, and `PlannedItem.seconds` must be reworked so that (a) training-block sets move uniformly (whole-round), (b) round-rest is a first-class tunable within a band, and (c) bookends stay one-set/non-adjustable. `toleranceSeconds` (+/-60s) and `asOf`-purity are hard constraints. See [ADR-0003](../../../docs/adr/0003-even-round-circuit-timing.md).
- **Runtime pace calibration (`workSecondsPerSet`): LANDED (US-CC08).** It is now a real runtime number rather than a planning proxy, and the player reads the same value because it calls the same function. The existing constants (`setupSecondsPerSet`, `secondsPerHoldSecond`, cadence derivation) were kept - they encode the model's *shape* - and a single `workPaceGenerosityFactor = 1.25` scales the estimated (rep) half to the slower end; holds are unscaled because their per-second cost is definitional. The direct consequence, accepted: the same number drives the fit, so a session lands fewer rounds - and at 45 minutes one fewer *station* (8 rounds x 4, versus 7 x 5), i.e. 4 distinct strength movements instead of 5. See [ADR-0002](../../../docs/adr/0002-per-interval-pacer-clock.md) for the pacer-clock reversal of US-O03's hidden-clock stance.
- **Benchmark:** the `<100ms` generation claim (`SessionGenerationBenchmarkTests`, opt-in) must still hold after the timing-model change; re-run the opt-in benchmark.
- **Audio session:** ducking requires the correct `AVAudioSession` category/options; VoiceOver coordination requires reading `UIAccessibility.isVoiceOverRunning` and the announcement queue. These verify meaningfully only on device.
- **Retiring the manual model:** the old tap-to-advance controls (**Start hold**, **Complete set**) and any tests asserting them are removed/rewritten; `docs/test-coverage.md` and the implementation log are updated. The removal is captured in this PRD and the `CONTEXT.md` term; whether it also warrants its own ADR is left as an Open Question (it may clear the hard-to-reverse/surprising/trade-off bar).

## Success Metrics

- A user can complete a full session start-to-finish without a single tap (verified by an XCUITest that launches, starts, and reaches completion with zero interaction beyond starting).
- Sessions continue to land within +/-60s of the requested minutes across 5/10/15/20/30/45/60 after the timing-model change (unit suite).
- Median tap count per session drops to ~0-1 (from one tap per set/stretch today) - measurable via the touch path in `RepTodayUITests`, not a shipped metric.
- Session-completion rate (`session_completed` / `session_started`, US-T10) holds or rises; note the more generous reading from auto-advance logging (US-CC09) so the number is interpreted correctly.
- No regression in generation latency (`<100ms`, opt-in benchmark).
- Accessibility: **+ More time** reachable and functional under VoiceOver; no truncation at the largest Dynamic Type sizes; ring degrades under Reduce Motion (manual + XCUITest verification).

## Open Questions

- **Per-side movements in the circuit (DEFERRED - standing default, not final):** the leaning default is one work window with a mid "Switch sides" beat, handled exactly like the per-side bookends. Flagged open; revisit whether a per-side strength movement should instead be two windows.
- **Session-clock visibility (DEFERRED - standing default, not final):** the leaning default is to keep the **total** elapsed time hidden (preserving US-O03's intent that the total not become a thing-to-endure) while showing the **local** per-interval countdown ring and "Round N of M". This is the exact distinction ADR-0002 rests on - a per-interval pacer is not a grind-against-total clock - so the rationale is explicit. Flagged open; revisit whether a subtle overall progress affordance is worth adding.
- **Calibrating the generous per-exercise pace (US-CC08): RESOLVED 2026-08-15 (captain).** Observed per-movement pace data does not exist and sourcing it (a moderated cohort or a timed dry-run of all 71 movements) was not made a precondition. The calibration instead scales the data the catalog already carries: a single deterministic `workPaceGenerosityFactor = 1.25` on the *estimated* (rep) half of `workSecondsPerSet`, justified from the authored cadence itself (see the US-CC08 criteria above) and applied inside that one function so planning and the on-screen window can never diverge. Holds are unscaled because their per-second cost is definitional, not estimated. This is honestly a **scaled typical-case estimate, not observed runtime data** - a later story with real completion times can replace the factor with per-movement runtime fields without touching any call site, since every caller already reads this one function.
- **First-run explainer scope (US-CC13):** exact copy, and whether it is a single sheet or a 2-3 step coach-mark sequence, is open.
- **Round-rest band flex rule (US-CC04):** the precise mapping from session intensity/length to a round-rest value within the band is open (a monotonic function of remaining fit gap vs. an intensity-indexed default); it must stay deterministic and within bounds.
- **Standalone ADR for retiring the manual player:** whether the wholesale replacement of the manual tap-to-advance model deserves its own ADR (beyond ADR-0002/ADR-0003 and the CONTEXT term) is open; it plausibly clears the bar (hard to reverse, surprising to a reader who finds no manual mode, a real trade-off against self-pacing).
