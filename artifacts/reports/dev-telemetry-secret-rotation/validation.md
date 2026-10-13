# Dev usage-data secret rotation - 2026-10-13

## What happened

The repository became public while the Debug configuration still committed the dev sink's shared secret (`REPTODAY_ANALYTICS_SECRET`) in `ios/RepToday/project.yml` and the generated project.
The production secret was never in the repository and nothing here touched it, its Keychain item or the production deployment `sensible-spider-810`.

The dev deployment `courteous-dogfish-560` now accepts only a new value.
That value was generated from `/dev/urandom` (32 bytes, 64 hex digits), stored in the macOS login Keychain item `com.reptoday.analytics.development` / `debug-build`, and set as the deployment's `ANALYTICS_SHARED_SECRET`.
It was never printed, passed as a command argument, or written to a tracked file.
Every deployment command named `courteous-dogfish-560`; the production Keychain item's modification date is still 2026-08-31.
The old value is still readable in git history, which was not rewritten; it is useless because the deployment refuses it.

`convex/README.md` ("The dev secret on a Mac") owns the developer steps.

## Scenarios

Each row is bound to code commit `7e34db8`, this Mac (Xcode 26.5, an iPhone 17 / iOS 26.5 Simulator created for the work), the dev deployment `courteous-dogfish-560`, and 2026-10-13.

| Scenario | Expected | Observed | Result |
|---|---|---|---|
| No secret value in any tracked file | neither the old nor the new value in a tracked file | both absent at the final commit | pass |
| The CI check fails on a planted value | failure naming the file, value withheld | 8 check tests pass; the check also fails on the tree as it was before this change | pass |
| Old value refused, new value accepted | 401 and 204 | 401 and 204, twice | pass |
| A Debug build with the Keychain item sends an accepted event | one row on dev for its install id | 1 row (`onboarding_started`) | pass |
| A Debug build without it builds, runs and blocks nothing | builds, launches, sends nothing, shows no error | built, launched to onboarding, still running after 12 s, 0 rows, no crash report | pass |
| Release archive wiring unchanged | same resolved settings, same wrapper behaviour | settings and schemes identical; the stand-in archive cases pass before and after | pass |
| Unit suite green with no secret (the CI state) | all pass | 1,667 tests, 0 failures | pass |
| CI green | all jobs pass on the pull request | not yet run when this was written | untested here |
| A real App Store archive | the production value in the archive | not run: it sends to production | untested |

Material change beyond the plan: three app source files changed so tests and the XCUITest probe no longer depend on a committed secret (`ServiceContainer.live(analyticsConfiguration:)`, `LiveAnalyticsService.configured(secretStandIn:)`, and the Debug-only probe harness).
A Release build passes neither: it reads its own bundle and has no stand-in.

Judgment a reviewer still owes: reading the diff of `tools/archive-release.sh` and the two production validators to confirm they read the same production Keychain item and write the same file as before.

## Rotation

Rotated at **2026-10-13T17:21:29Z** with `tools/dev-telemetry-secret.sh rotate`, after the code that removes the value was committed (`7e34db8`).
The command named its target before changing anything: `target deployment: courteous-dogfish-560 (dev: the Debug REPTODAY_ANALYTICS_ENDPOINT)`.

Every line below is an HTTP status from `POST https://courteous-dogfish-560.convex.site/logEvent`.
No request or response body is recorded here.

| When | Value sent in `X-RepToday-Analytics-Secret` | Status | Meaning |
|---|---|---|---|
| Before the rotation | the value published in the repository | 204 (at 2026-10-13T17:20:55Z) | it was live until the rotation |
| After | the new Keychain value | 204 | accepted |
| After | the value published in the repository | 401 | refused |
| After | no header | 401 | refused |
| After | a random wrong value | 401 | refused |

A second, independent run of `tools/dev-telemetry-secret.sh verify --refused-value-file <published value>` at 2026-10-13T17:22:08Z gave the same four results.

## A Debug build with and without the Keychain item

Both legs built the `RepToday` scheme in Debug (Xcode 26.5), installed the app on an iPhone 17 / iOS 26.5 Simulator created for this work, launched it under a reserved `dev-validation-debug-*` install id, and read that id's rows back from the dev deployment with the internal `reconcile:eventsForInstalls` query.

| Leg | `RepTodayAnalyticsSecret` in the built `Info.plist` | App after 12 s | Rows on dev for its install id |
|---|---|---|---|
| With the Keychain item (`tools/dev-telemetry-secret.sh install`, then build) | 64 characters | running | 1 (`onboarding_started`) |
| Without it (`remove`, then build) | empty | running, onboarding shown, no error | 0 |

So a Debug build without the secret sends nothing, rather than sending requests that are refused, and it builds, launches and keeps running.
The unit suite states the same thing in process: `LiveAnalyticsServiceTests.testADebugBuildWithoutTheDevSecretWiresTheInertSinkAndSendsNothing`.

## Release wiring is unchanged

- `xcodebuild -showBuildSettings` for the app, unit-test and UI-test targets in Debug, Release, CoachDeviceQA and CoachStaging was captured before and after. The only difference in all twelve is that Debug's app target no longer resolves `REPTODAY_ANALYTICS_SECRET` from the project. All four shared schemes are byte-identical.
- With a plainly fake `DebugTelemetry.local.xcconfig` in place, Debug resolved it and Release, CoachDeviceQA and CoachStaging still resolved nothing, so the dev value cannot enter another configuration.
- Release with a fake value passed by `-xcconfig` resolved that value, as the archive wrapper relies on.
- `tools/test-telemetry-secret-wiring.sh` passes, and its archive cases also pass against `tools/archive-release.sh` as it was before this change.

## Checks

| Check | Result |
|---|---|
| `tools/check-no-committed-telemetry-secret.py` on this tree | no committed value |
| The same check on the tree before this change | failed, naming `project.yml` and the generated project, value withheld |
| The old and the new value searched for in every tracked file at the final commit | absent |
| `RepToday` unit suite, Debug, no secret present (the CI state) | passed: 1,667 tests, 0 failures, 1 skipped (the opt-in benchmark) |
| Analytics and container suites, Debug, a plainly fake secret present | passed: 72 tests, 0 failures |
| `TelemetryOptOutUITests`, Debug, no secret present | passed: 5 tests, 0 failures |
| `npm run typecheck`, `npm test` (the sink) | passed, 97 tests |

## Not exercised

- A real App Store archive through `tools/archive-release.sh`, and the two production validators' live legs: they send to production, which this work must not touch. The wrapper's wiring is covered offline by the stand-in test and by the build-settings comparison.
- A Debug build on a physical phone. The route is the same xcconfig the Simulator build read.

## Recovery

- Reverting the code restores the old wiring but not the old secret; the deployment keeps refusing it, by design.
- If the Keychain value is lost: `tools/dev-telemetry-secret.sh adopt` copies it back from the deployment, or `rotate` replaces it.
- One accepted event proves the route again: `tools/dev-telemetry-secret.sh verify`.
