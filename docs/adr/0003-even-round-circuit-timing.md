# ADR-0003: Even-round circuit timing (round-rest as the fit lever)

- Status: Accepted (decision made 2026-08-14); **not yet implemented** - to be built per `.claude/agent/tasks/prd-continuous-circuit-sessions_260814.md` (US-CC03/US-CC04). Until those stories land, `SessionAssembly` still sizes sessions by per-exercise set adjustment (uneven counts allowed).
- Date: 2026-08-14
- Deciders: captain, via the "Continuous-Circuit Sessions" decision session (2026-08-14)
- Relates to: [ADR-0002](0002-per-interval-pacer-clock.md) (the pacer clock that counts down these intervals); the domain term `CONTEXT.md` -> "Continuous Circuit (planned)".

## Context

The strength block will be played as circuit rounds - one set of each exercise per round, "Round N of M" (US-CC02).
For rounds to be well-defined, every exercise in a training block must carry the **same** number of sets (= the number of rounds).

But today's engine hits its +/-1 minute landing target the opposite way: `SessionAssembly`'s timing fit adds or drops a set on **individual** exercises (`.addSet`/`.removeSet` per item, within the `minTrainingSets...maxTrainingSets` = 1...8 rails), which routinely produces a block where exercise A has 4 sets and exercise B has 3.
That uneven-count lever is structurally incompatible with even rounds: you cannot rotate A, B, C evenly if A owes one more set than B.
Removing the lever without replacing it would break the +/-60s tolerance the whole engine is measured against.

## Decision

**Force a uniform set count per training block, and make the bounded between-round rest the primary timing-fit lever.**

- Every exercise in a training block gets the **same** set count (the block's round count); the per-exercise set-adjust move is retired for training blocks.
- To still land within `toleranceSeconds` (+/-60s), the fit tunes the **between-round rest** within a bounded band (roughly 30-75s). This is a real, deterministic knob: each second of round-rest moves `(rounds - 1)` seconds of planned wall-clock per block, giving fine-grained control without touching set counts or the capacity-relative per-set target from Step 6.
- Two rest gaps replace the old single between-set rest (US-CC04): a short fixed **between-station transition** (~10-15s, the "next up" beat) inside a round, and the tunable **between-round rest**.
- When the round-rest band alone cannot close the gap (very short or very long requests), the fit may add or drop a **whole round** (uniformly, so the block stays even) or a whole exercise - never an uneven per-exercise count.
- The warm-up and cooldown bookends are unaffected: they remain one set each, non-set-adjustable, flowing linearly.

## Considered Options

- **Keep per-exercise set adjustment, fake even rounds in the UI** - rejected: the player would show "Round 3 of 4" while some exercises silently had no set that round, which is exactly the uneven-count problem surfaced to the user.
- **Fix the set count and land time only by adding/dropping whole exercises** - rejected as too coarse: whole-exercise steps are large (a short session cannot absorb one), so the fit would park minutes away from the request, missing tolerance. Round-rest is the fine-grained lever that keeps the landing tight.

## Consequences / Trade-offs

- The planned wall-clock formula changes to `Σ(rounds × Σ exercise work-window) + between-station transitions + (rounds - 1) × round-rest` per block; `plannedSeconds(of:)`, the `additions`/`removals` candidate generation, and `PlannedItem.seconds` are reworked accordingly. Determinism and `asOf`-purity are preserved.
- Coupled with the generous runtime pace (US-CC08, where the on-screen window must equal the planned work-seconds), generous windows fit slightly fewer rounds per session - an accepted trade-off.
- This is hard to reverse once the player renders rounds and users expect even circuits, and it is surprising to a reader who finds the old per-item set-adjust lever gone from the fit - which is why it is recorded here. The +/-60s tolerance remains the hard constraint the new lever is verified against.
