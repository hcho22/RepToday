# Foundations are Push, Pull, Legs, Core - validation

Decision record: `docs/adr/0006-foundations-push-pull-legs-core.md`.
Suite: `FoundationsEvidenceTests` (unit bundle, `RepToday` scheme), with `REPTODAY_WRITE_EVIDENCE=1` to regenerate these images.

## What was rendered

The production `ProgressTabView` and `StrengthGraduationRevealView`, hosted in a real key window in the iOS Simulator over seeded history, through the real `PhaseEvaluator`, `ProgressAnalytics` and the real exercise catalog.
Each is captured in light, dark and at `accessibility2` Dynamic Type (`large`), except the note, which is committed in light, dark and large.
The one-time note is driven by a real `AppState` over an isolated `UserDefaults` suite.

| Seeded user | State | Images |
| --- | --- | --- |
| Fresh (new install, one short Push session) | Push started but uncleared; every other foundation not started; Legs "0 of 2"; no note (onboarded on this build) | `01-fresh-*.png` |
| Mid-climb (existing install, 8 steady weeks) | Push and Core cleared, Legs "1 of 2" (squat side only), Pull not started (postural work only), so the count drops to 2 of 4 and the one-time note is shown once | `02-mid-climb-note-light.png`, `05-mid-climb-note-dark.png`, `04-mid-climb-note-large.png` |
| Strength (earned, history would not clear Pull) | No climb card, no note, Strength rungs unlocked, ratchet holds | `06-strength-*.png` |
| Graduation reveal | Names only the Push, Legs and Core ladders as gaining Strength-Phase movements | `07-graduation-*.png` |

## Assertions on the live accessibility tree

- Climb card: "2 of 4 cleared", Legs "1 of 2 sides cleared" with "Legs, squat side, cleared" and "Legs, hinge side, in progress"; Legs never reads cleared until both sides are.
- "Where you stand": "Pull, not started yet" although the user has postural pull sessions; Squat and Hinge sides each show their own movement.
- Map: Pull's ladder is Wall Scapular Pull, Supine Floor Row, Single-Arm Supine Floor Row, with no locked rung; Superman Hold never appears on the Pull ladder or the journey.
- Journey (premium): a "Legs, squat side journey" and no Pull journey until the horizontal chain is worked.
- Note: shown on first appearance with "2 of 4 cleared (Push, Core)", the one-shot flag flips when the note actually appears on the climb card, and a later appearance over the same `AppState` does not show it again.
- Strength user: no climb card and no note, although the evaluator alone reads their history as not clearing Pull; the persisted phase is what the tab reads.
- Graduation copy no longer promises a Strength-Phase skill at the top of every foundation.

## Layout fixes found while looking at the renders

Reviewing the large-type renders turned up text wrapping into slivers, so these were fixed:

- Legs' side rows and statuses ("Hinge / side", "In / progress") now put the status under the name when the row is too narrow (`StatusRow`, `TitleNoteRow`).
- "Where you stand" stacks the name above the movement at accessibility sizes.
- The note's "Got it" button uses the primary text colour, since the accent colour was close to invisible on the dark button.
- "Where you stand" keeps every movement in one column: a Squat or Hinge side indents only its label inside the shared name column, so "Bodyweight Squat" and "Glute Bridge" line up with "Standard Push-Up" and "Forearm Plank".
- Unrelated but on the same screen: the consistency headline no longer hyphenates "consistency" beside the score, the consistency-over-time chart no longer overprints its week labels, and the pillar and pattern share bars stack their label above the bar instead of wrapping "Strength" into "Streng-th".

## Dark-mode accent: harness artifact, not app behaviour

The first dark renders showed the light-appearance accent (dark teal, about #2E4F61) on near-black.
The real app is correct: launched in the Simulator in dark appearance it draws the lighter dark-variant accent (about #788F9E) on its Continue button, and a bare accent fill hosted through `HostedSurface.host` in dark also came out as the dark variant.
The cause was in `FoundationsEvidenceTests`: it set `hostedWindow.overrideUserInterfaceStyle` after hosting, on top of the style `HostedSurface.host` already applies, and that left dark surfaces resolving the accent for the light appearance.
Removing the window override (the appearance now comes only from `HostedSurface.host(style:)`) fixes it; the dark ticks, "93", "8 of 8 weeks" and "You're here" now render in the lighter accent.
No app change was needed.
The other checks that did not matter: the accessibility tree being read before capture, the pump loop, the previous window still being visible, and the downscale step.

## Not covered

Live VoiceOver and Reduce Motion behaviour are captain-verifiable manual QA, as for the other Progress-tab surfaces.
Hosted renders exercise the production views, not a cold launch of a real upgraded install.
The dark-variant accent is a muted grey-blue by design, so accent text on dark surfaces is softer than body text; that is the app's palette and was left alone.
