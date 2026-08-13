# CONTEXT - Rep Today domain glossary

The resolved vocabulary of the Rep Today domain: the small set of terms whose meaning is load-bearing across the product, the engine, and the docs.
This is a glossary of settled terms, not a spec - each entry points to the authoritative code or doc rather than duplicating its detail.
`AGENTS.md` is the working guide for contributors; the dated PRDs under `.claude/agent/tasks/` are the strategic source of truth; decisions that changed a term's meaning are recorded as ADRs under `docs/adr/`.

## Pillar

The training families a session draws from - `strength`, `mobility`, `primal` (`Models/Enums.swift`, `Pillar`).

**Strength is the primary pillar of every session.**
Single-focus, blend, cold-start, and Return sessions all lead with strength; mobility is **supporting** - the structural warm-up, the cooldown, and a minority accessory block (Movement Practice), never the lead.
This is the strength-primary decision that superseded the earlier co-primary framing (see [ADR-0001](docs/adr/0001-strength-primary-sessions.md)); it is captain-accepted, and the term "co-primary" is retired for describing current behavior.
`sitsLong` (desk-worker signal) now only modulates the *size* of the mobility accessory, never which pillar leads.

`primal` (bear crawl, crab walk, ground-to-standing) is a first-class pillar: it earns its own dedicated block in extended (41-60 min) sessions and folds into the strength family in shorter blends (US-E02).
The engine mechanics live in `Services/Engine/PillarBalance.swift`; `AGENTS.md` section 2 ("Pillar balance") is the working description.

## Movement Practice

The mobility **training** block - a real block of mobility work (deep squat holds, hip work, thoracic rotations), distinct from the structural warm-up that opens every session.
Under the strength-primary model it is a one-set-per-exercise minority accessory that grows a longer session by adding distinct movement *types* (capped at `maxMobilityTrainingExercises`), not by adding sets (`Services/Engine/SessionAssembly.swift`; `AGENTS.md` section 7).
"Movement Practice is not the warm-up" remains true; "Movement Practice is co-primary with strength" does not.

## discipline-first

The product's positioning: the promise is **daily consistency** - showing up - independent of whether a given day's work is strength or mobility.
Discipline-first is a framing about the user's behavior and identity ("you're someone who moves"), not a claim about the session's pillar mix.
It coexists with the strength-primary engine: the engine leads with strength while the positioning stays discipline-first, and every user starts in the **Discipline Phase** and earns the **Strength Phase** through sustained consistency plus demonstrated competence (`Services/Consistency/`, `PhaseEvaluator`; `AGENTS.md` "Consistency & Phase").
No gamification (no XP, levels, badges, or a streak to break); a miss dents but never zeroes the Consistency Score.
