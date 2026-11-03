# ADR-0011: Round rep and hold numbers, the three-session climb, and "couldn't finish"

- Status: Accepted and implemented (2026-11-02, `Services/Engine/AdaptiveOverload.swift`, `Services/Engine/ProgressionChainSelection.swift`, the completion screen, and `Resources/Exercises.json`).
- Date: 2026-11-02
- Deciders: captain, via the hands-free sessions design questions settled 2026-11-02
- Amends: the Asymmetric Ramp (US-E05) and Adaptive Overload's percentage steps (US-C06); the 3-rep floor; US-CC09's "the end-of-session rating is the sole ramp signal", which now has one post-session per-move companion.
- Relates to: [ADR-0006](0006-foundations-push-pull-legs-core.md) (Foundations, never revoked), [ADR-0010](0010-short-rests-stretched-work-windows.md) (the windows these numbers are priced at); the domain term `CONTEXT.md` -> "Round numbers".

## Context

Adaptive Overload moved each target by a percentage: about +5% after a "just right" session, +10% after "too easy", -20% after "too hard" or a skip, never below 3 reps.
That produced numbers like 13 and 14, which the captain asked to replace with 10, 15, 20.
Round numbers move in steps of five, so a step is a big change for a small number, and a set records what it asked for (US-CC09): a user who could not do the reps would still log them, and a move's advancement target would read as met.

## Decision

**Every rep target is a multiple of five from 10 to 50, every hold a five-second step from 10 seconds to the hold ceiling, and targets move one step at a time.**

- **The grid.** `AdaptiveOverload.step` is 5, `minReps` and `minHoldSeconds` are 10, `maxReps` stays 50 and `maxHoldSeconds` stays 180, with a per-side hold's ceiling `180 / sides` rounded down onto the grid (90 a side).
  A per-side move follows the rule per side.
  If a user cannot do ten, they do what they can.
- **The climb.** Three sessions in a row at the same number rated "just right" (an unrated session counts as "just right", as before) add 5.
  "Too easy" adds 5 at once.
  "Too hard" or a skip takes 5 off; already at 10, the move steps one rung down its progression chain instead and stays at 10 there (`ProgressionChainSelection`), and the user climbs back only when a later session clears that lower rung's advancement criteria again.
  It still backs off faster than it climbs: one bad day steps back, a climb takes three good ones.
- **Old numbers.** A number logged before the grid (13, 14) is read rounded down onto it (10) at the next session, never below 10, and a catalog default such as 12 is served as 10.
  The logs themselves are never rewritten.
- **"Couldn't finish".** The completion screen keeps its rating.
  After "too hard" it lists the session's worked strength and primal moves, and the user taps any they could not finish.
  A tapped move steps back and that session never counts toward its advancement (`WorkoutLog.countsTowardAdvancement(_:)`), including a Foundation line and so the earned Strength Phase.
  An untapped move in that session neither steps back nor counts as a "just right" session toward its climb, and still counts toward its advancement.
  "Too hard" with nothing tapped steps every move back, as "too hard" always has, and, as the completion screen says everything eases off, that session counts toward no move's advancement, the same as if every move were tapped.
  Because an earned phase is never revoked (ADR-0006), a session's own log is evaluated for the earned phase only once the completion screen closes, after its rating and marks are saved (`SessionCompletionService.recordEarnedPhase()`); a session whose completion screen never closes is evaluated as it was left, no later than the next session completion or app open.
  The mark is one optional flag per move on the stored log (`LoggedExercise.couldNotFinish`), so older logs and older app versions read unchanged.
  It is post-session and per move, never per set: `CompletedSet` still carries only `reps` and `durationSeconds`, and `NoPerSetCompletionTrackingGuardTests` is narrowed only to name this one flag on `LoggedExercise`.
- **Advancement criteria.** Every catalog rep criterion at or below 10 per set is raised to 15, keeping its set count and per-side wording (for example "3x5 clean reps per side" and "3x10 clean reps" become "3x15 clean reps per side" and "3x15 clean reps"; 21 criteria in all); criteria above 10 stay as they are, and no hold criterion changed.
  This is the captain's option C (2026-11-02): a move is first served at 10, so a criterion of 10 would let one finished session clear it and the hardest ladders could be climbed a rung per session.
  At 15, a newly reached move opens at 10, climbs to 15 after three "just right" sessions, and clears only on a session at 15 after that, so **a newly reached move now needs at least four sessions before it can clear**.
  A criterion that is not a round number (such as 3x12) is still compared as "at least 12", so it is met by the next round number, 15, and a number logged before the grid still meets it.
  No Foundation entry rung had a criterion at or below 10, so no Foundation changes; a Foundation line already cleared stays cleared and an earned Strength Phase is never revoked (ADR-0006).
- **Warm-up and cooldown stretches** keep their round catalog lengths (30, 40 or 45 seconds) and follow the same grid.

### How the existing levers map onto five-steps

Each lever keeps its direction and stays within its rails.

| Lever | Before | On the grid |
| --- | --- | --- |
| Session Policy `progressionRate` (0.5-2.0) | scaled the percentage of each upward step | sets how many "just right" sessions a climb takes: `ceil(3 / rate)`, so 0.5 asks for 6, 1.0 for 3, 2.0 for 2; a step is always 5, and "too easy" and the step back are unchanged by it |
| Return / Re-entry Ramp scale (0.7-1.0) | scaled the target, at least 1 below the un-held target | scales the target, rounds down onto the grid, and lands at least one step (5) below the un-held target, never under 10; the un-held target is read from the user's last capacity before the Return (`ReturnOverride.capacityLogs`), never from a held session's log, so the ramp walks back up instead of compounding to the floor |
| Cold-start Start Seed `startingRepMultiplier` (x1.0, x1.15, x1.30) | scaled the catalog default | scales the grid-rounded default and lands on the nearest grid number, so a larger multiplier never serves less |
| Start Seed volume easing after a cold-start down-signal | `x0.8` per signal, through the ramp's old back-off constant | the same `x0.8` per signal, now `ColdStartOverride.volumeEaseFactor` |

## Considered Options

- **Multiples of five from 5** - rejected by the captain: the floor is 10.
- **"Too hard" steps everything back** - kept only for "too hard" with nothing tapped, where every move also loses the session toward moving up; the captain chose to ask which moves were not finished so only those step back and lose the session toward moving up.
- **Climb after one good session** - rejected: a step of five is large for a small number, so the climb waits for three.

## Consequences / Trade-offs

- Numbers change less often but by more: a target holds for three sessions and then moves by five.
- A user served ten of a hard move who can do only a few still logs ten; the "couldn't finish" mark is what keeps that session from advancing them.
- A user partway up a ladder whose criterion moved from 10 (or less) to 15 needs a session at 15 before they move up, even if they once logged the old number; a rung they have already reached is never taken away.
- Rounding old numbers down can serve a returning user slightly less than they last did, never more.
- A user on a stepped-down rung sees the higher rung on the progression map as where they reached; the map is unchanged by this decision.
- Reverting restores the percentage ramp; numbers already on the grid are valid inputs to it, and the `couldNotFinish` flag is optional, so logs written meanwhile still load.
