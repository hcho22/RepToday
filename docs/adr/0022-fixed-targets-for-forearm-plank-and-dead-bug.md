# ADR-0022: Fixed Targets for Forearm Plank and Dead Bug, and 0:30 bookend holds

- Status: Accepted (decided 2026-11-19); implemented 2026-11-19 (`Services/Engine/RepGrammar.swift`, `Resources/Exercises.json`).
- Date: 2026-11-19
- Deciders: captain (interview of 2026-11-19, `.claude/agent/tasks/prd-fixed-core-targets_261119.md`)
- Amends: [ADR-0013](0013-fixed-four-sets-five-step-reps.md) - its Earned Reps ranges, climb and advancement bar, for two movements; [ADR-0011](0011-round-numbers-and-the-climb.md) - the catalog lengths of held warm-up and cooldown stretches.
- Relates to: `CONTEXT.md` -> "Fixed Target", "Earned Reps / Rep Ramp", "Round numbers", "Bookend hold"; [ADR-0018](0018-session-sizing-and-day-matched-bookends.md) (day-matched bookends, unchanged); [ADR-0015](0015-practice-movement-bypasses-staple-gate.md) (Practice Movements).

## Context

Since ADR-0013 every strength and core movement is prescribed through **Earned Reps**: a per-movement number that climbs 5 after each qualifying session, drops 5 after "too hard", and lives inside a level range (holds 20-60 seconds, advanced 90; reps per side 5-15).
The captain wants Forearm Plank and Dead Bug to ask one known number of each fitness level instead: Forearm Plank 0:30, 1:00 and 3:00 per hold, Dead Bug 10, 15 and 20 per side.
The advanced numbers sit above the range caps (90 seconds, 15 per side), so they cannot be reached by Earned Reps at all.
The captain also wants every held warm-up, cooldown and Recovery stretch to be 0:30; they were served at each stretch's catalog length (30, 40 or 45 seconds).

## Decision

**Forearm Plank and Dead Bug are served a Fixed Target: a per-level number set by the user's fitness level alone.**

1. **The catalog declares it** (`Exercise.fixedTarget`: a unit and one number per level), and load validation rejects one that is missing a level, off the grid of fives, under the short-session floor, in a unit the movement does not count in, or on anything but a strength rung.
   `RepGrammar` stays the one owner of the numbers: `RepGrammar.fixedTarget(for:level:)` reads it, and `RepGrammar.earnedRange(for:level:)` answers with the target alone for such a movement, so every caller that asks for a range or a top - the fit's Padding ceiling, the served number, the swap's shift, the advancement bar - treats the target as the whole range.
   No engine code names either movement.
2. **It is served as is: no climb, no step back, no Padding.** `AdaptiveOverload.earned` returns the target whatever the history says, and a long session fills its time through other stations and rest.
3. **"Too hard", a skip or "couldn't finish" hold the number** and never step the user down a rung (`AdaptiveOverload.floorStepBackDate` is `nil` for a Fixed Target); that session simply does not count toward advancement.
4. **A short session may cut it** toward the existing short-session floor (10-second hold, 5 per side), and a cut session never counts toward advancement.
5. **The Return ease-in still applies** (`AdaptiveOverload.held`), and the target resumes when the Return window ends, with no climb back.
6. **Moving up takes four clean sets at the target, prescribed at the target, in a session not rated too hard and not marked "couldn't finish"** - the ADR-0013 bar with the target as the top. Foundation clearing reads the same bar. Logs are read as written: a log counts toward moving up only if its sets reached today's target, and a rung or foundation already cleared stays cleared - a user who worked a rung on a Training Day and later moved past it keeps that rung's foundation line (`PhaseEvaluator`), the same evidence that set their frontier above it.
7. **A Practice station of a Fixed Target movement runs at the level target** (`RepGrammar.practiceValue(for:level:)`), may be cut on a short session, and still never advances anything. The shipped catalog never places Dead Bug in a Practice slot, because Core Sprinkles take none; the rule applies wherever a Practice station of such a movement arises.
8. **The Coach speaks in targets.** Its catalog gives each movement's target by level, its context gives the user's targets, and a Coach-written Custom Workout starts these movements at the user's level target (`convex/coachTools.ts`), which the user can still edit.

**Every held warm-up, cooldown and Recovery stretch runs 0:30 at every level** (per side when one-sided: side 1, "Switch sides", side 2).
The bookend rule owns the length (`SessionAssembly.bookendHoldSeconds`, read by `SessionAssembly.bookendValue`), not the catalog: the 0:30 is a rule about the bookends, so a stretch added later with a longer catalog `defaultDurationSeconds` cannot break it, and that catalog value keeps only its other job, seeding a Custom Workout step.
Rep-based bookend moves keep their catalog reps, and day-matched bookend selection (ADR-0018) is unchanged.

Fixed Targets and the bookend rule apply from the next session assembled; no log or paused session is rewritten, and a paused session resumes with the durations it was saved with.

## Consequences

- **An advanced plank block is 4 x 3:00: twelve minutes of holds** before rests, inside the circuit's rounds with the usual hands-free flow and **+ More time**. On a short session the fit cuts it toward the floor rather than dropping the plank (0:10 to 0:20 on a 15-minute advanced session in `FixedTargetSessionSweepTests`).
- **A short session's cut never counts toward advancement**, so an advanced user moves up from Forearm Plank only on a session long enough to serve the full 3:00.
- **No step-down on "too hard"**: a user who struggles with Dead Bug stays on Dead Bug at their target, and the session just does not count. A user stepped down from Dead Bug to Bird Dog before this change is served Dead Bug again, since the step-down is read from the logs and no longer applies.
- **A first session at the target can clear the rung**, since the target is where it opens; every other movement still opens below its top.
- **Old logs are read against the new target for moving up**: an advanced user still on Forearm Plank is not moved up to Side Plank by 90-second plank logs, while an intermediate's 60-second ones still move them up. A user who already moved past the plank keeps the Core line and their Strength-Phase eligibility, since their later Side Plank work shows the rung was cleared.
- **Session sizing shifts, and some beginner sessions run honestly short** (captain, 2026-11-19): shorter bookends and fixed core numbers move a few minutes between stations and rest, and no session ever plans past its length. Where a beginner's plank used to pad to 1:00 to fill the time, it now stays at 0:30, so a session whose other levers are already spent runs short and Today shows its real time - a fresh beginner's 30-minute Legs Day plans 26.5 minutes (it was 28.8). Across `TrainingDayFitHarnessTests`' 1701 cases the honest shortfalls past the tolerance go from 25 to 53, all beginner or cold-start sessions; padding a Fixed Target, longer rests on short sessions and longer bookends were each considered and declined.
- **The "couldn't finish" screen** says on a Fixed Target move's card that the target stays the same and the session just won't count toward moving up, instead of promising it eases off; every other move keeps its wording.
- **Copy**: the two movements' advancement criteria read "4 clean holds at your target" and "4 clean sets per side at your target", and the Progress tab's foundations note names the plank's bar. No app screen shows a range or a next number for a movement, so nothing else changes.
- A revert restores Earned Reps from the next session; a rung advanced under this rule stays advanced, since logs count as written.

## Alternatives considered

- **A new starting point that still climbs.** Rejected: the user would no longer know what the movement asks, and the advanced numbers sit above the range caps, so the climb would stop short of them.
- **Raising the range tops** (holds to 180 seconds advanced, reps per side to 20). Rejected: it would change every other hold and per-side movement's range, Padding and advancement bar, which the captain kept unchanged.
