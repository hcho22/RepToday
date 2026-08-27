# US-AN01 - Strength-journey analytics (premium)

Rendered by `RepTodayTests/StrengthJourneyEvidenceTests` on every run.
Re-generate the committed PNGs with `REPTODAY_WRITE_EVIDENCE=1` (see `AGENTS.md`).

## What the story adds

The premium **Deeper analytics** layer gains a **strength journey** anchored on progress over time,
not just this week's numbers:

- a per-chain **tier-advancement timeline** ("Wall Push-Up -> Standard Push-Up, 6 weeks") read from
  real `WorkoutLog` history, each tier stamped with the date it was first performed;
- the current **phase-earning progress**, reusing US-SP04's `PhaseProgress` signals rather than
  recomputing them.

It is a new `StrengthJourney` field on `DeepAnalytics` (`ProgressAnalytics.makeStrengthJourney`), so it
is premium-gated at the **same render boundary** as the other deep layers - `ProgressTabView` renders
it only inside `if viewModel.isPremium { DeepAnalyticsSection }`.

## What the images show

| File | Surface | What it evidences |
| --- | --- | --- |
| `01-strength-journey-premium.png` | The production `ProgressTabView` for a **premium** user with a multi-week push climb | Under **Deeper analytics**, the **Your strength journey** card shows Push advancing **Wall Push-Up -> Standard Push-Up, 6 weeks**, with the per-tier timeline dated (Wall reached May 27, Knee Jun 17, Standard Jul 8 - marked "you're here"), a second foundation (Squat) "getting started", and the **Earning the Strength Phase** readout reusing the phase-earn signals. The card follows the app's visual system (the same connector-rail marker ladder, `Theme` tokens, identity-framed copy). |
| `02-strength-journey-free-gated.png` | The production `ProgressTabView` for a **free** user with the identical history | The strength-journey card is **absent**; the free chain-position and progression-map layers still render, and the **Go deeper with Premium** upsell stands in place of the whole deep layer. This is the render-boundary gate: no deep depth leaks to a free user. |

## What the tests pin (not the images)

- The timeline's dates and week-span duration, earliest-reached-wins, the never-report-a-locked-tier
  invariant (a Discipline user never sees a Strength tier as reached; a Strength user does), a single
  worked tier being a position but not an advancement, active-chain reuse from `chainPositions`,
  untrained-pattern omission, and skipped/set-less exclusion - all in `ProgressAnalyticsTests`
  (`testStrengthJourney*`).
- That the premium tree carries the dated advancement / per-tier dates / phase-earn readout and the
  free tree carries none of it - asserted on the live `AccessibilityTree` in
  `StrengthJourneyEvidenceTests`.

## What these images do *not* prove

- The advancement arithmetic or the honesty invariants above - those are behavioural and live in
  `ProgressAnalyticsTests`, not in any pixel.
- That the numbers are the engine's own: the view reads through the real `ProgressAnalytics` and
  `PhaseEvaluatorService` over the real catalog, and the deterministic logic is pinned in
  `ProgressAnalyticsTests`; the images show a reviewer the actual pixels.

## Captain-verifiable manual QA

- Live on-device **VoiceOver** reading of the timeline (each milestone is a single combined element
  naming the movement, its reached date, and "you're here" for the frontier) - the hosted suite
  asserts the labels are on the tree, but Simulator VoiceOver is a proxy for the on-device announce
  order and focus behaviour.
- **Reduce Motion** and Dynamic Type on the strength-journey card - the layout uses
  `fixedSize(vertical:)` so text wraps, but the on-device rendering is captain-verifiable.
