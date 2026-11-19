# PRD: Fixed Level Targets for Forearm Plank and Dead Bug, and 0:30 Bookend Holds

- Status: **Approved for implementation (2026-11-19).**
  Every decision below was settled with the captain in an interview on 2026-11-19, and the captain approved this PRD for implementation the same day.
- Story prefix: `US-FT##`.
- Related decision (new): [ADR-0022](../../../docs/adr/0022-fixed-targets-for-forearm-plank-and-dead-bug.md).

## Introduction / Overview

Today every strength and core movement is prescribed through **Earned Reps**: a per-movement number that climbs 5 after each qualifying session, drops 5 after "too hard", and lives inside a level range (`RepGrammar.earnedRange`: reps 15-30, advanced 15-50; per side 5-15; holds 20-60 seconds, advanced 90).
Warm-up, cooldown and Recovery stretches are served at each stretch's catalog length (`SessionAssembly.bookendValue`), which today is 30, 40 or 45 seconds for holds.

The captain wants three changes:

1. **Forearm Plank** (`core_forearm_plank`): beginner 0:30, intermediate 1:00, advanced 3:00 per hold.
2. **Dead Bug** (`core_dead_bug`): beginner 10 reps per side, intermediate 15 per side, advanced 20 per side.
3. **Warm-up / cooldown timed stretches**: 0:30 for every level.

The first two become **Fixed Targets**: the number is set by the user's fitness level alone and never climbs or drops from ratings.

## Goals

- A user always knows what Forearm Plank and Dead Bug ask of them at their level.
- Advanced users get a real plank challenge (3:00) and a real Dead Bug challenge (20 per side), above today's range caps.
- Every held warm-up, cooldown and Recovery stretch is a predictable 0:30 (per side for one-sided stretches).
- Nothing else about prescription, progression or session length changes.

## Interview decisions (captain, 2026-11-19)

| # | Decision |
|---|---|
| 1 | The two movements' numbers are **fixed per level**: served as is, no climb, no drop, no Padding on long sessions. Advancing to the next rung (Side Plank; Bear Hold) takes 4 clean sets at the fixed target in a session not rated too hard. |
| 2 | Dead Bug stays `audience: intermediate`; the beginner target is still recorded and used whenever a beginner is served Dead Bug. |
| 3 | Only **held** bookend stretches become 0:30; rep-based bookend moves (Cat-Cow, Arm Circles, World's Greatest Stretch, Hip Circles, Side Bend, Ankle Rocks, Thoracic Rotation, Cossack) keep their rep counts. |
| 4 | One-sided stretches hold 0:30 **per side**. |
| 5 | The Recovery flow uses the same 0:30 holds. |
| 6 | Every other movement (Side Plank, Hollow Hold, Bird Dog, Bear Hold, all main strength moves) keeps Earned Reps unchanged. |
| 7 | A **short session** may still cut a Fixed Target toward the existing short-session floor (10-second hold, 5 per side), and a cut session does not count toward advancement. A long session never pads a Fixed Target. |
| 8 | "Too hard" or "couldn't finish" on a Fixed Target movement **holds** the number: no 5 off, no step down a rung; that session just does not count toward advancement. |
| 9 | The **Return** ease-in (`ReturnOverride`) still applies to these movements. |
| 10 | Dead Bug served as a **Practice Movement** uses the user's level target (a beginner on Bird Dog previews Dead Bug at 10 per side), not the generic Practice value (4 x 5 per side). |
| 11 | Fixed Targets apply from the next session assembled; logs are never rewritten; a rung already cleared stays cleared; past logs count toward future advancement only if they reached the new target. |
| 12 | Advancement copy for the two movements reads "4 clean holds at your target" (plank) and "4 clean sets per side at your target" (Dead Bug) wherever criteria show, including Progress and Coach surfaces. |
| 13 | Session-sizing consequences of shorter bookends and fixed core numbers are accepted; the requested session length still holds. |
| 14 | The Coach starts a Custom Workout's Forearm Plank or Dead Bug at the user's level target; the user may still edit it. |

## Verified facts on current main (2026-11-19, read-only)

- `core_forearm_plank`: `isHold`, `defaultDurationSeconds 30`, `audience beginner`, chain `core_plank` order 0 (no regression), progression `core_side_plank`, criteria "4 clean holds at the top of your hold range".
- `core_dead_bug`: reps, `isPerSide`, `defaultReps 10`, `audience intermediate`, chain `core_stability` order 1, regression `core_bird_dog`, progression `core_bear_hold`, criteria "4 clean sets per side at the top of your rep range".
- Advanced plank 180 s exceeds the advanced hold cap (90); advanced Dead Bug 20 per side exceeds the per-side cap (15) at every level.
- All targets sit on the grid of fives (ADR-0011).
- Every station runs `RepGrammar.setsPerStation` = 4 rounds; an advanced plank is 4 x 3:00 = 12 minutes of holds before rests.
- Earned Reps start (`AdaptiveOverload.earned`), climb and step back in `Services/Engine/AdaptiveOverload.swift`; ranges, short-session floor, Practice values and `isAdvancementMet` live in `Services/Engine/RepGrammar.swift`.
- The fit (`SessionAssembly`) cuts reps toward the short-session floor, then drops stations, and pads up to the range top on long sessions.
- `SessionAssembly.bookendValue(for:)` serves warm-up, cooldown and Recovery stretches at catalog length floored to fives, never under 10.
- Held mobility stretches today: 30 s (12 entries), 40 s (Lizard Lunge, per side), 45 s (Deep Squat Hold, Pigeon per side, Frog, Child's Pose, Butterfly).
- `advancementCriteria` text is surfaced through `Models/Exercise.swift`, `Models/CustomWorkout.swift`, `Views/ActiveSession/ActiveSessionView.swift` and `Services/Coach/CoachProposalApplier.swift`; the implementer must find every other surface (Progress, Coach context sent to the agent) before changing copy.

## User Stories

### US-FT01: Fixed Target in the catalog and grammar

**Description:** As the engine, I need one place that says a movement has a per-level Fixed Target so that every prescription, fit, practice and advancement path reads the same number.

**Acceptance Criteria:**
- [ ] The catalog can declare a per-level Fixed Target for a movement (beginner, intermediate, advanced), in seconds for a hold and reps per side for a per-side move; `core_forearm_plank` declares 30/60/180 and `core_dead_bug` declares 10/15/20.
- [ ] Catalog validation rejects a Fixed Target that is off the grid of fives, missing a level, or declared on a movement whose kind does not match.
- [ ] `RepGrammar` exposes the Fixed Target for a movement and level, and every caller that asks for a movement's range or top treats a Fixed Target movement as having exactly that one value.
- [ ] Movements without a Fixed Target behave byte-identically to today (prescription, ranges, climb, advancement).
- [ ] Unit tests cover all six numbers, the validation rejections and the unchanged path for a non-fixed movement.

**Validation Test:** Assemble sessions for a beginner, intermediate and advanced fixture at 45 minutes; Forearm Plank and Dead Bug stations prescribe exactly 30/60/180 s and 10/15/20 per side; a Side Plank station still prescribes its Earned Reps.

### US-FT02: Prescription ignores the climb and Padding

**Description:** As a user, I want Forearm Plank and Dead Bug to ask the same thing every session at my level so that I always know my target.

**Acceptance Criteria:**
- [ ] `AdaptiveOverload.earned` returns the Fixed Target for a Fixed Target movement regardless of history, rating, skip or "too easy".
- [ ] "Too hard", a skip or "couldn't finish" on a Fixed Target movement never lowers the number and never steps the user down a rung (Dead Bug never drops to Bird Dog through this path); that session does not count toward advancement.
- [ ] A long session never pads a Fixed Target station above its target; the fit fills the time through its other levers (other stations' Padding, rest), and the requested length still lands within today's tolerance.
- [ ] The prescription and log still record `earnedReps` / `earnedDurationSeconds`, set to the Fixed Target, so history readers keep working.
- [ ] Unit tests cover each rating signal and a 60-minute session with no padding on the fixed station.

**Validation Test:** Seed a history with "too hard" twice and "too easy" once on Dead Bug for an intermediate; the next session still serves 15 per side and the user is still on Dead Bug.

### US-FT03: Short sessions may cut a Fixed Target

**Description:** As an advanced user on a 15-minute session, I want the plank trimmed to fit rather than dropped so that I still plank on short days.

**Acceptance Criteria:**
- [ ] The fit may cut a Fixed Target station toward the existing short-session floor (10 s hold, 5 per side) using today's cut order, before it drops any station.
- [ ] A session whose Fixed Target station was served below the target never counts toward that movement's advancement (consistent with `isAdvancementMet` requiring the prescription at the target).
- [ ] Every requested length (5-60 minutes) for every level still assembles within the existing tolerance; an engine test sweeps lengths x levels with Forearm Plank and Dead Bug forced into the core slot.

**Validation Test:** An advanced 15-minute Core-slot session serves the plank below 3:00 and lands on length; logging it clean four times never advances to Side Plank.

### US-FT04: Advancement at the Fixed Target

**Description:** As a user, I want to move up from Forearm Plank or Dead Bug once I can do my level's target cleanly so that progression stays earned.

**Acceptance Criteria:**
- [ ] `RepGrammar.isAdvancementMet` treats the Fixed Target as the top: four sets at the target, prescribed at the target, in a session not rated too hard and not marked "couldn't finish".
- [ ] Foundation clearing (`hasCleared`, `clearingSessionCount`) uses the same rule, so the Core foundation line on the plank chain clears at the user's target.
- [ ] Past logs are read as they are: a log counts only if its sets reached the current target; a rung or foundation already cleared stays cleared.
- [ ] Unit tests cover an advanced user whose old logs at 90 s no longer count, and an intermediate whose old 60 s logs do.

**Validation Test:** An intermediate fixture with four clean 60 s plank sets in one session rated "just right" is offered Side Plank next.

### US-FT05: Return ease-in still applies

**Description:** As a user back after a break, I want these movements eased in like the rest so that I do not jump straight to a 3:00 hold.

**Acceptance Criteria:**
- [ ] The Return override lowers a Fixed Target station exactly as it lowers an Earned Reps station today, and a held (Return) session never counts toward advancement.
- [ ] After the Return window the Fixed Target resumes with no climb back.

**Validation Test:** An advanced fixture returning after the Return threshold gets a reduced plank in its first Return session and 3:00 once the window ends.

### US-FT06: Dead Bug as a Practice Movement uses the level target

**Description:** As a beginner on Bird Dog, I want the Dead Bug preview at my target so that the preview matches what I will be asked to do.

**Acceptance Criteria:**
- [ ] A Practice station for a Fixed Target movement is prescribed at the user's level target instead of `RepGrammar.practiceValue`; Practice still never advances anything (`countsForProgression` false).
- [ ] The fit may still cut it on a short session like any station.
- [ ] Other Practice stations keep today's Practice values.

**Validation Test:** A beginner on Bird Dog at 45 minutes gets a Dead Bug Practice station at 4 x 10 per side.

### US-FT07: 0:30 held bookend stretches

**Description:** As a user, I want every held warm-up, cooldown and Recovery stretch to be 0:30 so that the bookends are predictable.

**Acceptance Criteria:**
- [ ] Every held warm-up, cooldown and Recovery stretch is served at 30 s at every level; one-sided holds run 30 s per side (side 1, "Switch sides", side 2).
- [ ] Rep-based bookend moves keep their catalog rep counts.
- [ ] The value comes from one owner (the bookend rule, or the catalog's `defaultDurationSeconds` set to 30 for every held mobility entry, whichever keeps one source of truth; the implementer states which and why).
- [ ] Session sizing re-plans with the shorter bookends; every length x level still lands within tolerance and the day-matched bookend selection (ADR-0018) is unchanged.
- [ ] A session saved before this change resumes with the durations it was saved with.

**Validation Test:** A 30-minute Pull Day's warm-up and cooldown show only 0:30 holds (per side where one-sided) and rep moves at their rep counts; a Recovery flow does the same.

### US-FT08: Copy and Coach

**Description:** As a user, I want the move-up rule and the Coach to speak in targets for these two movements so that nothing mentions a range they do not have.

**Acceptance Criteria:**
- [ ] `core_forearm_plank` criteria read "4 clean holds at your target"; `core_dead_bug` reads "4 clean sets per side at your target"; every surface that shows criteria (session player, Progress, progression map, Coach) shows the new text.
- [ ] Any surface that shows a movement's range or next number shows the single target for these two movements (for example "Target 1:00"), never "20-60 s".
- [ ] The Coach's movement context gives Forearm Plank and Dead Bug at the user's level target, and a Coach-written Custom Workout starts them there; the user can still edit sets, reps and time.
- [ ] Copy follows the existing identity-framed, non-loss-framed tone.

**Validation Test:** Simulator screenshots of the plank and Dead Bug in the player, Progress and a Coach proposal, light and dark, show target wording and the level numbers.

### US-FT09: Domain docs

**Description:** As a maintainer, I want the glossary and decision record to explain Fixed Targets so that a future reader does not "fix" them back into Earned Reps.

**Acceptance Criteria:**
- [ ] `CONTEXT.md` gains a **Fixed Target** entry (a per-level number set by fitness level alone; never climbs, drops or pads; may be cut on a short session or eased on a Return) and the Earned Reps / Round numbers entries name the exception.
- [ ] `CONTEXT.md` states that held warm-up, cooldown and Recovery stretches are 0:30 (per side when one-sided).
- [ ] A new ADR records the Fixed Target decision: context (captain's level numbers above the range caps), decision (decisions 1, 7, 8, 9, 10 above), alternatives rejected (new starting point with climb; raising range tops), consequences (12-minute advanced plank blocks, short-session cuts, no step-down on "too hard").
- [ ] `docs/implementation-log.md` and `docs/test-coverage.md` are updated as the repo's convention requires.

**Validation Test:** The glossary and ADR read correctly on their own and link each other.

### US-FT10: Evidence

**Description:** As the captain, I want one evidence pass so that I can judge the change before release.

**Acceptance Criteria:**
- [ ] Engine evidence: a table of assembled sessions (lengths 15, 30, 45, 60 x three levels) showing the plank or Dead Bug prescription and bookend durations, before and after.
- [ ] Simulator screenshots: an advanced 3:00 plank hold, an intermediate Dead Bug at 15 per side, a 0:30 one-sided bookend stretch with its switch-sides beat, light and dark, on the small and large phone sizes.
- [ ] Unit and UI suites, typecheck and lint pass.

## Functional Requirements

- FR-1: A movement may carry a per-level Fixed Target; only `core_forearm_plank` (30/60/180 s) and `core_dead_bug` (10/15/20 per side) do.
- FR-2: A Fixed Target is served as is: no climb, no step back, no step down a rung, no Padding.
- FR-3: A short session may cut a Fixed Target toward the short-session floor; a cut session never counts toward advancement.
- FR-4: The Return ease-in applies to Fixed Targets.
- FR-5: Advancement from a Fixed Target movement needs four clean sets at the target in a session not rated too hard and not marked "couldn't finish".
- FR-6: A Fixed Target movement served as Practice uses the level target.
- FR-7: Held warm-up, cooldown and Recovery stretches are 30 s (per side when one-sided) at every level; rep-based bookend moves are unchanged.
- FR-8: Criteria and range copy for the two movements speaks of the target.
- FR-9: The Coach starts the two movements at the level target.
- FR-10: Logs are never rewritten; cleared rungs stay cleared.

## Non-Goals

- No change to any other movement's Earned Reps, ranges or advancement.
- No change to Dead Bug's audience or the beginner core ladder.
- No change to sets per station (4), rest rules or session lengths.
- No conversion of rep-based bookend moves to timed holds.
- No new user setting for targets.
- No change to Custom Workout editing freedom or to the rule that Custom Workouts never advance progression.

## Design Considerations

- An advanced plank station is a 3:00 hold inside each circuit round; the existing compact ring, **+ More time** and hands-free flow apply unchanged.
- Shorter bookends free a few minutes on long sessions; the fit spends them as it does today.

## Technical Considerations

- Keep `RepGrammar` the one owner of numbers; avoid special-casing movement ids in `SessionAssembly` or `AdaptiveOverload`.
- `earnedReps` / `earnedDurationSeconds` keep being written (set to the target) so history, Return and Coach readers do not need a second path.
- Paused-session snapshots must still decode and play their saved values.
- Catalog validation tests must cover the new field.

## Success Metrics

- Every assembled session at every length and level lands within the existing length tolerance.
- No regression in the engine, player or Coach test suites.
- Fixed Target movements show the level numbers in 100% of assembled sessions outside short-session cuts and Returns.

## Open Questions

- None from the interview. The implementer reports, before building on it, any surface found to show ranges or criteria that this PRD does not name.
