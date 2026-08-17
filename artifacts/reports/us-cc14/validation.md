# US-CC14 - Accessibility acceptance for the auto-advancing flow (+ More time first-class)

Player/presentation + accessibility story. No change to the deterministic engine, the timing model, the
session/persistence schema, the advance logic, the completion-logging invariant (US-CC09), or the cue
vocabulary (US-CC10). Reps stay the currency; engine determinism / `asOf`-purity preserved.

## What landed

- **+ More time, first-class (AC1 / FR-16).** `ActiveSessionViewModel.extendActiveCountdown(by:)` extends
  whichever of the live **work window** or **hold leg** is running by the **same +15s** the rest's
  "+ More time" (`extendRest`) uses. Surfaced in the player's secondary control row via the shared
  `secondaryAction` (visible "+ More time", accessibility label "More time", `+15s` hint) whenever
  `canExtendActiveCountdown` (`isRunningWorkWindow || isHolding`) - at the 60pt active-screen touch
  target, VoiceOver-reachable and hittable. The rest overlay keeps its own "+15s", so the two never
  double up. A pure display/timer affordance: it changes **nothing logged** (US-CC09 stands - the set
  still records prescribed = performed however long the window ran) and never touches the engine's fixed
  planned wall-clock; neither countdown is persisted, so it writes no snapshot.

- **VoiceOver: no per-second spam, on-demand time (AC2).** The shared `CountdownRing` carries
  `.accessibilityAddTraits(.updatesFrequently)`, so VoiceOver polls the remaining time when the user
  focuses the ring rather than announcing every tick or pulling focus onto the drawing as it counts down.
  The remaining time stays queryable in the ring's own "<name>, N seconds remaining" label.

- **Dynamic Type (AC3).** Movement name, round/set label, target, and the primary control labels wrap
  rather than truncate at the largest accessibility sizes (`fixedSize(horizontal: false, vertical: true)`
  and `minHeight` on the prominent buttons); the ring clock shrinks to fit (`minimumScaleFactor`).

- **Reduce Motion (AC4).** The ring's sweeping arc animates only when Reduce Motion is off
  (`reduceMotion ? nil : .linear`); on, the arc steps to the current fraction with no animation.

- **VoiceOver mid-announcement coordination (AC5).** Inherited from US-CC10: the completion tone is
  withheld while VoiceOver is running (the haptic still fires), and the auto-advance posts no
  screen-change / announcement notification of its own, so an advance never cuts the user off.

## Evidence

`MoreTimeAccessibilityEvidenceTests` hosts the production `ActiveSessionView` in a real key window and
asserts on the live accessibility tree, then captures frames (written under `REPTODAY_WRITE_EVIDENCE=1`):

- `01-more-time-work-window.png` - the work window shows a hittable "More time" control beside the ring;
  the ring carries `.updatesFrequently`; activating "More time" the way VoiceOver's double-tap would
  lengthens the ring's spoken remaining time (asserted before < after).
- `02-more-time-hold.png` - the same on an auto-started warm-up hold, so the control is on *every*
  auto-advancing countdown, not only the work window.

Deterministic companions in `ActiveSessionViewModelTests` ("+ More time" suite) pin the extend arithmetic
on both the work window and the hold, the no-op on a rest / completed session, and the US-CC09
no-log-change invariant under an injected clock.

## Manual QA (captain-verifiable, on device)

- The Reduce-Motion ring stilling: the `accessibilityReduceMotion` environment value is read-only in the
  SDK and cannot be overridden on a hosted surface, so AC4 is enforced by the `CountdownRing` animation
  gate and confirmed on device, not by a hosted assertion.
- Live VoiceOver focus and announcement cadence on the running countdown, and that an auto-advance never
  interrupts speech mid-sentence.
