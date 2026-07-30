# Asset attribution

Every third-party asset that ships inside the Rep Today binary must have a row here first.

The rule is deliberately hard: an asset with no recorded source and license is **not cleared for distribution**, so it stays out of the app target's Copy Bundle Resources phase (`ios/RepToday/project.yml`) and out of `Resources/Exercises.json`.
The exercise demo degrades to its SF-Symbol fallback on its own (US-O01), so holding an asset back costs nothing but the animation itself.

## Exercise demo animations (US-O01)

An animation only ships once **both** are true: it has a cleared row below, and its exercise carries the matching `animationName` in `Resources/Exercises.json`.
`ExerciseLibraryTests.testEveryAnimationNameResolvesToABundledFile` enforces the second half - a catalog entry naming a file the bundle does not carry fails the build.

| File | Embedded name | Source | License | Cleared to ship |
| --- | --- | --- | --- | --- |
| _(none yet)_ | | | | |

The app therefore ships entirely on the SF-Symbol fallback today, which is the designed steady state until a cleared animation arrives.

## Removed assets

### `push_standard.json` (removed)

Added as the US-O01 validation fixture ("a single test `.json` dropped into `Resources`") to prove the Lottie seam and its fallback end to end, then **deleted from the repository**.

It was a third-party Lottie whose origin was never written down, so nobody could say what redistributing it would require.
Keeping it out of Copy Bundle Resources addressed the risk of shipping it inside the binary, but the file was still committed to a public repository - which is itself redistribution - so excluding it from the bundle was never enough.
Since its provenance could not be reconstructed, it was removed rather than kept as a repo-local fixture.

Nothing depended on it: no `Exercises.json` entry ever referenced it, and the seam it validated is covered by `ExerciseDemoView`'s fallback path plus `ExerciseLibraryTests.testEveryAnimationNameResolvesToABundledFile`, which still gates any future `animationName` against the bundle.
The next animation to land must arrive with its source and license row above **before** it is added to `Resources`.
