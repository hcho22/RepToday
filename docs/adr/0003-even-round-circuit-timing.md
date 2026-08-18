# ADR-0003: Even-round circuit timing (round-rest as the fit lever)

- Status: Accepted (2026-08-14) and **implemented** 2026-08-14 in `SessionAssembly` (US-CC03/US-CC04, engine-only). The per-exercise set-adjust lever is retired for training blocks: a training block now carries one uniform round count, and the timing fit lands the ±60s target by tuning a bounded between-round rest (`minRoundRestSeconds`...`maxRoundRestSeconds`), falling back to whole rounds / whole exercises - always uniformly. The player-side rendering of rounds (US-CC02) and applying a mid-circuit skip/swap across all remaining rounds (US-CC07) have since landed - the latter needed no engine change, since the substitute already keeps the block's uniform round count. The generous runtime pace (US-CC08) has also landed and re-prices the `workPerSet` term this formula sums (see Consequences below); the levers and the uniformity rule are unchanged.
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

- The planned wall-clock formula changed to `Σ(rounds × Σ exercise work-window) + between-station transitions + (rounds - 1) × round-rest` per training block (plus the linear bookends and one between-station transition between adjacent blocks). As built: `SessionAssembly.blockSeconds` owns the round-aware per-block formula (over both `PlannedBlock` mid-assembly and a materialized `WorkoutBlock`), `plannedSeconds`/`totalSeconds` sum it plus between-block transitions, and the fit's candidate generator replaced the per-item `.addSet`/`.removeSet` moves with a single `setRoundsAndRest` move (round count and in-band rest tuned together so the greedy can trade a round for rest in one step) alongside whole-exercise promote/drop. `PlannedItem` gained a mutable `restSeconds` (the between-round rest) and dropped its old linear `seconds`. Determinism and `asOf`-purity are preserved (verified across 5/10/15/20/30/45/60 for every fitness level: uniform per-block round count, in-band rest, and landing within ±60s).
- Coupled with the generous runtime pace (US-CC08, where the on-screen window must equal the planned work-seconds), generous windows fit fewer rounds per session - an accepted trade-off, and as built (`workPaceGenerosityFactor = 1.25`) a measured one: 15/20 min 6 -> 5 rounds, 30 min 7 -> 6, 5 and 60 min unchanged. At 45 minutes the cost lands on **stations** rather than rounds - the strength block goes 7 rounds x 5 stations to 8 x 4, i.e. 4 distinct movements instead of 5 - because the block is pinned at the `maxTrainingSets` rail, where dropping a station is the fit's only remaining lever. Worst |fit error| stays 1s against the ±60s tolerance and no length loses its last round; a station floor or a higher rail is a separate follow-on. **Superseded by [ADR-0004](0004-round-cap-wide-circuit.md) (US-RC01, 2026-08-18):** the `maxTrainingSets` rail this consequence rests on was capped at 4 and the "add more rounds" lever replaced with "add more stations," so a long session now fills wider rather than dropping a station at the old 8-round rail - this "8 rounds x 4 stations" outcome no longer holds. The even-round uniformity and +/-60s tolerance recorded here are unchanged; only the round rail moved.
- This is hard to reverse once the player renders rounds and users expect even circuits, and it is surprising to a reader who finds the old per-item set-adjust lever gone from the fit - which is why it is recorded here. The +/-60s tolerance remains the hard constraint the new lever is verified against.
