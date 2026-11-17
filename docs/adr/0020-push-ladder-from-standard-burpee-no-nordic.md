# ADR-0020: The push ladder starts at Standard, Burpee joins the squat ladder, the Nordic curls leave

- Status: Accepted (decided 2026-11-16); implemented 2026-11-16 (`Resources/Exercises.json`, `Models/Exercise.swift`, `Services/Mock/MockExerciseService.swift`, `Services/Engine/ProgressionChainSelection.swift`, `Services/Progress/ProgressAnalytics.swift`, `Views/ActiveSession/ActiveSessionView.swift`).
- Date: 2026-11-16
- Deciders: captain, via the movement change request and the details settled with it (2026-11-16)
- Amends: [ADR-0006](0006-foundations-push-pull-legs-core.md) - the Push foundation's horizontal entry rung is now Standard Push-Up; [ADR-0007](0007-staple-movements-for-beginner-and-intermediate.md) - its staple lists and its "every foundation stays clearable from Wall Push-Up" consequence.
- Relates to: `CONTEXT.md` -> "Foundation", "Staple movement", "Variation"; [ADR-0014](0014-retire-primal-pillar.md) (the retired audience); [ADR-0015](0015-practice-movement-bypasses-staple-gate.md); [ADR-0018](0018-session-sizing-and-day-matched-bookends.md).

## Context

The horizontal push ladder opened with Wall, Incline and Knee Push-Up, and Knee Push-Up was a station of its own on many beginners' Push Days.
The captain wants Push Days built from push-ups people train with, starting at the Standard Push-Up, with the easier versions offered only as a way to do a Standard push-up until it comes.
The captain also asked for more push-up variety above Standard, a burpee on Legs Days, and the removal of the Nordic curl, which needs something to hold the feet down.

## Decision

**The horizontal push ladder runs Standard, Wide, One-Legged, Diamond, Side-to-Side, Spider, Explosive, Burpee with Push-Up, Archer, Assisted One-Arm, One-Arm.**

1. **Push tiers.**
   Standard, Wide and One-Legged Push-Up are beginner staples; Diamond, Side-to-Side, Spider, Explosive Push-Up and Burpee with Push-Up are intermediate staples; Archer, Assisted One-Arm and One-Arm Push-Up are advanced, and the last two keep their Strength-Phase lock.
   Side-to-Side and Spider Push-Up are counted per side, like Archer.
2. **Wall, Incline and Knee Push-Up leave the ladder.**
   The app never serves them as a station again.
   The Standard Push-Up's card carries one line instead: "Can't do a full push-up yet? Do it against a wall, on an incline or on your knees."
   That line is catalog data (`Exercise.cue`) that the exercise screen shows under the movement's name.
3. **Burpee (no push-up) joins the squat ladder after Sumo Squat** as an intermediate staple: Wall Sit, Bodyweight Squat, Sumo Squat, Burpee, Cossack, Shrimp, Assisted Pistol, Pistol.
4. **Both Nordic curls leave**, so the bridge ladder ends at Long-Lever Single-Leg Bridge and, like Pull's ladder, has no Strength-Phase rung.
5. **The removed movements are retired, not deleted.**
   Wall, Incline and Knee Push-Up and both Nordic curls stay in `Exercises.json` with the `retired` audience, in their own retired chains (`push_horizontal_retired`, `hinge_nordic`), so old logs, paused sessions and the Coach's reading of history still name them.
   The exercise service never serves a retired movement, so no session, swap, Practice Movement, Different workout, progression map or Coach catalog can offer one.
   Their Trainer art stays, because a session paused before the update still plays with them.
6. **A user on a removed rung keeps their place (`Exercise.replaces`).**
   Standard Push-Up replaces Wall, Incline and Knee Push-Up, and Long-Lever Single-Leg Bridge replaces both Nordic curls: the closest rung each user still gets on the same ladder, the rule ADR-0007 set for movements a user no longer gets.
   A log of a replaced movement places the user on its replacement, in the engine's chain selection and on the Progress tab's chain position and progression map.
   It moves only where the user stands: the replacement's Earned Reps open at the bottom of its range, and clearing it, advancing past it and clearing a foundation all read the replacement's own logs.
   No logged workout is rewritten.
   The catalog loader rejects a `replaces` entry that is not a retired or withdrawn movement of the same pattern, that two rungs claim, or that sits on a withdrawn rung.
7. **The Push foundation clears on Standard Push-Up** (the horizontal ladder's new entry rung) or Floor Tricep Dips (the vertical ladder's, unchanged).
   An earned Strength Phase is never revoked.
8. **New movements ship without Trainer art** and the card shows its icon, as it does for any movement without a pose pair; their art is a separate later task.

## Consequences

- A beginner's Push Day opens at Standard Push-Up, so the first push station is harder than it was for a user who would have started at Wall Push-Up; the card's line tells them how to make it easier.
- A user who was on Wall, Incline or Knee Push-Up moves to Standard Push-Up at the bottom of its range.
  A user on either Nordic curl moves to Long-Lever Single-Leg Bridge.
  Neither move is undone if this change is reverted.
- A Discipline user who cleared Push on Wall Push-Up, and not yet on Standard Push-Up or Floor Tricep Dips, has to clear it again.
- The Progress tab's strength journey reads only movements the app still serves, so time spent on a removed rung does not appear as a milestone.
  That history still counts toward balance, weekly volume and sessions, and the Coach still reads it by name.
- Intermediate users get five more push rungs and one more squat rung to climb before the advanced-only ones, and an intermediate's Practice Movement after Diamond is Side-to-Side Push-Up instead of Archer.
- Injury flags exclude whole movement patterns, so Burpee with Push-Up (a push movement) is not excluded by a knee, hip or ankle flag, and Burpee (a squat movement) is excluded by a knee or hip flag but not an ankle flag. Per-movement contraindications are out of scope here.
- The catalog has 83 movements, of which the app serves 70.

## Alternatives considered

- **Keep the easy push-ups as an optional regression a user could pick.** Rejected by the captain: the app never serves them as a station; they are a note on the Standard card.
- **Delete the removed movements from the catalog.** Rejected: old logs and paused sessions must still resolve by name.
- **Keep the removed rungs in their ladders as a withdrawn head or tail.** Rejected: the live ladders would no longer start at order 0 or end at their real top rung, and Long-Lever would still link up to a movement nobody gets; a separate retired chain plus an explicit `replaces` keeps the live ladders exactly as they are served.
- **Re-enter users on a removed rung at the ladder's entry with no stand-in.** Rejected for the Nordic curls: a user whose recent history is only Nordic work would drop to Glute Bridge instead of Long-Lever.
