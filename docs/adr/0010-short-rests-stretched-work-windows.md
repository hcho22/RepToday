# ADR-0010: Short rests, with stretched strength sets as the timing-fit lever

- Status: Accepted and implemented (2026-11-02, `Services/Engine/SessionAssembly.swift` and the active-session player).
- Date: 2026-11-02
- Deciders: captain, via the hands-free sessions design questions settled 2026-11-02
- Supersedes: [ADR-0003](0003-even-round-circuit-timing.md)'s bounded between-round rest (30-75s) as the timing fit's primary lever.
  ADR-0003's even rounds and the ±60s tolerance are unchanged.
- Relates to: [ADR-0002](0002-per-interval-pacer-clock.md) (the pacer clock that counts these intervals down), [ADR-0004](0004-round-cap-wide-circuit.md) (the 2-4 round cap and wide circuits the coarse fit still uses), [ADR-0011](0011-round-numbers-and-the-climb.md) (the round rep and hold numbers the windows are priced at); the domain terms `CONTEXT.md` -> "Continuous Circuit" and "Stretched work window".

## Context

The captain asked for a session that, once started, runs for the length the user chose with no tap at all, and found the rests between sets too long.
Two things stood in the way.
The continuous-circuit player still asked for taps: a timed strength or primal hold waited for **Start hold** (US-O03), a rep-based warm-up or cooldown move waited for **Complete set**, and the one-time explainer paused the running session until **Got it**.
And the between-round rest ran 30-75 seconds because it was the timing fit's fine lever (ADR-0003): each second of round rest moved `(rounds - 1)` seconds of session, which is how a session landed within a minute of the request.

Capping every rest at 15 seconds removes that lever, and the minutes it held have to go somewhere or a session ends early.

## Decision

**Every rest is at most 15 seconds, and the session is filled by stretching the work windows of rep-based strength sets.**

- `SessionAssembly.maxRestSeconds` is 15.
  The between-round rest is fixed at it (`roundRestSeconds`), the between-station and between-block transitions stay 15 seconds, a bookend's between-set rest is 15 seconds, and the per-side "Switch sides" beat stays 5 seconds.
  The player clamps every rest it opens to the cap, so a session saved before this change resumes with short rests.
  **+15s** on a rest stays as an optional extra.
- The timing fit picks the coarse shape first: whole rounds (uniformly, within the 2-4 rails) and whole stations, never an uneven block.
  Its cost already knows the remaining gap will be filled by stretching (`SessionAssembly.fitCost`): a shape a little short of the request is cheap, a stretched second costs half a second of landing error, an overshoot costs in full, and a shape that would land outside ±60s costs more than any shape inside it.
  So the fit prefers shapes that keep the stretch small.
- The gap left is then spread across the session's rep-based training sets (`stretchWorkWindows`): every set gets the same whole-second stretch, the remainder goes one more second per set to stations in session order while a whole station's rounds fit, so a station's stretch is the same in every round and the result is deterministic.
  A window only grows from the generous pace (`workSecondsPerSet`, US-CC08), never shrinks below it, and never past `maxStretchSecondsPerSet` (90s).
  Timed holds and the warm-up and cooldown keep their prescribed lengths.
- The stretch is stored on the prescription (`PrescribedExercise.stretchSeconds`, optional), the player's countdown shows the stretched window, and a swap hands the slot's stretch to a rep-based substitute.
- The user finishes the reps and rests until the window ends.
  The set still records what it asked for (prescribed = performed, US-CC09), and the spare time at the end of a set is part of the set, not a rest, so the 15-second cap does not bind it.
- No tap is needed after the start.
  Every timed hold auto-starts after its get-ready beat the way a bookend hold already did (US-CC05), on a natural reveal and on a resumed session, and a per-side hold flows side 1, "Switch sides", side 2.
  A rep-based warm-up or cooldown move runs on the same auto-advancing window as a training set, at its generous pace.
  The first-run explainer shows before the session starts and its button starts it, so it never pauses a running session.
  The one-time Trainer choice (US-TP10) does the same on every arrival whose Trainer is still unresolved, including after a force-quit before choosing or a choice whose write failed: it shows before the start, and choosing starts the session, or hands on to the explainer when that is due.
  Pause, Done, Skip, Swap, Stop hold and **+ More time** stay optional; **Start hold** survives only as the way back after a deliberate Stop hold.

## Considered Options

- **Keep a tunable round rest below 15 seconds** - rejected: a 0-15s band moves at most 15 seconds per round boundary, which cannot absorb the minutes the long rests held, and a near-zero rest is no recovery at all.
- **Add more rounds or stations only** - rejected as too coarse: a station or a round is one to four minutes of work, so a session would park a minute or more off the request.
- **Longer strength sets (chosen)** - the captain's option B: the clock on each strength move stretches to fill, at the cost that the time no longer matches the reps asked for.

## Consequences / Trade-offs

- The planned wall-clock formula is ADR-0003's with each rep-based training set's `workPerSet` including its stretch, and a fixed 15-second round rest.
  Verified for 5/10/15/20/30/45/60 minutes at every fitness level, for a steady history and a fresh one (`SessionAssemblyTests.testEvidenceEvenRoundCircuitTranscriptAcrossLevelsAndLengths`): every session lands within 16 seconds of the request, every rest is at most 15 seconds, and the largest per-set stretch is 21 seconds.
- An injury flag that removes whole patterns (a lower-back flag drops pull and hinge) leaves a long session with too few stations to go wider at the round cap, which used to land several minutes short; the stretch now fills it, at the cost of long windows (about a minute of extra time per rep set for a lower-back user's 60-minute session, the most observed in `DifferentWorkoutTests`).
  The 90-second rail exists for that case.
- With 15-second rests a session holds more work, so sessions fill wider and deeper within the existing 2-4 round cap: more stations, and more rounds at the shorter lengths.
- A stretched window is longer than the reps need, by design; how that feels on a phone is the captain's to judge by hand.
  There is no separate on-screen cue for the spare seconds at the end of a stretched set; that would be a follow-up.
- Determinism and `asOf` purity hold: the fit and the stretch are pure functions of the inputs, and only ids vary run to run.
- Reverting restores the round-rest lever; sessions saved under this rule still play (the stretch is optional on the prescription, and older code ignores it).
