# ADR-0002: Per-interval pacer clock (partial reversal of US-O03's hidden clock)

- Status: Accepted (decision made 2026-08-14); **fully implemented**. US-CC01 landed the first visible auto-advancing per-interval countdown - the rep-based strength/primal **work window** (`ActiveSessionViewModel.workWindow`), counting the set's planned work-seconds down and flowing on with no tap - alongside US-O03's tap-started Hold Timer. Both of this decision's pacer intervals exist: US-CC04 landed the engine's bounded **between-round rest**, and US-CC02 routes both circuit gaps (the between-station transition and that between-round rest) through the US-K02 rest overlay, which counts down - so the between-round rest is a visible per-interval pacer in the shipped player. US-CC14 has now landed the accessibility hardening the visible clock demanded (the shared `ActiveSessionView.CountdownRing` carries `.accessibilityAddTraits(.updatesFrequently)` so VoiceOver polls on demand rather than announcing every tick, and its sweep is dropped under Reduce Motion) plus a first-class **+ More time** on both auto-advancing countdowns, completing the continuous-circuit PRD, per `.claude/agent/tasks/prd-continuous-circuit-sessions_260814.md`; the shipped player still shows no session-wide clock.
- Date: 2026-08-14
- Deciders: captain, via the "Continuous-Circuit Sessions" decision session (2026-08-14)
- Relates to: [ADR-0003](0003-even-round-circuit-timing.md) (the timing model the pacer clock counts against); the domain term `CONTEXT.md` -> "Continuous Circuit (planned)".

## Context

US-O03 made a deliberate choice: the active-session player shows **no ticking clock**.
Elapsed time is derived from an injected clock but is **not** surfaced while the session runs, because "a visible ticking total turns the session into something to get through" - it only appears afterward as the completion summary's duration (see `ActiveSessionViewModel.elapsed(asOf:)` and its doc comment).
The only in-session countdown US-O03 allowed was the Hold Timer for a timed stretch, tap-started by the user.

The continuous-circuit feature (the planned player) needs the opposite for the *thing on screen right now*: a work window has to count down visibly so the user knows when it will auto-advance, and a between-round rest has to count down so they know when the next round starts.
That is a genuine tension with US-O03's "no visible timer" intent, so it is recorded here rather than left as an unexplained flip a future reader would trip over.

## Decision

**Introduce a per-interval pacer clock, and keep the total session clock hidden.**

The distinction is the whole decision, and it is what makes this a *refinement* of US-O03 rather than a repudiation of it:

- A **per-interval countdown** (the current work window's remaining seconds; the current round-rest's remaining seconds) **is shown**, because it is a pacer - it tells the user how to move *now* and when the hands-free flow will carry them onward. This is the natural extension of US-O03's already-accepted Hold Timer countdown to every interval, now auto-started rather than tap-started.
- The **total elapsed session time stays hidden** (US-O03's actual concern), because a running grand total is the thing that becomes a session-to-endure. `elapsed(asOf:)` remains internal, surfaced only in the completion summary.

So US-O03's principle survives intact ("don't make the whole session a countdown to grind against"); what changes is that a *local* pacer is not that grand total and is now shown to enable the hands-free experience.

## Consequences / Trade-offs

- The session-clock-visibility question (should any subtle *overall* progress affordance exist alongside the per-interval ring and "Round N of M"?) is left open in the PRD; the standing default is to keep the total hidden. This ADR's rationale is exactly why: a per-interval pacer is admissible where a grind-against-total clock is not.
- A visible per-interval countdown raises the accessibility bar: the timer must not spam VoiceOver or steal focus, and must degrade under Reduce Motion (US-CC14). Those requirements exist *because* we chose to show a clock at all.
- This is hard to reverse in user-experience terms once shipped (users will pace to the ring), and it visibly contradicts the US-O03 code comment that says the clock is deliberately not shown - which is precisely why it is recorded here, so the contradiction reads as a deliberate, scoped decision rather than a regression of US-O03.
