# ADR-0013: Fixed 4 sets, reps in steps of 5, reps as the fit lever, and fixed movement counts

- Status: Accepted (decided 2026-11-10); not yet implemented (M1, `US-TD00`...`US-TD04`).
- Date: 2026-11-10
- Deciders: captain, via the Push/Pull/Legs design grill (2026-11-09 to 2026-11-10)
- Spec: `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md`
- Supersedes: [ADR-0004](0004-round-cap-wide-circuit.md) entirely (round cap 2-4 and filling long sessions wider).
- Amends: [ADR-0003](0003-even-round-circuit-timing.md) - even rounds stay, but between-round rest is no longer the primary fit lever and the +/-60s tolerance becomes about +/-3 min.
- Supersedes: [ADR-0010](0010-short-rests-stretched-work-windows.md)'s stretched work windows as the fit lever and its 15-second cap on every rest; its hands-free player stays.
- Amends: [ADR-0011](0011-round-numbers-and-the-climb.md) - the grid of multiples of five and the "couldn't finish" mark stay; the earned range, the climb and the advancement bar change as recorded below.
- Relates to: `CONTEXT.md` -> "Earned Reps / Rep Ramp", "Padding", "Practice Movement", "Continuous Circuit".

## Context

Under ADR-0004 a long session promotes further-chain accessories, so a 45-minute session serves about 11-14 movements and a 60-minute one about 12-18.
Users want fewer movements, more reps and more recovery, in a format that is easy to read: round numbers and a constant set count.

## Decision

**Every training station is 4 sets of a multiple-of-5 rep target; session length changes reps and rest, never sets, and only a few movements are served.**

- Bookends hold at most 2 warm-up and 2 cooldown movements. Main movements by length: 5-10 min 1, 15-20 min 1, 30 min 2, 45 min 3, 60 min 4, plus one Core Sprinkle (none at 5-10 min).
- Push and Pull have two ladders each, so their third and fourth slots are Practice Movements (ADR-0015). Legs uses its four ladders' current rungs.
- Every main and core station is exactly 4 sets. Reps are multiples of 5: 15-30 for beginner and intermediate, 15-50 for advanced; per side 5/10/15; holds in 5-second steps.
- Each movement carries Earned Reps, grown by the rated-session ramp. Advancing a rung needs 4 clean sets at the top of the range at earned reps, not rated too hard.
- Reps are the fit lever: short sessions go below Earned Reps (floor 10, per side 5); long sessions Pad above them up to the level's top. Padded reps are logged as done but never move Earned Reps or a rung.
- Rest after a round is at most 60s on sessions of 30 min or less. On 45/60 min sessions the pause between movements grows from 15s to as much as 60s, and rest after a round grows to a level cap: beginner 2:00, intermediate 1:30, advanced 1:00. If a session still cannot fill, it runs short and Today shows the honest time.

## Considered Options

- Straight sets or supersets instead of the circuit - rejected; the captain kept the continuous circuit.
- Letting long sessions finish short with no padding - rejected in favor of padding plus level-capped rest.
- Raising the set count on long sessions - rejected; 4 sets is a fixed rule.

## Consequences

- Planning modelled beginner and intermediate 45/60 min sessions at 10-20 min short with 60s rest; the level-capped rest and longer transitions close most of that gap, and a test-only fit harness (`US-TD00`) guards it.
- Because logging records prescribed = performed (US-CC09), each prescription carries its earned level and station role so Padding and Practice can never inflate progression.
- Foundation clearing gets harder (ADR-0006 amendment), so Discipline users' cleared counts may drop on update.

## Reconciliation with ADR-0010 and ADR-0011 (recorded at M1 implementation, 2026-11-10)

The design grill that produced this decision read a checkout that predated ADR-0010 and ADR-0011 (both landed 2026-11-02).
M1 is implemented on top of them, and where the two disagree this ADR wins as the newer captain decision:

- **Rests.** The 15-second floor of ADR-0010 is the starting value for both gaps.
  On sessions of 30 minutes or less the rest after a round may grow to 60 seconds; on 45 and 60 minute sessions the pause between movements may grow to 60 seconds and the rest after a round to the level cap.
  The player caps a rest at the beginner cap (2:00), not at 15 seconds.
- **Stretched work windows are retired.** Reps (Padding) and then rest fill a session; a session that still cannot fill runs short and says so.
  `PrescribedExercise.stretchSeconds` stays decodable so sessions saved before M1 still play.
- **The grid.** ADR-0011's multiples of five stay, and its 10-rep floor becomes the short-session floor (per side 5).
  The earned range starts at 15 (per side 5, holds 20 seconds), so a new movement opens at 15 rather than 10.
- **The climb.** The planning default replaces ADR-0011's three-session climb: Earned Reps climb one step after each session, not rated too hard, whose prescription was at or above Earned Reps.
  A Training Day works each ladder about once per Cycle, so a three-session climb would take two to three weeks per step.
  The Session Policy pace keeps its direction: a climb takes `ceil(1 / progressionRate)` qualifying sessions.
  "Too hard" and "couldn't finish" still step back one step, and at the bottom of the range step down the chain, exactly as ADR-0011 records.
- **Advancement.** The per-movement `advancementCriteria` numbers (ADR-0011's "raised to 15") give way to the one bar of this ADR, judged at the user's level.

These reconciliations are the implementer's reading and are flagged for the captain to confirm (PRD Open Question 2).
