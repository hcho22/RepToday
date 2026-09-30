# US-SP04 - Phase-progress surface (the visible climb)

The free, read-only surface that shows a Discipline-Phase user how close they are to earning the Strength Phase, from real logs, using the exact same logic `PhaseEvaluator` gates on.

## Where it lives

The Progress tab (`Views/Progress/ProgressTabView.swift`), a `PhaseProgressCard` shown just under the consistency headline - free, never premium-gated - when history is present and the user is still climbing (`phase == .discipline` and the earn signals are not both met).
Once the phase is earned, US-SP06's graduation moment and the strength surfaces take over.

## One source of truth (no re-derivation)

`PhaseEvaluator.evaluate(...)` is refactored to be *literally* `PhaseEvaluator.progress(...).hasEarnedStrength`, and the surface renders that same `PhaseProgress` value.
The number the card shows and the decision the gate makes are one computation, so they cannot drift.
`PhaseProgress` exposes the component signals the gate is built from:

- **Consistency** - `weeksSustained` of `requiredWeeks` (the active-week span toward the ~8-week window), plus `currentScore` vs `scoreThreshold` (the 80+ bar the recency-weighted Consistency Score must hold).
- **Competence** - `foundations`, using the counting lines and clearing rule defined in [Foundation](../../../CONTEXT.md#foundation), with each line evaluated by the gate's own `AdvancementCriteria` check.

## Validation Test (PRD)

- **Setup:** a synthetic user with 5 sustained weeks, Push and Pull cleared, and only the Squat side of Legs cleared (Hinge and Core not). This fixture reflects [ADR-0006](../../../docs/adr/0006-foundations-push-pull-legs-core.md).
- **Expected:** shows "5 of 8 weeks" and exactly 2 of 4 foundations cleared, matching what `PhaseEvaluator` would gate on; the user is *not* shown as earned.

Proven three ways:

- `PhaseEvaluatorTests.testProgressReportsFiveOfEightWeeksAndTwoOfFourFoundations` - the pure component values and the gate agree (`hasEarnedStrength == false`, `evaluate == .discipline`).
- `PhaseEvaluatorTests.testProgressEarnedFlagMatchesGateAcrossScenarios` - `progress.hasEarnedStrength == (evaluate == .strength)` across every phase scenario, so the surface can never disagree with the gate.
- `ProgressViewModelTests.testLoadPopulatesPhaseProgressMatchingTheGate` - the view model loads the same numbers over the real catalog and agrees with `PhaseEvaluatorService.phase`.

## Rendered evidence

`PhaseProgressEvidenceTests.testPhaseProgressCardShowsFiveOfEightAndTwoOfFour` hosts the production `ProgressTabView` over this validation history and asserts the live accessibility tree carries "5 of 8 weeks", "2 of 4 cleared", "Push, cleared", "Pull, cleared", "Legs, 1 of 2 sides cleared", "Legs, squat side, cleared", "Legs, hinge side, in progress", and "Core, in progress", then captures the screen.

![Phase-progress climb card](01-phase-progress-climb.png)

The card reads: **Your climb to Strength** - "Steady practice 5 of 8 weeks" with "Consistency 100, holding above 80", and **Foundations 2 of 4 cleared** with Push/Pull checked (Cleared), Legs at "1 of 2" (Squat side checked, Hinge side in progress), and Core in progress.
Copy is identity-framed ("Strength is earned, not chosen"), never loss-framed; no XP, level, or streak.

Regenerate the PNG with `REPTODAY_WRITE_EVIDENCE=1` on the `RepToday` scheme (keep the filename).
