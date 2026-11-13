# ADR-0018: Session sizing by length and day-matched bookends

- Status: Accepted (decided 2026-11-12); implemented 2026-11-12 (`US-SZ01`...`US-SZ03`; `Services/Engine/SessionAssembly.swift`, `Models/Exercise.swift`, `Models/TrainingDay.swift`).
- Date: 2026-11-12
- Deciders: captain, via the session-sizing design grill (2026-11-12); Part A of the PRD approved as written, Open Question 2 settled in favor of the higher 45 and 60 minute counts.
- Spec: `.claude/agent/tasks/prd-health-coach-sizing-signout_261112.md` (Part A)
- Amends: [ADR-0013](0013-fixed-four-sets-five-step-reps.md) - its movement counts by length; 4 sets, the rep grid, reps as the fit lever and the rest caps stay.
- Amends: US-M02's prefer-then-fill bookend selection, and `prd-ppl-rest-accounts-coach-agent_261110.md` decision 8 (movement counts) and decision 12 (the Variation).
- Relates to: `CONTEXT.md` -> "Training Day", "Core Sprinkle", "Variation", "Pillar"; [ADR-0015](0015-practice-movement-bypasses-staple-gate.md).

## Context

M1 sized a Training Day at 1 main movement up to 20 minutes, which left 10-20 minute sessions as one movement repeated for four rounds, and long sessions with a single Core Sprinkle.
The bookends led with one stretch matching the day's lead pattern and filled the rest by variety alone, so a Push Day could close on a hamstring stretch.
The captain asked for more main work at every length, more core in long sessions, and warm-ups and cooldowns that prepare and relieve the muscles trained that day.

## Decision

**Main movements by length are 1 (5 min), 2 (10-15), 3 (20-30), 4 (45) and 5 (60); Core Sprinkles are 0 (5-10 min), 1 (15-30) and 2 (45-60), plus one with Abs; every bookend stretch complements the day's group.**

- Slot order is unchanged: a Push or Pull Day's slots 1-2 are its two ladders' current rungs and slots 3-4 their Practice Movements; a Legs Day fills from the squat, lunge, bridge and hip ladders, one squat-side and one hinge-side ladder first.
- A Push or Pull Day's fifth slot (60 min) is a **Variation**: a catalog movement that declares `variationOf` a parent rung.
  It is eligible only while that parent is the user's current rung, while the eligible pool offers it (movement access, injuries, skips), and while both Trainers have its full start/end pose pair, asked through `TrainerPoseResolver`.
  Several eligible Variations rotate, least recently done first.
  With none eligible the slot stays empty and the fit fills the time with reps and rest.
  A Variation runs at its parent's number when both are counted alike, records no Earned Reps, and carries `StationRole.variation`, which never advances a rung, the Rep Ramp or a Foundation.
  It sits alone in its own one-rung chain, so no ladder serves it, and the library loader rejects one that does not.
  Landing a Variation's catalog entry and its art is the only step that makes it live.
- A Legs Day's fifth slot is the Practice Movement of its first ladder.
- With an Abs Focus Area, a 45 or 60 minute session's three Core Sprinkles are one from each core ladder.
- Bookends are day-matched: on a Push Day every warm-up and cooldown stretch complements push, on a Pull Day pull, on a Legs Day squat or hinge.
  The existing variety order (a Different workout press's moves last, then no recent repeats, then least recently done) picks among the matching stretches, and an unmatched stretch is used only once the matches run out.
  The cooldown still takes holds first, inside the matching stretches and inside the fallback separately, and it now picks before the warm-up, so the day's matching holds close the session even when only a few match; the warm-up then takes the freshest matches left.
- The desk-worker `sitsLong` preference reorders posture and hip openers first inside the matching stretches and inside the fallback separately; it never brings an unmatched stretch ahead of a match.
- Bookend counts, the Rest Day Recovery flow, the Practice fallback, Focus Area ordering, 4 sets per station, 5-step reps and no-mixed-groups are unchanged.

## Considered Options

- Keep 45 and 60 minute main movements at 3 and 4 and change only 10-30 minutes (PRD Open Question 2) - rejected by the captain, who confirmed the higher counts against the 2026-11-10 goal of at most 8 and 9 movements.
- Keep prefer-then-fill and only widen it to every slot - rejected; strict matching with a fallback says what the captain asked for and keeps a bookend from ever emptying.
- Fill a Push or Pull Day's fifth slot with a second Practice Movement or a further ladder - rejected; a Variation varies the rung the user is on without previewing or advancing anything.

## Consequences

- Movement counts per session (warm-up + main + core + cooldown) become 2 (5 min), 3 (10), 6 (15), 7 (20), 8 (30), 10 (45) and 11 (60), one more with Abs from 15 minutes; a 60-minute Push or Pull Day serves 10 until its first Variation lands.
- More stations in the same minutes leave less room for Padding and rest; `TrainingDayFitHarnessTests` prices every length x level x day x Focus Area set for a fresh, a cold-start and a seasoned history.
  At implementation every fresh and seasoned session landed inside the tolerance (the closest, +164s, an Abs session at 20 minutes for a seasoned user), and no session of 5-20 minutes ran short.
  The honest shortfalls left are cold-start Push and Pull Days at 30-60 minutes, where the cold-start difficulty cap rules out a Practice Movement and the slot stays empty (a beginner's 60-minute Push Day runs about 51 minutes, an intermediate's 60-minute Pull Day about 43); the added stations make them shorter gaps than before.
  One cold-start case overruns: an intermediate's 15-minute Pull Day with Abs plans about 18 minutes, 5 seconds past the tolerance, with every station already at its short-session floor, so the fit has no lever left and Today shows the honest length.
- Movement access gates stretches as well as training movements (ADR-0007), so a Discipline beginner or intermediate is offered fewer matches than the catalog holds: four push stretches, three pull, ten for Legs.
  Their 30-60 minute Push Day therefore uses all four push stretches every time, and their 30-60 minute Pull Day's fourth bookend stretch is the one fallback.
  New staple stretches are the remedy if that feels repetitive, and are a content task.
- For the same reason, a Discipline beginner or intermediate's 45 and 60 minute Push Day already holds everything a **Different workout** press could rank ahead (both ladders with their Practice Movements, all four push stretches, both core ladders they are offered), so the press returns the same session there.
- The hollow core ladder is advanced-only until the Strength Phase, so a Discipline beginner or intermediate with Abs gets two Core Sprinkles at 45-60 minutes rather than three, one movement fewer rather than a ladder twice.
- `StationRole.variation` is a new stored value; it is decodable by every build from this one on, and the Coach's description of a logged session (`convex/coachPrompt.ts`) shows a Variation as an ordinary station.
