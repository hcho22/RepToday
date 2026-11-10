# ADR-0012: Push/Pull/Legs Training Day rotation with an automatic Rest Day

- Status: Accepted (decided 2026-11-10); not yet implemented (M1, `US-TD04`, `US-TD05`).
- Date: 2026-11-10
- Deciders: captain, via the Push/Pull/Legs design grill (2026-11-09 to 2026-11-10)
- Spec: `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md`
- Supersedes: staleness-led lead-pattern selection (`MovementPatternFocus`) as the way a session's strength work is chosen.
- Relates to: [ADR-0006](0006-foundations-push-pull-legs-core.md) (foundations stay the Strength-Phase gate, not a schedule); `CONTEXT.md` -> "Training Day", "Rotation / Cycle", "Rest Day", "Core Sprinkle", "Outside Activity".

## Context

Today every session leads with the stalest movement pattern and fills the rest of its time with the other patterns, so a 45 or 60 minute session works nearly every pattern every day.
Users find long sessions crowded and the app has no notion of a split or a day off.

## Decision

**Sessions are Training Days that rotate Push -> Pull -> Legs, with an automatic Rest Day after each completed Cycle.**

- A Push Day trains push only, a Pull Day pull only, a Legs Day squat and hinge only; each adds one Core Sprinkle plus the warm-up and cooldown bookends. Groups never mix.
- The Rotation advances only when a Training Day session is completed, so a missed day never skips a group. The order never shuffles; Cycle-to-Cycle variety comes from the Core Sprinkle rotating across core ladders.
- A Rest Day follows every completed Cycle. Any session-free day after Legs satisfies it. On a Rest Day, Today offers an optional mobility-only Recovery flow and "Train anyway", which starts the next group and forfeits the rest. Rest never lowers the Consistency Score.
- An Outside Activity (and a Coach Custom Workout) gives the group it worked at least one day off: that group swaps behind the next one, or, if it is the last group left in the Cycle, the Rest Day comes early. It never completes a group.
- The Rotation is derived purely from the workout log and logged activities as of a given date, keeping the engine deterministic and `asOf`-pure.

## Considered Options

- Calendar-pinned rotation - rejected: a missed day would silently drop a group.
- Shuffling the day order each Cycle - rejected: predictability matters more than novelty of order.
- A weekday picker for rest - rejected for simplicity; rest is automatic per Cycle.

## Consequences

- Existing users start at Push after the update (old mixed sessions carry no Training Day).
- The weekly Consistency goal of 3 stays below the ~5 sessions a week the Rotation allows, so rest cannot dent the score.
- The coach's `patternEmphasis` lever becomes mostly inert (it can only reorder within a day); see ADR-0005.
