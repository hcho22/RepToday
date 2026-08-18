# ADR-0004: Round cap and wide circuits (cap rounds at 2-4, fill long sessions wider)

- Status: Accepted and implemented (2026-08-18, in US-RC01, engine-only, `Services/Engine/`).
- Date: 2026-08-18
- Deciders: captain, via the "Round Cap and Wide Circuits" design grill (`.claude/agent/tasks/prd-round-cap-wide-circuits.md`, `US-RC##`)
- Supersedes: [ADR-0003](0003-even-round-circuit-timing.md)'s 45-minute "8 rounds x 4 stations" consequence - the round rail that ADR-0003 pinned at `maxTrainingSets` is what this decision retired (see Consequences).
- Relates to: [ADR-0003](0003-even-round-circuit-timing.md) (the even-round timing model this caps); the domain term `CONTEXT.md` -> "Wide Circuit".

## Context

Under ADR-0003 a training block is a circuit of a **uniform round count**, and the timing fit lands the +/-60s target chiefly by tuning a bounded between-round rest, falling back to adding or dropping whole rounds.
That round rail ran to `maxTrainingSets = 8` (`minTrainingSets = 1`), so a long session filled itself by going **deeper**: a 60-minute strength block presented each of ~4 movements at 7-8 rounds (e.g. `Pike Push-Up 7 x 8`).

That is too much volume per movement, and it reads alarmingly on the plan preview.
It also wastes the catalog: every strength pattern already carries 2-3 progression chains (push has horizontal and vertical; squat has squat and lunge; hinge has bridge and hip; core has plank/stability/hollow; pull has postural/horizontal), and primal has two - yet a session only ever drew the frontier of each pattern's *top* chain, then ground it out over many rounds.

The fix is to bound the round count and fill a longer session by going **wider** - more distinct movements - instead of deeper, drawing the extra movements from each pattern's *further* progression chains as accessories.
This is an engine-only change: the continuous-circuit player (US-CC02) already reads the station count and round count off the block and renders "Round N of M," so a session with more stations and fewer rounds needs no player or UI work.

## Decision

**Cap every training-block exercise at 2-4 rounds, and fill a longer session by promoting further-chain accessories (depth-first) instead of adding rounds.**

- **Round rails `2...4`.** `SessionAssembly.minTrainingSets = 2`, `maxTrainingSets = 4` (was `1...8`). No exercise is ever prescribed more than four times or fewer than two, at any length or fitness level. The even-round uniformity of ADR-0003 is unchanged: every station in a block still shares the block's round count.
- **Second-chain accessories.** For each strength movement pattern, the engine seeds the frontier tier of the pattern's **top-N progression chains** (not just the top-1) into the block reserve: every pattern's primary chain first, then every pattern's further chains as accessories. Each accessory is an honest frontier of its own chain, ranked through the same `ProgressionChainSelection.selectAll` / staleness ordering as any station (`Builder.strengthBlock` over `orderedStrengthPatterns`; the extended-blend dedicated `primalBlock` does the same over its one pattern's two chains).
- **Depth-first fill.** The timing fit takes every active station to the `maxTrainingSets` cap (4) *before* promoting any accessory from the reserve; an accessory is promoted only when four rounds of the current stations still fall short of the request. So short and medium sessions stay clean one-movement-per-pattern circuits, and only long sessions go wide.
- **Accessory joins at the block's round count**, keeping the block internally even (ADR-0003). The reserve-promotion move solves the round count *jointly* with adding the station (`.addReserveWithRounds`) rather than pricing it at whatever round count the round-only lever had already walked to.
- **Same rules as a primary.** An accessory uses the identical progression advancement, `varietyWindow` no-repeat preference, and Adaptive Overload targeting as a primary station - there is no separate accessory code path. Step 5's `selectAll` ranks every chain through one `selectInChain`, and Step 6's `appendTrainingItem` doses every station through one `AdaptiveOverload.target`.
- **Accepted bounded depth mismatch (not gated).** A pattern's second chain can be shallower than the primary the user has maxed, and that gap is deliberately *not* gated. It is **bounded by the difficulty cap** (`ExercisePoolFilter.difficultyCap`: beginner 1-2, intermediate 1-3, advanced 1-5), which clamps both the primary and the accessory to the user's band: for a beginner and an intermediate the maxed mismatch is **zero** (both chains top out at the cap ceiling), and for an advanced discipline-phase user it is at most **one tier** (horizontal push maxes at archer, difficulty 4, one-arm being Strength-phase-gated; vertical push at pike, difficulty 3). And it is **never seeded above an earned tier**: an untouched second chain enters at `selectInChain`'s no-history base tier (order 0), never nudged up to the pattern frontier the user cleared on the other chain.

## Considered Options

- **Keep the `1...8` round rail (fill deeper), just cap the preview label** - rejected: the alarming volume is real, not just a display artifact; 7-8 rounds of one movement is genuinely too much per-movement volume, and relabeling would hide it rather than fix it.
- **Cap rounds but fill with a *back-off* accessory (a lower tier of the same chain)** - rejected: repeating the same chain at an easier tier adds no new training surface and muddies progression tracking. Accessories are always a *different* chain's frontier, so every prescribed movement stays an honest frontier of its own chain.
- **Cap rounds but gate the second-chain difficulty to match the primary** - rejected as unnecessary machinery: the difficulty cap already bounds the mismatch to zero for beginner/intermediate and one tier for advanced, and gating would suppress a legitimately-earned frontier on the second chain to force a symmetry the user does not need.
- **Cap rounds without widening the reserve** - rejected: capping alone would leave a ~30-minute hole in a 60-minute session and miss the +/-60s landing tolerance, which is why US-RC01 landed the cap and the wider accessory pool as one coupled unit.

## Consequences / Trade-offs

- **Supersedes ADR-0003's 45-minute consequence.** ADR-0003 recorded that, pinned at the old `maxTrainingSets` rail, a 45-minute strength block went `7 rounds x 5 stations -> 8 x 4` (dropping a station because adding rounds was the fit's only lever there). With the rail now at 4 that specific outcome no longer applies: a long session adds *stations* rather than rounds, so a 60-minute session presents 6-8 distinct strength movements at <=4 rounds each instead of ~4 movements at 7-8 rounds. ADR-0003's even-round uniformity, its two rest gaps, and the +/-60s tolerance all still hold - this decision caps the round rail ADR-0003 introduced, it does not reopen the timing model.
- **Landing the cap exposed and fixed two latent timing-fit bugs** the round cap made load-bearing (US-RC01, engine-only): whole-station promotion now searches the round count *jointly* with adding the station (`.addReserveWithRounds`) rather than at a stale round count; and `selectAll` ranks every chain by freshness/withheld-status as a sort key rather than an elimination filter, so a pattern's non-frontmost chain no longer vanishes from the reserve because its sibling chain was recently worked.
- Short/medium sessions (5-30 min) are unchanged except for shedding rounds beyond four; the reshaped fill is visible only on long sessions.
- Determinism and `asOf`-purity are preserved; strength still holds the training-time majority, mobility stays bookend-only, and the extended (41-60 min) session still carries a strength-led dedicated primal block.
- Owning code: `SessionAssembly` (the `2...4` round rails, reserve generation, depth-first fit, `blockSeconds`) and `ProgressionChainSelection` (the per-pattern multi-chain frontier via `selectAll`/`selectInChain`).
