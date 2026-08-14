# CONTEXT - Rep Today domain glossary

The resolved vocabulary of the Rep Today domain: the small set of terms whose meaning is load-bearing across the product, the engine, and the docs.
This is a glossary of settled terms, not a spec - each entry points to the authoritative code or doc rather than duplicating its detail.
`AGENTS.md` is the working guide for contributors; the dated PRDs under `.claude/agent/tasks/` are the strategic source of truth; decisions that changed a term's meaning are recorded as ADRs under `docs/adr/`.

## Pillar

The training families a session draws from - `strength`, `mobility`, `primal` (`Models/Enums.swift`, `Pillar`).

**Strength is the primary pillar of every session.**
Single-focus, blend, cold-start, and Return sessions all lead with strength; mobility is **supporting** - the structural warm-up and the cooldown bookends only, never a training block and never the lead.
This is the strength-primary decision that superseded the earlier co-primary framing (see [ADR-0001](docs/adr/0001-strength-primary-sessions.md)); it is captain-accepted, and the term "co-primary" is retired for describing current behavior.
Since **US-M01** the strength lead is *structural*: the engine builds every session as Warm-Up -> Strength (-> Primal at 41-60 min) -> Cooldown, with no strength-vs-mobility split machinery. `sitsLong` (desk-worker signal) is currently inert (US-M03 will repurpose it to bias bookend selection).
Since **US-M02** the bookends are *pattern-matched*: each mobility movement carries a `complements: [MovementPattern]` tag (`Exercises.json`), and the warm-up and cooldown **lead** with a stretch complementing the day's lead strength pattern, then fill with the existing staleness / no-repeat ordering - a preference, never a filter (`SessionAssembly.leadingComplement`); the general pool is the fallback so a bookend is never starved.

`primal` (bear crawl, crab walk, ground-to-standing) is a first-class pillar: it earns its own dedicated block in extended (41-60 min) sessions and folds into the strength family in shorter blends (US-E02).
The engine mechanics live in `Services/Engine/SessionAssembly.swift` (the block builder); `AGENTS.md` section 2 ("Pillar balance") is the working description.

## Movement Practice (retired)

The mobility **training** block that once sat between the warm-up and cooldown - a real block of mobility work (deep squat holds, hip work, thoracic rotations), distinct from the structural warm-up.
**Retired by US-M01** (2026-08-13): it is no longer emitted at any length, its split machinery (`PillarBalance`/`PillarWeights`) is removed, and the training minutes it held were reallocated to strength.
Mobility now survives only as the warm-up and cooldown bookends. The term is kept here only so a future contributor recognizes it as a removed concept, not a live block (see [ADR-0001](docs/adr/0001-strength-primary-sessions.md) and the "Movement Practice removal" follow-on in `.claude/agent/tasks/prd-strength-primary-sessions_260812.md`).

## discipline-first

The product's positioning: the promise is **daily consistency** - showing up - independent of whether a given day's work is strength or mobility.
Discipline-first is a framing about the user's behavior and identity ("you're someone who moves"), not a claim about the session's pillar mix.
It coexists with the strength-primary engine: the engine leads with strength while the positioning stays discipline-first, and every user starts in the **Discipline Phase** and earns the **Strength Phase** through sustained consistency plus demonstrated competence (`Services/Consistency/`, `PhaseEvaluator`; `AGENTS.md` "Consistency & Phase").
No gamification (no XP, levels, badges, or a streak to break); a miss dents but never zeroes the Consistency Score.
