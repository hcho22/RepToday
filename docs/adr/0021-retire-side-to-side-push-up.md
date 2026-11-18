# ADR-0021: Side-to-Side Push-Up leaves the push ladder

- Status: Accepted (decided 2026-11-17); implemented 2026-11-17 (`Resources/Exercises.json`).
- Date: 2026-11-17
- Deciders: captain (2026-11-17)
- Amends: [ADR-0020](0020-push-ladder-from-standard-burpee-no-nordic.md) - its horizontal push ladder, the intermediate push staples, and the per-side push rungs.
- Relates to: `CONTEXT.md` -> "Staple movement"; [ADR-0007](0007-staple-movements-for-beginner-and-intermediate.md) (the closest-rung rule); [ADR-0008](0008-static-trainer-pose-art-replaces-lottie-demo.md) (Trainer pose art).

## Context

ADR-0020 added Side-to-Side Push-Up to the horizontal push ladder between Diamond and Spider Push-Up.
Trainer pose art was produced for the other movements ADR-0020 added, but no usable image could be produced for Side-to-Side Push-Up.
The captain asked for the movement to be removed from the app entirely.

## Decision

**The horizontal push ladder runs Standard, Wide, One-Legged, Diamond, Spider, Explosive, Burpee with Push-Up, Archer, Assisted One-Arm, One-Arm.**

1. **Diamond climbs straight to Spider**, and Spider regresses to Diamond.
   Every other rung keeps its audience, phase, per-side counting and place relative to its neighbours.
2. **Side-to-Side Push-Up is retired, not deleted**, by ADR-0020's rule for removed rungs.
   It stays in `Exercises.json` with the `retired` audience, alone in its own retired chain (`push_side_to_side_retired`), so old logs, paused sessions and the Coach's reading of history still name it.
   The exercise service never serves it, so no session, swap, Practice Movement, Different workout, progression map or Coach catalog can offer it.
3. **Diamond Push-Up replaces it (`Exercise.replaces`).**
   Diamond is the highest rung at or below Side-to-Side that its users still get, ADR-0007's closest-rung rule.
   A log of Side-to-Side places the user on Diamond; Diamond's Earned Reps open at the bottom of its range, and clearing Diamond and advancing past it read Diamond's own logs, exactly as ADR-0020 set for the rungs it removed.
   No logged workout is rewritten.

## Consequences

- An intermediate's Practice Movement after Diamond is Spider Push-Up.
- A user who was on Side-to-Side Push-Up moves to Diamond Push-Up at the bottom of its range, and climbs to Spider when they clear Diamond. This move is not undone if the change is reverted.
- The Progress tab's strength journey reads only movements the app still serves, so time on Side-to-Side does not appear as a milestone; it still counts toward balance, weekly volume and sessions, and the Coach still reads it by name.
- A saved Custom Workout step that names Side-to-Side Push-Up becomes Diamond Push-Up when the Coach loads it, through the same `replaces` link (`CustomWorkout.servingReplacements`): its name, per-side counting and estimate follow Diamond in the card, the editor and the player, so a Custom Workout never shows or plays the retired movement; the step keeps its saved sets, reps and rest.
- A session already paused on Side-to-Side Push-Up before the update still resumes and plays it as saved, with the card's icon in place of Trainer art; nothing rewrites a paused snapshot.
- The catalog still has 83 movements; the app serves 69.

## Alternatives considered

- **Delete it from `Exercises.json`.** Rejected for the reason ADR-0020 rejected it: old logs and paused sessions must still resolve by name, and the Coach names history from the catalog.
- **Spider Push-Up replaces it.** Rejected: a user whose only recent work was Side-to-Side would skip Diamond's clear and move up a rung they never earned; ADR-0007 places a user at the highest rung at or below where they were.
- **Keep it and ship it with the card's icon.** Rejected by the captain: the movement leaves the app.
