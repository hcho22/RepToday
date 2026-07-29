# Asset attribution

Every third-party asset that ships inside the Rep Today binary must have a row here first.

The rule is deliberately hard: an asset with no recorded source and license is **not cleared for distribution**, so it stays out of the app target's Copy Bundle Resources phase (`ios/RepToday/project.yml`) and out of `Resources/Exercises.json`.
The exercise demo degrades to its SF-Symbol fallback on its own (US-O01), so holding an asset back costs nothing but the animation itself.

## Exercise demo animations (US-O01)

An animation only ships once **both** are true: it has a cleared row below, and its exercise carries the matching `animationName` in `Resources/Exercises.json`.
`ExerciseLibraryTests.testEveryAnimationNameResolvesToABundledFile` enforces the second half - a catalog entry naming a file the bundle does not carry fails the build.

| File | Embedded name | Source | License | Cleared to ship |
| --- | --- | --- | --- | --- |
| `ios/RepToday/RepToday/Resources/push_standard.json` | `military_push_ups` | Not recorded | Not recorded | **No** |

### `push_standard.json`

Added as the US-O01 validation fixture ("a single test `.json` dropped into `Resources`") to prove the Lottie seam and its fallback end to end.
It is a third-party Lottie whose origin was never written down, so nobody can say today what redistributing it inside the app would require.

Until that is answered it stays a repo-local fixture: excluded from the app bundle, and not referenced from `Exercises.json`.
Its opaque full-canvas `White Solid 1` layer has been stripped so the animation composites onto `Theme.Colors.secondaryBackground` correctly in both light and dark mode whenever it is cleared - the asset is ready, the paperwork is not.
