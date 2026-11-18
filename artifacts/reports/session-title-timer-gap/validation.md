# Workout timer sits close under the exercise title

On a roomy phone the player's flexible spacer pushed the workout timer down to Done, leaving a large gap between the exercise name and "TIME LEFT".
The timer now follows the round tracker at the column's rhythm, and the spare height stays below it, above the pinned controls.

## Screenshots

Taken in the Simulator (iOS 26.5) by walking the real app into a session: a rep work window (Standard Push-Up) and a warm-up hold (Downward Dog).

| | Before | After |
|---|---|---|
| iPhone 17 Pro Max, rep | `before-promax-rep.png` | `after-promax-rep.png` |
| iPhone 17 Pro Max, hold | `before-promax-hold.png` | `after-promax-hold.png` |
| iPhone SE (3rd generation), rep | `before-se-rep.png` | `after-se-rep.png` |
| iPhone SE (3rd generation), hold | `before-se-hold.png` | `after-se-hold.png` |

On the Pro Max the gap between the round tracker and the timer drops from about 70 pt to the 12 pt column rhythm.
The SE is unchanged: its card already shrinks to fit, so it never had spare height.

## Tests

`TrainerPoseEvidenceTests.testRoundTrackerDotsStayAboveTheFoldInEveryState` now asserts that the timer starts one column rhythm below the round tracker on 393x852 and 375x667.
The full `RepToday` unit suite passes, including the large-text fit suites.
