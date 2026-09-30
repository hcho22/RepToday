# ADR-0006: Foundations are Push, Pull, Legs, Core

- Status: Accepted
- Date: 2026-09-30
- Story: captain request, "update the foundation for reptoday to Push, Pull, Legs, and Core"
- Supersedes / amends: the four-foundation gate of US-H02 (push / squat / hinge / core); the surfaces built on it (US-SP04, US-SP05, US-AN01, US-AN02, the US-AC07 emphasis vocabulary)

## Context

The Strength Phase is earned through consistency plus competence.
Competence meant clearing the entry rung of one chain in each of four movement patterns: push, squat, hinge and core.
That list existed in four places (`PhaseEvaluator`, `ProgressAnalytics`, `CoachIntentMapper`, `CoachAnalyticsInsight`), and every user-facing surface (the Progress tab's climb card, "where you stand", progression map and dated climb, the premium strength journey, the Coach's insights and requestable words) repeated it.
Pull already existed as a strength pattern used in sessions, with a postural chain and a horizontal chain, but it never counted toward anything the user could clear.
The captain wants the foundations to read the way people talk about strength: Push, Pull, Legs, Core.

## Decision

**The four foundations are Push, Pull, Legs and Core, defined once in `StrengthFoundation` and read by the gate and every surface.**

1. **Legs needs both sides.**
   Legs groups the squat and hinge patterns as a Squat side and a Hinge side, and is cleared only when both are.
   Squat and hinge stay separate movement patterns in the engine.
   A user who only squats has not shown they can hinge, and the Strength Phase lifts the difficulty cap for everything, so it should not open on quads alone.
   Collapsing Legs to "either side" would also have quietly loosened the gate compared with today, where both squat and hinge are required.

2. **Only the horizontal pull chain counts.**
   Pull is cleared by the entry rung of the horizontal chain (Wall Scapular Pull, 3x12 clean reps).
   The postural chain (Superman Hold, Reverse Snow Angel, Prone Y-T-W Raises) stays in sessions as accessory and prehab work but never clears Pull.
   Its entry rung is a prone hold on the floor that says little about pulling strength, and counting it would let the easiest movement in the catalog stand in for the foundation.
   The rule is data on the foundation line (a set of counting chain ids), so Pull's ladder, current movement and dated climb on the Progress tab and in the premium analytics are always the horizontal chain.

3. **Pull has no Strength-Phase top rung yet.**
   Pull's ladder ends at Single-Arm Supine Floor Row, with no locked Strength-Phase rung.
   A meaningful advanced pull is a pull-up or a rowing variation that needs a bar, rings or a load, and the zero-equipment rule stays intact for now.
   A Pull top rung waits for the planned Phase 2 equipment work.
   Copy that promised a locked Strength-Phase skill at the top of every foundation was reworded so it stays true (the progression map's intro and the graduation reveal).

4. **Progress is recalculated, with a one-time note, not grandfathered.**
   Foundation progress is recomputed from the full workout history under the new rules.
   A user who had cleared squat and hinge keeps Legs, a user who cleared only squat now sees Legs at "1 of 2", and nobody has Pull cleared until they clear its horizontal chain, so some Discipline users see their count drop.
   Grandfathering would mean storing a per-user "cleared under the old rules" record, a second definition of clearing that the gate and the surfaces would both have to honour forever.
   Recalculating keeps one definition, and it is safe because an earned Strength Phase is never revoked: the ratchet lives in the persisted `User.phase` and is untouched, so the change can only affect users who have not yet earned Strength.
   A one-time note on the Progress tab's climb card says the foundations are now Push, Pull, Legs, Core and where the user stands.
   It uses the same persisted one-shot pattern as the other first-run notes (`AppState.hasSeenFoundationsUpdateNote`) and is shown only to an install that predates the change and has trained a foundation.
   The note is intentionally limited to Discipline users who still have that climb card.
   Strength users have no climb card, keep their ratcheted phase and historical progression, and see the recalculated Push, Pull, Legs and Core foundations directly on the progression map instead of receiving the note.
   It never reaches a brand-new user: finishing onboarding on this build marks it seen, which also covers someone who deletes their account and starts over.

5. **One definition, five lines.**
   The Progress tab shows Legs as one foundation with a Squat side and a Hinge side, each with its own tick, current movement, ladder and dated climb.
   The Legs header reads Cleared only when both sides are, and "1 of 2" before that; the headline stays "N of 4 foundations cleared" in the order Push, Pull, Legs, Core.
   The premium strength journey and the Coach's analytics insights track the same five lines, and an insight names the side ("the hinge side of your legs has been flat for 3 weeks") and offers to emphasize exactly that pattern.
   The Coach recognizes Pull words (pull, row, back, upper back) and "legs" as a request that nudges squat and hinge together; the existing squat and hinge words keep working for finer control through the existing emphasis control, so the coach write path and its safety rules (ADR-0005) are unchanged.

## Consequences

- The gate and every surface read one definition, so they cannot drift: adding or changing a foundation is a change to `StrengthFoundation` and nothing else.
- `MovementPattern`, the exercise catalog, session assembly and the zero-equipment rule are unchanged.
- Some Discipline users' foundation counts drop on update (Pull is new and Legs now needs both sides), and it can take them longer to earn Strength than it would have.
  The note explains it, and the recalculation is honest: it reflects what the user has actually demonstrated on the ladders that now count.
- A user who only trained the postural pull chain sees Pull as "not started" on the Progress tab, even though those movements are in their sessions.
  This is the accepted cost of postural work not counting.
- The Coach's context bundle now carries a fifth chain summary, Pull, and its strength-journey summaries can name Pull; the wire is otherwise unchanged and the proxy needs no change.
- Pull has no Strength-Phase rung, so the graduation reveal names only the Push, Legs and Core ladders as gaining Strength-Phase movements.

## Alternatives considered

- **Legs as either side.** Rejected: it loosens the gate relative to today and lets a lopsided user earn the phase.
- **Postural pull counts too, or counts alongside horizontal.** Rejected: its entry rung is too easy a stand-in for pulling strength.
- **A Strength-Phase Pull rung now.** Rejected: it needs equipment, which is a separate planned piece of work.
- **Grandfather existing users' cleared foundations.** Rejected: a second, per-user definition of "cleared" to maintain forever, and unnecessary because the earned phase already ratchets.
- **Rename the patterns themselves (merge squat and hinge into a legs pattern).** Rejected: squat and hinge are separate staleness buckets in the engine and merging them would change session assembly, variety and the catalog for a change that is about what the user clears.
