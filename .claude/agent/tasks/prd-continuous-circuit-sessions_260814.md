# PRD: Continuous-Circuit Sessions (hands-free follow-along player)

- Status: In progress. US-CC01 (auto-advancing work window for strength sets), US-CC03/US-CC04 (the even-round engine timing model: uniform set count per training block plus the two-gap transition/round-rest fit, engine-only), US-CC02 (circuit rotation of the training block, "Round N of M", player-only), and US-CC05 (hands-free warm-up/cooldown bookend holds - auto-start plus the per-side "Switch sides" beat, player-only) have landed; all other stories remain unbuilt (specification only). Decisions locked with the captain 2026-08-14.
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

**Acceptance Criteria:**

- [ ] **Skip** on an exercise removes it from all remaining rounds (not just the current round), and it logs as not-done (US-CC09).
- [ ] **Swap** replaces the exercise with its deterministic same-pillar/pattern peer (US-K03 `ExerciseSwap`) for all remaining rounds, keeping the block's uniform round count.
- [ ] After a skip or swap the block remains internally uniform (US-CC03) - no exercise ends with a different completed round count because of a mid-circuit skip/swap.
- [ ] A swap that returns `.noAlternative` leaves the exercise in place for the remaining rounds and shows the honest no-alternative state (unchanged US-K03 semantics).
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in the running app (Simulator, `RepTodayUITests`).

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

- [ ] `SessionAssembly.workSecondsPerSet` becomes an honestly-calibrated, generous, per-exercise **runtime** pace (a slower-end pace a typical user comfortably finishes within), not a planning-only estimate.
- [ ] The active-session player's work-window countdown for a set uses **exactly** the same per-set seconds the engine budgeted for that set - there is one source of truth, so the screen window can never be roomier (or tighter) than what the fit planned. A roomier screen window than the plan would make every set overrun and blow past the requested minutes; this coupling forbids that by construction.
- [ ] Per-side and hold movements price their window the same way runtime as in planning (per-side doubles via `sidesPerSet`; a hold's window is its prescribed hold seconds per side).
- [ ] The accepted trade-off is documented: generous windows fit slightly fewer rounds per session, and a fast user may finish a touch early (they can tap **Done**).
- [ ] Determinism/`asOf`-purity preserved; the number remains a pure function of the exercise and prescribed target.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass (test: the player's window seconds for a set equal `SessionAssembly.workSecondsPerSet(of:)` for that prescription).

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

- [ ] An auto-advanced set records the prescribed reps/hold as performed, identical to today's tapped completion (prescribed = performed; there is no per-rep input, unchanged from US-K01/US-L01).
- [ ] Only an explicit **Skip** (US-CC07) records an exercise as not-done; **Done** (early advance) records completed.
- [ ] No per-set "did they really do it" tracking is added; the end-of-session perceived-difficulty rating (US-L02, `rate`) remains the sole adaptation signal into the Asymmetric Ramp.
- [ ] The `>=80%` session-completion telemetry (US-T10 `session_completed`) reads a bit more generously than the old tap-gated model; this is documented as an accepted consequence in the PRD and `docs/test-coverage.md`.
- [ ] The session-lifecycle telemetry contract is otherwise unchanged: `session_started`/`session_completed`/`session_abandoned` fire from the same choke points (`start()`, `recordSessionEnd()`, and `ReadyViewModel`'s give-up path), and `AbandonPoint` (warmup/mainWork/cooldown) still derives from the current step's block.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.

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

- [ ] No spoken/TTS callouts and no recorded trainer voice anywhere in the flow.
- [ ] Distinct tones mark distinct states: **go** (work window starts), **halfway** (optional midpoint), **transition** (between stations), **round-rest** (between rounds), and **done** (set/hold complete), so states are tellable apart by ear (extends the existing `RestTimerFeedback` seam).
- [ ] Audio **ducks** (lowers, does not stop) the user's own music/podcast for the duration of a cue, then restores it (correct `AVAudioSession` category/options - e.g. `.duckOthers` - rather than interrupting/stopping).
- [ ] Audio **coordinates with VoiceOver**: when VoiceOver is running, app tones do not talk over VoiceOver speech (respect the announcement/`isVoiceOverRunning` state, defer or suppress a cue that would collide).
- [ ] A haptic alternative accompanies each tone (project convention: haptics with an audio alternative), so a muted user still gets state changes.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass; verify audio behavior on device where the audio session is real (Simulator audio routing is a proxy).

**Validation Test:**

- **Setup:** On a device (or Simulator for structure), start background music, launch a session.
- **Steps:**
  1. Follow a few work windows and one round-rest hands-free, listening.
  2. Enable VoiceOver and repeat one work window.
- **Expected Result:** Each state change plays a distinct tone; music ducks under each tone and returns to full volume after. No spoken workout callouts occur. With VoiceOver on, tones do not overlap VoiceOver speech.
- **Failure Indicator:** Music stops (instead of ducking) or never returns; a spoken callout plays; tones collide with VoiceOver; or states are indistinguishable by ear.

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
- **Runtime pace calibration (`workSecondsPerSet`):** this becomes a real runtime number, not a planning proxy, and the player reads the same value. The current constants (`setupSecondsPerSet`, `secondsPerHoldSecond`, cadence derivation) were tuned for planning-only bias, not for a slower-end runtime window a typical user comfortably finishes - see Open Questions on sourcing real per-movement data. See [ADR-0002](../../../docs/adr/0002-per-interval-pacer-clock.md) for the pacer-clock reversal of US-O03's hidden-clock stance.
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
- **Calibrating the generous per-exercise pace (US-CC08):** the current `workSecondsPerSet` is a planning proxy where per-second precision was explicitly not the goal. A real runtime window needs real per-movement pace data (observed completion times at a comfortable slower-end cadence) rather than the authored catalog estimate. How is this sourced and validated - a small moderated cohort, a timed dry-run of the catalog, or per-movement authored runtime fields? Flagged as a precondition for shipping US-CC08's calibration.
- **First-run explainer scope (US-CC13):** exact copy, and whether it is a single sheet or a 2-3 step coach-mark sequence, is open.
- **Round-rest band flex rule (US-CC04):** the precise mapping from session intensity/length to a round-rest value within the band is open (a monotonic function of remaining fit gap vs. an intensity-indexed default); it must stay deterministic and within bounds.
- **Standalone ADR for retiring the manual player:** whether the wholesale replacement of the manual tap-to-advance model deserves its own ADR (beyond ADR-0002/ADR-0003 and the CONTEXT term) is open; it plausibly clears the bar (hard to reverse, surprising to a reader who finds no manual mode, a real trade-off against self-pacing).
