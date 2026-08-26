# US-SP06 - The graduation moment

The one-time, identity-framed reveal shown on the first app open after the user earns the Strength Phase.
Presentation + one-shot flag only.
No change to the deterministic engine, the timing model, the persistence schema, or any emission site.
The reveal is purely celebratory and never gates the core loop.

## The load-bearing implementation question, resolved

The AC says "on the first app open after `PhaseEvaluator` transitions the user to `.strength`."
Investigation found that `user.phase` is **never advanced to `.strength` in production**: `PhaseServiceProtocol.phase(for:recentLogs:)` had **zero** production callers (it appeared only in the protocol declaration and tests), and every write of `user.phase` sets `.discipline` (onboarding, the sample user).
The engine's `ExercisePoolFilter` reads the persisted `user.phase`, so US-SP01's cap-lift is in fact **currently inert in production** - a separate, pre-existing gap.

Rather than fabricate a persisted transition that cannot happen (or widen scope by wiring `user.phase` persistence, which would change engine behavior), US-SP06 detects the crossing off the **computed earned phase**: the same deterministic `PhaseEvaluatorService.phase(for:recentLogs:)` the gate uses, compared against a persisted, ratcheting one-shot on `AppState`.
This is exactly the "persisted last-seen phase on `AppState` compared against the current earned phase" shape the story brief anticipated, and it needs no engine change.

**The separate gap (`user.phase` never persisted to `.strength`, so US-SP01's cap-lift never engages in a real session) is flagged for a follow-on and is out of US-SP06's scope.**

## What landed

- **The reveal (`Views/Progress/StrengthGraduationRevealView.swift`).** Identity-framed copy: "You've earned the Strength Phase", "You're someone who moves - and it shows." Four honest points - you earned this (weeks of showing up and cleared foundations), harder work is ready when you are, new Strength-Phase skills join the ladder, and see the whole climb on the progression map. Never gamified ("reward"/"unlocked"/"level"/"badge"/"XP") and never loss-framed. `Theme` tokens throughout; `.isModal` card, `accessibilityHidden` scrim, `ScrollView` for Dynamic Type, a single 60pt "Keep climbing" dismiss control.

- **The one-shot flag (`AppState.lastCelebratedPhase`).** A persisted `Phase`, default `.discipline`, in the style of `hasSeenContinuousCircuitExplainer`: read via `hasCelebratedStrengthGraduation`, advanced via `markStrengthGraduationCelebrated()`. It is a **ratchet** - only ever advanced when the reveal is shown, never rewritten to the live earned phase - so a rolling earned phase that later dips back to `.discipline` and re-climbs never re-congratulates. The milestone is celebrated once, ever.

- **The crossing detector (`ViewModels/StrengthGraduationViewModel.swift`).** Computes the earned phase over the user's full history through the real evaluator and reports whether it is `.strength`. Best-effort: a missing user or a failed read leaves it false, so the reveal never fires on an error.

- **Hosting (`Views/RootView.swift`).** The reveal is an **overlay layer** (not a `.sheet`) above the whole app shell - the one surface that survives tab teardown, so it fires on first open regardless of which tab the user lands on (the same hosting precedent as the US-AD05 alert). The flag is flipped the moment the reveal decides to show (a force-quit while it is up cannot re-arm it), the entrance/exit is stilled under Reduce Motion, and it never gates session start.

- **Purely celebratory.** No paywall nudge, resolving the PRD's open question toward the "never a reward withheld" invariant.

## Evidence

`StrengthGraduationEvidenceTests` hosts the production `StrengthGraduationRevealView` in a real key window and asserts on the live accessibility tree, then captures the frame (written under `REPTODAY_WRITE_EVIDENCE=1`):

- `01-strength-graduation-reveal.png` - the reveal as shipped: identity-framed header, the four points, and the "Keep climbing" dismiss control.

Assertions: identity-framed ("earned", "someone who moves") and non-gamified/non-loss-framed copy; explains what changes ("harder", "skill") and points to the "progression map"; the "Keep climbing" dismiss control is a labeled, hittable VoiceOver element and calls back.

The once-only / survives-relaunch / never-re-armed gating is proved in `AppStateTests`; the crossing decision (stub phase service + a true end-to-end pass over the real `PhaseEvaluatorService` and real catalog with earn-threshold logs) in `StrengthGraduationViewModelTests`.

## Validation Test (PRD)

- **Setup:** A user whose logs just crossed the earn threshold; one-shot flag unset.
- **Steps:** Launch the app; dismiss the reveal; relaunch.
- **Expected Result:** Reveal shows once with identity-framed copy, points to the map, never re-appears after dismissal or relaunch.

Covered by the union of: `StrengthGraduationViewModelTests.testRealLogsCrossingTheEarnThresholdTriggerTheReveal` (real earn-threshold logs -> the reveal fires), the `StrengthGraduationEvidenceTests` copy/map assertions (identity-framed, points to the map), and `AppStateTests.testGraduationCelebratedFlagSurvivesRelaunch` / `testCelebratedGraduationIsNeverReArmed` (dismissed -> a relaunch never shows it again).

## Manual QA (Simulator/unit suite cannot fully cover)

- On-device VoiceOver focus-trapping inside the `.isModal` reveal.
- The Reduce-Motion entrance/exit stilling (the `accessibilityReduceMotion` environment is read-only, so the animation gate is enforced structurally rather than hosted).
