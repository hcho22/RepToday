# ADR-0007: Beginner and intermediate users get staple movements only

- Status: Accepted
- Date: 2026-10-01
- Story: captain request, "update the list of exercises for reptoday for beginner/intermediate users"
- Supersedes / amends: the fitness-level difficulty band as the engine's "too hard" gate (the Effective Difficulty Cap of US-SP01), ADR-0004's bound on the accessory depth mismatch (now bounded by staples instead of the band)

## Context

Rep Today builds discipline first.
The catalog offered 76 movements, and a beginner or intermediate user was gated only by a difficulty band (beginner 1-2, intermediate 1-3).
That band let through movements most people would not call by name (Hollow Rock, Reverse Snow Angel, Lizard Crawl, Underswitch), and it could not express "the easy version of a classic is fine, the exotic one at the same difficulty is not".
The captain wants beginner and intermediate sessions built from the movements people already know - push-ups, squats, planks, bridges - and the rest saved for later.

## Decision

**Which movements a user may get is decided in one place, `MovementAccess`, from the self-reported fitness level and the earned phase.**

1. **Level-based gate.**
   Each catalog movement carries an `audience`: the lowest fitness level for which it is a *staple* (`beginner`, `intermediate`, `advanced`), or `version2`.
   In the Discipline Phase a beginner or intermediate user is offered staples only, and an advanced user keeps today's variety.
   The gate is the level the user picked at onboarding.
   No setting to change it is added.
2. **Staples are authored, not derived.**
   A staple is a movement most people already know by name, so the list is data on each movement, not a difficulty cut-off.
   Staples for beginner and intermediate users: Wall, Incline, Knee and Standard Push-Up, Floor Tricep Dips, Wall Scapular Pull, Superman Hold, Wall Sit, Bodyweight Squat, Reverse Lunge, Glute Bridge, Single-Leg Glute Bridge, Bodyweight Good Morning, Forearm Plank, Bird Dog, Bear Crawl, plus 16 stretches.
   Intermediate users also get Diamond Push-Up, Supine Floor Row, Sumo Squat, Split Squat, Marching Glute Bridge, Single-Leg Romanian Deadlift, Side Plank, Dead Bug and Crab Walk.
   Everything else that is not a Strength-Phase skill is advanced only.
3. **Version 2 removals.**
   Gorilla Walk, Lizard Crawl and Underswitch are withdrawn for every user in every phase until version 2.
   They stay in `Exercises.json` marked `version2` so they are recoverable, and the exercise service never serves them, so no session, swap, progression map, Coach context or analytics surface can name one.
   The dedicated primal block now has one chain; a beginner's primal block is Bear Crawl alone and the timing fit lets strength absorb the leftover time.
   The 30-minute blend lost its primal accessory in the reserve, so the fit's worst landing there is 24 seconds off target, still inside the +/-60 second tolerance.
4. **Sumo Squat and Dead Bug move later.**
   Sumo Squat moves behind Bodyweight Squat (Wall Sit, Bodyweight Squat, Sumo Squat, Cossack Squat, ...), so a beginner's squat progression is Wall Sit then Bodyweight Squat.
   Dead Bug already follows Bird Dog in the core stability chain, so the order is unchanged: Bird Dog, then Dead Bug for intermediates, with Bear Hold advanced only.
   Every chain stays a clean doubly-linked ladder, and loading the catalog now checks that.
5. **Pull is the one exception to "familiar only".**
   Pull keeps its current equipment-free movements.
   The rule that only the horizontal chain clears the Pull foundation (ADR-0006) stands, and real pull-ups wait for the version 2 equipment work.
6. **Earning the Strength Phase lifts the restriction.**
   Every movement opens at once: the advanced-only movements and the Strength-Phase skills.
   Only the version 2 withdrawal survives it.
   The graduation reveal and the progression map copy say so for each audience: a beginner or intermediate user gains every movement beyond the staples, an advanced user only the Strength-Phase skills.
7. **Existing users move, history stays.**
   A user partway up a progression on a movement they no longer get is served the closest movement they do get on the same progression: the highest allowed rung at or below where they were, or the lowest allowed rung if none sits below.
   This is derived from history at read time, so no logged workout is rewritten or deleted, and foundations already cleared stay cleared because clearing reads the entry rung of each counting chain and every entry rung is a staple or already logged.
   The Progress tab's chain position, progression map, strength journey and the Coach's context bundle read the same rule, so they report the rung the user is actually served.
   The strength journey keeps every rung the user worked as a milestone, including one they no longer get, and never reports the served rung as reached before they work it; until then that line carries no Coach trend, so time spent on the old rung never reads as a stall.
   A past log of a withdrawn movement still counts in the totals that read the log's own pillar and pattern (balance, weekly volume, sessions), but no surface names it.
8. **A one-time note.**
   Installs that predate this change, whose users are beginner or intermediate and in the Discipline Phase, see "Your sessions now focus on the classics. More movements unlock when you earn the Strength Phase." once on the Ready Screen.
   It uses the `hasSeenFoundationsUpdateNote` precedent from ADR-0006: a persisted one-shot flag, marked seen when onboarding completes so a brand-new install never sees it, and never shown to advanced users or Strength-Phase users, whose sessions did not change.

## Consequences

- Beginner and intermediate pools shrink sharply: a beginner sees 16 training movements and 16 stretches, an intermediate user 25 and 16, and an advanced user 39 and 26 (47 training movements once Strength is earned).
- Every foundation stays clearable from staples by a beginner: Push (Wall Push-Up), Pull (Wall Scapular Pull), Legs squat side (Wall Sit or Reverse Lunge), Legs hinge side (Glute Bridge or Bodyweight Good Morning), Core (Forearm Plank or Bird Dog).
- Every strength pattern keeps at least two staple stretches complementing it, so the bookends' lead-complement preference still works.
- The fitness-level difficulty band no longer gates the pool: staples sit inside it by construction, advanced users saw the whole band, and the Strength Phase lifted it, so it would never withhold anything `MovementAccess` allows.
  The cold-start capped difficulty and the Return cap are separate rails and are unchanged.
- The accepted depth mismatch between a maxed primary and a shallower accessory chain (ADR-0004) is now bounded by staples: a beginner tops both push chains at difficulty 2 (Standard Push-Up and Floor Tricep Dips, zero mismatch), while an intermediate's horizontal chain reaches Diamond Push-Up (difficulty 3) against Floor Tricep Dips (Pike Push-Up is advanced only), a one-tier mismatch, the same bound an advanced user has.
- A paused session written before this change that already contains a withdrawn movement still resumes with it, since a paused snapshot carries its own movements; it is not offered again afterwards.
- A user whose only history on a line sits on a chain they no longer get anything from (a beginner who only trained the Hollow Hold chain for core) sees that line as not started on the Progress tab, though the foundation they cleared there stays cleared.

## Alternatives considered

- **Re-rate difficulty instead of a per-movement field.** Rejected: difficulty measures how hard a rung is, not whether most people know it by name, so a cut-off would still let Hollow Rock in or push Superman Hold out.
- **Gate on earned history instead of the self-reported level.** Rejected by the captain: the gate is the level chosen at onboarding, which is simple to explain and has no new state.
- **Keep the difficulty cap alongside the new gate.** Rejected: two rules deciding which movements a user gets could disagree, and the cap withholds nothing the staples gate allows.
- **Delete the three crawls from the catalog.** Rejected: they are wanted back in version 2, so they are withdrawn, not removed.
- **A setting to change the fitness level.** Out of scope: the captain asked for no such setting.
- **Rewrite existing users' progress to the new rungs.** Rejected: the move is derived at read time, so logged workouts are never touched and a revert restores today's behavior.
