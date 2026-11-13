# Player and rest overlay at large text - validation

## What was wrong

On a 375x667 pt screen (iPhone SE) at the largest accessibility text size, the workout player and its rest overlay laid their controls over each other.
Seen on main at `32d66e1`, in the iOS 26.5 Simulator, iPhone SE (3rd generation), Larger Accessibility Sizes at the maximum (`accessibility-extra-extra-extra-large`), light and dark.

- Player, work window and running hold: the secondary row (+ More time, Swap, Finish exercise, Skip) kept four narrow columns, so its titles broke inside words ("Mor e", "Swa p", "Ski p") and grew taller than the room left for them.
  The text spilled up over Done / Stop hold and down past the bottom of the screen, and squeezed the scroll area so the target line and round tracker were gone.
- Rest overlay: nothing shrank far enough, so the whole stack outgrew the screen.
  The top bar (End session, Pause) was pushed above the screen (frame top at -48 pt) and + 15s and Skip rest ran off the bottom (frame bottom at 722 pt on a 667 pt screen).
  The two button titles were also clipped by their fixed 60 pt height.

Before (simulator): `simulator/before-ax5-light-*.png`, `simulator/before-ax5-dark-*.png`.

## What changed

All in `Views/ActiveSession/ActiveSessionView.swift`, using the existing `Theme` tokens.

- **Player secondary row.** Each control's column is now at least as wide as the longest word of its title, so a word is never broken.
  When the row cannot give every column that much (`stacksSecondaryActions`), the controls move into the scrolling column as full-width rows below the round tracker, and only the primary action (Done, Stop hold, Start hold) stays pinned.
  The choice is made from every slot the step can show, so + More time is counted whether or not the countdown runs right now and a swap in flight is counted (and its column sized) by its resting "Swap": starting or stopping a hold or a swap never moves the controls between the row and the column.
  Both the choice and each column's minimum are measured with the Bold Text setting, which draws every title heavier.
  The card still fits to the room around the exercise name, ring and round tracker, so those stay above the fold where they can, and the stacked controls are reached by scrolling.
- **Rest overlay middle.** The heading, ring, next-up text and poses still shrink to fit as before.
  When even their smallest sizes do not fit, the middle scrolls between the pinned top bar and controls (`ViewThatFits`), with the ring kept at full size so its clock is not shrunk.
  The flexible ring and poses now report their minimum as their ideal height, which is what lets the fit check measure the smallest layout.
- **Rest controls.** + 15s and Skip rest stay side by side while both titles fit their half on one line, and stack full width once either would wrap.
  Their titles may wrap rather than clip, with 60 pt as the minimum height.

At the default size nothing moves: on the same simulator walk, every control frame and the rest ring (141 pt) match main exactly.
The one visible difference at the default size is an improvement: on a timed hold's non-final set, main hyphenated "Com-plete set" in its narrow column; now that column takes the width "Complete" needs and the word stays whole.
Before: `simulator/before-default-light-hold-nonfinal-set.png`; after: `simulator/after-default-light-hold-nonfinal-set.png` (hosted 375x667, default text size, light, a running Forearm Plank hold on round 1 of 2).

## Verification

Simulator walk (the real app, onboarding with the stub sign-in, Today -> Start), iPhone SE (3rd generation) 375x667 pt, iOS 26.5:

| Text size | Appearance | Before | After |
| --- | --- | --- | --- |
| `accessibility-extra-extra-extra-large` (largest) | light | overlap, Skip rest off screen | `simulator/after-ax5-light-*.png` |
| `accessibility-extra-extra-extra-large` (largest) | dark | overlap, Skip rest off screen | `simulator/after-ax5-dark-*.png` |
| `large` (default) | light | `simulator/before-default-light-*.png` | `simulator/after-default-light-*.png`, frames identical |
| `large` (default) | dark | not captured | `simulator/after-default-dark-*.png` |

After the fix at the largest size, from the walk's accessibility frames: the top bar sits at 28-88 pt, + 15s at 487-561 pt and Skip rest at 569-643 pt, all hittable; Done and Stop hold sit at 565-643 pt; the stacked secondary controls are reached by scrolling (`*-scrolled.png`).

`PlayerLargeTextFitEvidenceTests` (unit bundle) hosts the production player on an emulated 375x667 SE at six text sizes, light and dark, and asserts that controls are on screen, apart and never break a word, and that Skip rest works when activated the way VoiceOver activates it.
It also runs the running hold with Bold Text on, and asserts that stopping a running hold leaves the primary action where it was and every secondary control in the row or column it was in.
`docs/test-coverage.md` has the full row.

VoiceOver reaching Skip rest: Skip rest is pinned on screen at every size and is an accessibility element the suite activates through `accessibilityActivate()`, VoiceOver's double-tap path.
A live VoiceOver pass on a device was not run.

Existing suites: the full `RepToday` unit suite (1,793 tests) passes, with `PerSideSwapEvidenceTests.testManualHoldCompletionGrowsRatherThanClippingAtAccessibilityType` restated to its real invariant: at accessibility3 "Finish exercise" now fits one line in its full-width stacked control instead of growing a narrow column, and the test asserts it is never clipped either way.
`ContinuousCircuitUITests` passes on the iPhone SE simulator.
Its rotation case had been stopping at the first hold station, because it only advanced work windows, and a Push Day that pairs Wall Push-Up with Forearm Plank has a timed hold as its second station; it now advances a hold by banking the set.
