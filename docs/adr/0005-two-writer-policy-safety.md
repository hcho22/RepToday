# ADR-0005: Two-writer `SessionPolicy` safety - the coach overlays, the engine stays sovereign

- Status: Accepted
- Date: 2026-08-26
- Story: US-AC07 (Phase-2 Strength Coach, Slice 3)
- Supersedes / amends: none (extends the US-AC05/US-AC06 preference-lever work)

## Context

`SessionPolicy` is the one per-user program the deterministic engine reads and the writers write.
Until now it had exactly one writer, the deterministic Programmer (`DeterministicSessionPolicyService`), which owns the safety moves: the plateau **de-load** (disengagement eases `progressionRate` and narrows `varietyWindow`), the **Re-entry Ramp** (`reentry`), and the **cold-start contract** (`coldStartContract`).
The policy is versioned **last-writer-wins**: whoever writes last, with the highest `version`, is in force on the next open.

US-AC07 adds a **second writer** - the premium AI coach - so a user can say "focus my push" or "take it a bit easier" and have their program adjust.
The danger the PRD flags (FR-11, "Two writers, one policy"): a naive last-writer-wins coach write could **clobber a deterministic safety back-off**.
Concretely, if the Programmer de-loads a disengaging user (eases pace, narrows variety) and the coach then writes a policy built from a *stale* snapshot, the coach's write would silently undo the de-load - making the session harder for a user the engine had just decided to protect.
The PRD left the merge/precedence data model open (its Open Questions: "disjoint fields vs. a safety-sovereign overlay").

## Decision

**The coach write is a safety-sovereign overlay onto the freshest in-force policy, and every lever the coach can touch is either disjoint from the safety moves or only-downward. Safety > preference, structurally.**

Three parts:

1. **Preference-only, closed proposal.** A coach request is converted to a `CoachPolicyProposal` (`Models/CoachPolicyProposal.swift`) that can name *only* the three preference levers - `patternEmphasis`, an eased `progressionRate`, a narrowed `varietyWindow` - and nothing else. The safety fields (`coldStartContract`, `reentry`, `pillarWeighting`, and the injuries / difficulty-cap / phase-gate / zero-equipment filters, which live on `User`/`ExercisePoolFilter`, not on `SessionPolicy`) are **not expressible** in the proposal type. "The coach writes only preference levers" is a property of the data model, not a runtime check.

2. **Overlay onto the current policy, re-read at write time.** `CoachSessionPolicyService.applyProposal` reads the *freshest* persisted policy from the shared `SessionPolicyStore` and applies the proposal *onto it* (`SessionPolicy.applyingCoachProposal`), rather than building a fresh policy or replacing unmentioned levers. A de-load that landed since the user last spoke to the coach is already in that policy and is carried through untouched.

3. **Every coach lever is disjoint or only-downward.**
   - `patternEmphasis` is **disjoint**: no deterministic safety move reads or writes it, so a clamped overlay can never collide with one.
   - `progressionRate` is **only-downward**, via the US-AC06 seam `easingProgressionRate(towardCoachProposed:)` = `min(clampedProgressionRate(proposed), inForceRate)`. A coach can lower pace but never raise it above the in-force (always ≤ engine-earned) value.
   - `varietyWindow` is **only-downward (narrow-only)**, via the new sibling seam `easingVarietyWindow(towardCoachProposed:)` = `min(clampedVarietyWindow(proposed), inForceWindow)`. Narrowing the no-repeat window is the "reduce friction / more familiar" direction the disengagement de-load itself narrows toward; widening it (fresher, less-repeated movement) is *added* friction and stays the engine's alone, exactly as upward pace does.

Because each lever is disjoint or only-downward, a coach write applied onto the freshest policy **cannot undo a de-load / Re-entry / cold-start** - it either doesn't touch the safety-moved lever or can only push it further in the protective direction. Every proposed value is **clamped to the engine's rails first**, so an out-of-range or hostile proposal (e.g. from a compromised proxy) is pinned to a safe, order-preserving value and never acts as a filter.

The write is tagged `updatedBy == .llm`, versioned forward, stamped with an injected `asOf` (never the wall clock), and noted honestly (`PolicyNote.coachTemplated`, which may only name a lever that actually moved). It is reversible: a later opposite/neutral coach request, or the deterministic Programmer, can move the lever back.

**The intent source is not trusted for safety.** Whatever produces the proposal - today the on-device `CoachIntentMapper`, tomorrow a proxy-emitted structured action - only ever *proposes*. The on-device write path validates, clamps, and direction-checks regardless, so a mis-recognition or a hostile proposal can only ever yield a bounded, safe, reversible nudge.

## Consequences

- A coach write and a deterministic de-load can arrive in either order and both survive: the de-load's eased pace / narrowed window are preserved by a later coach write (disjoint or only-downward), and the coach's disjoint emphasis is preserved by a later de-load (which copies the policy and moves only its own two levers). Proven end-to-end in `CoachPolicyWritePolicyTests` against the two real writers and a shared store.
- The coach cannot make a session harder, add novelty-friction, remove a movement, or touch a safety filter - the US-AC07 failure indicators are impossible by construction, not merely untested.
- Narrow-only `varietyWindow` means an "I want more variety / I'm bored" request is served by **de-emphasizing** the stale pattern (a safe, lateral emphasis move), not by widening the no-repeat window - the coach shifts focus and eases, but never dials challenge up. This mirrors US-AC06's thesis (the coach eases; only the engine advances) and is a deliberate, accepted limitation.
- The `varietyWindow` rail (`min`/`max`/`clampedVarietyWindow`) is now centralized on `SessionPolicy` and aliased by `PlateauDiagnosis`, exactly as US-AC06 centralized the `progressionRate` rail - so the deterministic floor/ceiling and the coach's easing gate share one definition and cannot drift.
- No new persisted field and no schema change: `applyingCoachProposal` derives the in-force ceiling at the write site (the in-force rate is always ≤ engine-earned because only the engine advances), so no separate "engine-earned" field is stored. Round-trip safety is unchanged.

## Alternatives considered

- **Disjoint fields (a separate coach-owned lever set the engine never writes).** Rejected: `varietyWindow` and `progressionRate` are genuinely shared - both writers have a legitimate reason to move them - so splitting them would either duplicate levers or forbid the coach from easing at all. The only-downward rule lets both writers share a lever safely.
- **Last-writer-wins with a stored baseline / timestamp comparison.** Rejected: it requires persisting extra state to detect "a safety move is in force," is fragile across reads, and still allows a clobber in the window between read and write. The overlay + only-downward rule needs no baseline and is safe by construction.
- **Trusting a proxy-returned policy.** Rejected outright: on-device enforcement is sovereign regardless of what the proxy/LLM says; the proxy can only ever propose a bounded change.
