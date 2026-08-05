# US-T04 Validation - live Convex-backed transport

**Story:** US-T04 of `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` - `LiveAnalyticsService`, its wiring, the deployment configuration, and the two remaining hardening rules on `POST /logEvent`.
**Date:** 2026-08-04
**Deployment:** dev `courteous-dogfish-560` (`https://courteous-dogfish-560.convex.site`), the same one US-T01 and US-T03 used.
**Verdict:** PASS, with the PRD's Validation Test **re-framed rather than run as written** - see the next section, which is the most important thing in this file.

> **Read this first, twice.**
>
> **1. The shipped diff contains no emission call site.** Nothing in the app calls `record(_:)`. US-T04 ships the transport and leaves it uncalled, exactly as US-T02 shipped the seam uncalled and US-T05 shipped the identity unread; the 13 emissions are US-T07 through US-T12. So the PRD's Validation Test - "complete onboarding, start a session, confirm events land in the Convex dashboard" - **cannot be run as written against the shipped build**, because the shipped build emits nothing when you do that. It was not made runnable by adding emission sites; that would be another story's scope landing here.
> Instead, a **temporary, non-shipping probe** stood in for the emission sites that do not exist yet, and was removed before the commit. What the live legs below therefore prove is that **the transport and the sink work end to end against a real deployment** - not that the shipped build emits anything. It does not.
>
> **2. This is a point-in-time transcript and nothing re-runs it.** This repository has no CI; no check runs against a pull request. What *does* re-run, when a human runs it, is `npm test` (50 `convex-test` assertions over the `POST /logEvent` boundary, new in this story) and `xcodebuild ... -scheme RepToday test` (`LiveAnalyticsServiceTests`, which drives the transport through an in-process `URLProtocol` stub). Those two are the standing gate; everything below is a record of one afternoon.

---

## What was run, and with what

| | |
|---|---|
| Device | iPhone 16 Simulator, `32039CCE-BE1D-4233-A4D4-19CA9428DBF3` |
| Bundle | `com.reptoday.app`, Debug build, installed and launched by the `RepTodayUITests` scheme |
| Endpoint the app used | the `Info.plist` value this **Debug** build resolved, `https://courteous-dogfish-560.convex.site`, with `/logEvent` appended by `LiveAnalyticsService`. A review round after this run split that value per build configuration (`REPTODAY_ANALYTICS_ENDPOINT` in `project.yml`), so the Debug origin above is unchanged and every leg here still describes what a Debug build does - while a **Release** build now carries no endpoint at all and is inert. The live legs below were not re-run for that change; all four suites in section 4 were |
| Sink-side probes | `curl` against the same origin |
| Rows read back with | `npx convex data events` |

The temporary probe was two files, both deleted before the commit: `App/UST04ValidationProbe.swift` (emits a burst of `ready_screen_shown` events from the **main actor**, timing how long each `record(_:)` call takes to return) and `RepTodayUITests/UST04ProbeUITests.swift` (drives onboarding -> Ready Screen -> a duration-chip regeneration -> Start -> a session run to completion -> Done, timing each phase). The probe reads `REPTODAY_T04_PROBE=1` from the app's launch environment and does nothing without it.

---

## 1. The sink's new rejections, before and after, against a real deployment

Both hardening rules are gaps US-T03 shipped **knowingly**, on the stated reasoning that nothing could reach the endpoint until a client existed. This story is that client. Each was probed against the pre-US-T04 action (deployed by stashing `convex/http.ts`, redeployed straight after) and then against the hardened one, so the pair is a before/after on one deployment rather than a claim about what used to happen.

| Payload | Before (US-T03 action) | After (US-T04 action) |
|---|---|---|
| `installId` of 65 bytes | *(not probed before; the rule did not exist)* | `400 installId is 65 bytes, over the 64-byte limit` |
| `installId` of 64 bytes | - | `204`, one row |
| `installId` of 300 KB | **`204` - the row was inserted** | `400 body is 300081 bytes, over the 65536-byte limit` |
| `installId` of 1.5 MB | **`500 internal error`** (past Convex's document limit; the false-outage case) | `400 body is 1500093 bytes, over the 65536-byte limit` |
| `props` bag of 3 MB | `400 props is 3000011 bytes, over the 4096-byte limit` | `400 body is 3000118 bytes, over the 65536-byte limit` |
| `props` bag of 16 MB | `400 props is 16000011 bytes, over the 4096-byte limit` | *(same class as 24 MB)* |
| `props` bag of 24 MB | **`500 internal error`** (the argument-serialization case) | `400 body is 24000113 bytes, over the 65536-byte limit` |
| `props` of 5011 bytes | - | `400 props is 5011 bytes, over the 4096-byte limit` |

**Two findings here are corrections to what the documentation predicted, and they are recorded as corrections rather than smoothed over.**

- The 300 KB `installId` did **not** fail at the insert as `convex/README.md` and `docs/implementation-log.md` predicted. It **succeeded**, inserting a 300 KB row. Convex's document limit is around 1 MB, so a few hundred KB fits comfortably; the false-outage `500` only starts at ~1.5 MB. The accepted gap was therefore *worse* than it was written up as - not a misclassified status code but an actual 300 KB row in the evidence table, through the one field with no ceiling. That row was deleted; see below.
- The `props`-bag argument-bound `500` reproduces at **~24 MB, not the ~8 MiB** the PRD and `README` cite. 3 MB and 16 MB both came back as the mutation's own `400`. The concern was real, the threshold in the prose was not; both documents now say ~24 MB observed rather than ~8 MiB assumed.

The last line of the table is the one that shows the new request-size cap does not swallow the more specific rejection it sits in front of: a 5011-byte bag is over the `props` cap and under the request cap, so the caller is still told which limit it actually broke.

### The junk row the "before" probe inserted was deleted

The 300 KB row (`j57bgfkkede805gq4pzsn2d6758bxe39`) existed only because the pre-fix probe inserted it, and it is gone. It was deleted the way US-T03 deleted its own junk row, and by the same reasoning - this file's method is proof-by-table-contents, and the repository claims to contain exactly one mutation: a scratch `deleteById` internal mutation was written in a temporary working copy **outside the repository**, deployed to the dev deployment, run once against that single document id (it returned `"deleted"`), and then removed by redeploying this branch's own code. It was never committed. The repository still contains exactly one mutation, `logEvent`, and it is still internal.

The table read back afterwards holds the seven US-T03 rows plus this story's two intended ones (`CURL-LIVE-US-T04-0001`, and the 64-`b` row that proves the bound accepts its own limit), and nothing else.

---

## 2. The transport, end to end, from the real installed app

The probe emitted 40 `ready_screen_shown` events through the sink `ServiceContainer.live(context:installId:)` actually wired - the log line records which one that was:

```
T04PROBE endpoint=shipped sink=LiveAnalyticsService
T04PROBE installId=FBC91D46-3D56-4FDF-AFF8-7E390921E9A7
```

The rows landed. Two of them, read straight back off the deployment:

```
_id                                | _creationTime      | clientTs      | installId                              | name                 | props                   | serverTs
"j57bswk32e45j193pgae8kv8q18bwdc4" | 1785893288638.2139 | 1785893288473 | "FBC91D46-3D56-4FDF-AFF8-7E390921E9A7" | "ready_screen_shown" | { "generation_ms": 38 } | 1785893288638
"j5768hwn44tx42ssjdr7cay3n58bxa9n" | 1785893288376.7136 | 1785893288216 | "FBC91D46-3D56-4FDF-AFF8-7E390921E9A7" | "ready_screen_shown" | { "generation_ms": 38 } | 1785893288376
```

Three things in those rows are the point of the whole story:

- **`installId` is the app's own.** The app container's `Library/Preferences/com.reptoday.app.plist` reads `AppState.installId = FBC91D46-3D56-4FDF-AFF8-7E390921E9A7` - the same string, character for character. It was read out of the installed app's own preferences, not out of a test double, and it was minted by `AppState` (US-T05), which remains the only thing that resolves identity. Nothing re-derived it on the way to the wire.
- **Both timestamps are populated and distinct.** `clientTs` is what the app sent (a bare JSON number of milliseconds); `serverTs` is stamped by the mutation.
- **`props` holds a plain scalar.** `{ "generation_ms": 38 }`, not `AnalyticsValue`'s tagged in-process form `{"type":"int","value":38}`. That is the wire-shape requirement, observed on the stored row rather than only asserted in a unit test.

---

## 3. An unreachable sink changes nothing about the loop

The PRD asks for airplane mode. A Simulator has none: it shares the host's network stack, and there is no per-device toggle. The substitute was to point the app at `https://10.255.255.1` - a routable-looking address that black-holes - so **every send hangs until its 10-second timeout** rather than failing instantly. State plainly what that swaps: it is *harsher* than airplane mode for the question being asked (a hang is the worst case for anything that might wait on it) but it does **not** exercise the OS's immediate `notConnectedToInternet` error path. That path is covered instead by `LiveAnalyticsServiceTests.testTransportFailureIsSwallowedAndTheServiceKeepsSending`, which injects exactly that `URLError` through the `URLProtocol` stub.

The same full touch path was driven three times: online, against the black hole, and online again.

**The core interactions, timed by the UI driver (milliseconds):**

| Phase | Online | Unreachable sink | Online again |
|---|---|---|---|
| launch to onboarding | 4517 | 4491 | 4562 |
| onboarding to Ready Screen | 7560 | 7559 | 7565 |
| duration-chip regeneration | 1486 | 1457 | 1475 |
| Start tap to player open | 1809 | 1787 | 1781 |
| session run to summary | 8549 | 6810 | 8551 |
| completion back to Ready | 1753 | 1752 | 1753 |

Nothing spins, stalls, or errors. The one column that moves is "session run to summary", and it moves *down* under the black hole (6810 ms vs 8549 ms), which is noise from how many taps that particular generated session needed rather than a telemetry effect - the sessions are generated per run and are not the same session. Every other phase is within ~1.5% across all three runs. No error surfaced in the app at any point; the driver asserts `Start` stays reachable across a regeneration and the run passes.

**How long `record(_:)` took to return, called on the main actor** - the caller that matters, since it is the thread the UI runs on:

| | Online | Unreachable sink |
|---|---|---|
| n | 40 | 40 |
| min | 0.030 ms | 0.028 ms |
| median | 0.064 ms | 0.072 ms |
| p90 | 0.657 ms | 0.927 ms |
| max | 103.9 ms | 122.0 ms |
| mean | 4.33 ms | 4.89 ms |

The median is tens of *microseconds* in both columns, and the two distributions are the same shape - which is the claim: whether the sink answers in 40 ms or never answers at all, the caller is not waiting on it. The outliers are worth naming rather than hiding: they are main-actor scheduling, not network. `record(_:)` is `async`, so awaiting it from a `@MainActor` task suspends and resumes on the main actor, and every one of the >50 ms samples lands during app launch or an onboarding transition, when the main thread is busy with UI work the probe is competing with. They occur in both columns and at the same points.

**Nothing was emitted while the sink was unreachable.** The row count for this install was 120 before the black-hole run and **120 after it** - the 40 hanging sends produced no rows, and equally produced no queue, no retry, and no crash. Losing offline events is expected and stated as acceptable in the PRD.

**Emission resumed when connectivity returned.** The third run put the count at **160**: 40 more rows, same install id, no restart needed beyond the run's own launch.

---

## 4. The suites that do re-run

Both were run locally, on this branch, after the probe was removed. This repo has no CI, so these are the only gates that exist and they gate nothing automatically.

| Suite | Command | Result |
|---|---|---|
| iOS unit | `xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday -destination 'id=32039CCE-…' test` | **863 tests, 0 failures** (862 as this story first landed; the review round below added one) |
| iOS UI | `xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepTodayUITests -destination 'id=32039CCE-…' test` | **5 tests, 0 failures** (re-run after the review round below, since it is the only suite that installs and launches the app and the endpoint now reaches `Info.plist` through a build setting) |
| Convex boundary | `npm test` (`vitest run`, `convex-test` in process) | **50 tests, 0 failures** |
| Convex types | `npm run typecheck` | clean |

No test in any of them performs a real network call. The Swift ones intercept in process with a `URLProtocol` stub; `convex-test` runs the real functions against an in-memory database and no deployment.

One consequence of the transport landing is recorded in `docs/test-coverage.md` and worth repeating here: the US-T02 container test used to drive all 13 events through `ServiceContainer.live(context:)` for free, because production wired the discarding no-op. It cannot any more - that container now wires a real transport pointed at a real deployment, and recording through it from a unit test would put 13 POSTs on the wire. The test now asserts the production container's wiring **by type**, and emits only through the mock.

### The per-configuration endpoint split, verified at the artifact

A review round after this run split `REPTODAY_ANALYTICS_ENDPOINT` per build configuration. The intended shape was to assert both halves from the running app bundle and run the suite twice, once per configuration. **The Release run does not build**, and that was found by trying it rather than assumed: this project sets `ENABLE_TESTABILITY` on the Debug configuration only, so `@testable import RepToday` cannot resolve and `xcodebuild ... -configuration Release test` fails at compile with `unable to resolve Swift module dependency to a compatible module: 'RepToday'`. Turning testability on for Release would de-optimise the shipping binary to make one test runnable, which is a worse trade than the gap, so it was not done.

The Release half is therefore verified at the **built artifact** rather than by a test run - which is a direct observation of what ships, not an inference about it:

```
$ xcodebuild ... -configuration Release -sdk iphonesimulator build   # ** BUILD SUCCEEDED **
$ plutil -extract RepTodayAnalyticsEndpoint raw -o - \
    "$DD/Debug-iphonesimulator/RepToday.app/Info.plist"
https://courteous-dogfish-560.convex.site
$ plutil -extract RepTodayAnalyticsEndpoint raw -o - \
    "$DD/Release-iphonesimulator/RepToday.app/Info.plist"
                       # the empty string
```

So a Release build ships the key present and empty, which `LiveAnalyticsService.endpoint(fromOrigin:)` already rejects (unit-covered by `testUnusableEndpointConfigurationResolvesToNil`), and the container falls back to `NoOpAnalyticsService`. What this does **not** establish: that a Release build was installed and observed staying silent at runtime. It was not.

### FR-13, made structural in the same round

That tripwire fired only because that one test happened to emit; `CoreDataServicesTests` builds the same production container for its CoreData wiring and does not emit, so it was quiet by luck, and US-T07 through US-T12 would have taken the luck away. `live(...)` now accepts an optional `analyticsService` (defaulting to production's own resolution, so the funnel test still asserts the default), and the two CoreData container tests pass `NoOpAnalyticsService`. "No test performs a real network call" is now held by the code rather than by the absence of emission call sites.

---

## What this record does **not** establish

- **That the shipped build emits anything.** It does not. See the note at the top. Every row above was produced by a probe that is not in the diff.
- **Airplane mode.** A black-holed endpoint was used instead, for the reason given in section 3, and it does not exercise the OS's immediate offline-error path (the unit suite does).
- **A real device, a real App Store build, or real network conditions.** Simulator, Debug, one Mac, one afternoon. The Simulator shares the host's network stack, so nothing here says anything about cellular, captive portals, or a device with genuinely no radio.
- **The production deployment.** There isn't one. A **Debug** build resolves the dev deployment `courteous-dogfish-560`; a **Release** build resolves nothing and is inert, which is the deliberate state until one is chosen (`REPTODAY_ANALYTICS_ENDPOINT` in `project.yml`). Which account and plan host the production sink is still an open question in the PRD; choosing and configuring it is a precondition for shipping any build that emits, and it is a configuration change rather than a source edit.
- **The Release configuration end to end.** The Release app was *built* and its `Info.plist` read (section 4), which shows it carries no endpoint. It was not installed, launched, or observed staying silent, and the Release **test** run does not build at all in this project - so nothing here exercises the Release code path at runtime.
- **Volume.** 160 rows from one install. Nothing here says what the sink does at launch scale, and the route is still unauthenticated and unmetered - that is US-T14.
- **Any future commit.** Point-in-time, no CI, nothing re-runs it. The `npm test` and `LiveAnalyticsServiceTests` suites are the parts that do.
