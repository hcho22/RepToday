# Trainer art for the six new movements: validation (2026-11-18)

Wide, One-Legged, Spider and Explosive Push-Up, Burpee with Push-Up and Burpee now show both Trainers' start and end poses on the exercise card.

## Evidence

The twelve `<exercise id>-<trainer>-card.png` files are crops of the production `ActiveSessionView` rendered by `PushLegsCardEvidenceTests.testNewMovementsShowTheTrainerPoses` in the iOS 26.5 Simulator (iPhone 16, 393x852 pt, dark), at half scale.
Each shows START left and END right, both figures on the floor glow, at the art's own proportions, on a transparent background.
The same run read "<name>, trainer showing start and end positions" from the accessibility tree for every movement and Trainer, and never "<name> demonstration" (the icon fallback).

## Checks

- `xcodebuild ... -scheme RepToday test` on a lane-owned iPhone 16 / iOS 26.5 Simulator: 1954 tests, 8 skipped, 0 failures.
- `python3 tools/test-check-trainer-art.py`: 5 tests OK; the build's `Report Trainer art gaps` phase lists only the two Pull movements' start poses.
- Importer diff: exactly 24 new image sets, no tracked image set changed (`git diff --quiet` on the asset catalog); every new PNG is byte-identical to its aligned file in the art folder.
- Each new PNG: 600x600 RGBA, the shipped sRGB profile, transparent corners, alpha 255 everywhere inside the figure, lowest ground contact at y=521, 252-256 colours, 33,370-57,642 bytes.

## Accepted as delivered

The captain accepted these without a redo: the Spider Push-Up END knee reaches the hip rather than the elbow; the female Burpee with Push-Up END head is drawn larger than her START; both Explosive Push-Up ENDs are drawn about 6-7% larger than their STARTs and tilted about 37-39 degrees.

## Not covered

The XCUITest `TrainingDayUITests` (which now expects Trainer art on every movement a session serves) compiles (`build-for-testing` succeeded) but was not run here.
