# Staple movements - validation (ADR-0007)

Decision: [ADR-0007](../../../docs/adr/0007-staple-movements-for-beginner-and-intermediate.md).
Scope: on-device engine, catalog and Progress/Ready surfaces, validated in the iOS Simulator only.
Physical-device behavior is untested.

## What the evidence shows

- `01-ready-screen-classics-note.png` - the Ready Screen of an install that predates the change, an intermediate user in the Discipline Phase.
  The one-time note reads "Your sessions now focus on the classics. More movements unlock when you earn the Strength Phase." and the session beneath it is all staples (Downward Dog, Standing Forward Fold, Wall Push-Up, Wall Sit, Glute Bridge, Cobra Stretch).
- `02-beginner-progression-map.png` - a beginner's Progress tab.
  Each ladder marks the staples they can reach and locks every rung beyond them with "Earn the Strength Phase to unlock" (Diamond and Archer Push-Up, Sumo Squat and beyond, Marching Glute Bridge and beyond, Dead Bug, Supine Floor Row).
  The squat ladder reads Wall Sit then Bodyweight Squat, and no withdrawn crawl is named.

Both were captured by `StapleMovementsEvidenceTests` with `REPTODAY_WRITE_EVIDENCE=1`; the tests assert the same marks on the live accessibility tree before capturing.

## Assertions behind them

`StapleMovementsTests` pins, over the real catalog:

- the pool for each fitness level and phase equals the decided lists exactly (beginner 16 training movements + 16 stretches, intermediate 25 + 16, advanced 39 + 26, Strength Phase everything offered);
- Gorilla Walk, Lizard Crawl and Underswitch never appear in a session (5-60 min, every level and phase), a swap, the progression map, chain positions, journey, bests or the Coach context bundle, are kept recoverable, and their past logs still count in history totals;
- every foundation clears from a beginner staple and a beginner earns the Strength Phase from staples alone;
- sessions at 5/10/15/20/30/45/60 min fit +/-60 s, stay even and inside 2-4 rounds for all levels, including a beginner's 45/60 min session with a Bear-Crawl-only primal block;
- every strength pattern keeps at least two staple stretches;
- users on Cossack Squat, Sumo Squat, Dead Bug and Gorilla Walk are served the closest rung they get, history is unchanged and cleared foundations stay cleared;
- the note's eligibility and one-shot flag cover an existing install, a brand-new install, advanced and Strength-Phase users.

## Known limits

- A paused session written before this change that already contains a withdrawn movement still resumes with it.
- A beginner or intermediate user whose only history on a line is on a chain they no longer get anything from sees that line as not started on Progress; their cleared foundation stays cleared.
- The 30-minute blend lands up to 24 s off target for intermediate and advanced users (it was within 8 s), inside the +/-60 s gate.
