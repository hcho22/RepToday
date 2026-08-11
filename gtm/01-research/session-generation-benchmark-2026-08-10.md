# Session-generation latency benchmark - substantiation for the "under 100 ms" claim (2026-08-10)

Substantiation record for the pre-publication checklist item
(`gtm/08-redteam/pre-publication-checklist.md` line 17, "Device benchmark record for the 'under 100 milliseconds' claim")
and for FR-12 as it appears across assets: "the on-device Deterministic Engine assembles every session offline in <100ms
from the Session Policy," across the full 5-60 minute range, including one-tap duration-chip regeneration.

This record supersedes the design-only predecessor `gtm/01-research/session-generation-benchmark.md` (2026-08-06),
which specified the device method but carried no numbers and no re-runnable harness.
It adds both: a committed XCTest benchmark and a proxy run of it.
The predecessor's device table and blocking framing still stand and are reproduced (as PENDING) below.

## Status: PARTIAL - optimistic proxy captured; authoritative on-device p95 (iPhone XS / iOS 17) still PENDING

The proxy numbers below **do not substantiate the claim on their own** and must not be published as if they did.
A test bundle runs in the iOS Simulator, which executes on the host Mac's CPU, so these figures reflect desktop-class
silicon, not the slowest supported iPhone.
They are an *upper bound on how good the answer could look* and a floor on how much headroom exists - useful as an early
signal, not as evidence for a device latency claim.
The box that only real hardware can check is in the PENDING section; do not publish any asset carrying the "under 100 ms"
number until the iPhone XS p95 row is filled in and passes.

## 1. What was measured, and why it is the right call

The claim is about the **deterministic on-device engine that assembles a concrete session** (blocks, exercises, sets/holds
for a requested duration) from the already-written `SessionPolicy` - **not** the asynchronous, off-device AI Programmer that
*writes* the policy (that never runs in the core loop and is explicitly out of the <100 ms budget).

Exact entry point benchmarked:

- `MockWorkoutEngine.generateWorkout(requestedMinutes:user:recentLogs:sessionPolicy:)`
  - `ios/RepToday/RepToday/Services/Mock/MockServices.swift:28`
  - Despite the `Mock` name, this is the **production** `WorkoutEngineProtocol` conformer: `ServiceContainer` wires it in
    **both** `.live(...)` and `.mock(...)` (`ios/RepToday/RepToday/DI/ServiceContainer.swift:92` and `:245`). There is no
    separate "real" engine.
  - It runs the full deterministic pipeline (Steps 1-7) through `SessionAssembly.assemble(...)`
    (`ios/RepToday/RepToday/Services/Engine/SessionAssembly.swift:129`).

This is the same await the shipping app times to produce the marketing/telemetry number: `ReadyViewModel.generate()`
brackets exactly this call to emit `generation_ms` on `ready_screen_shown`
(`ios/RepToday/RepToday/ViewModels/ReadyViewModel.swift:407`, US-T09).
The Ready Screen's first open and every duration-chip tap both reach the engine through this one call, so benchmarking it is
benchmarking the claim's own unit, not a proxy for it.

The engine's `generateWorkout` awaits `exerciseService.exercises()`, which returns the already-decoded, in-memory library
(`MockExerciseService` decodes + integrity-validates `Exercises.json` **once** at construction, at app launch, then serves
cached lookups - `ios/RepToday/RepToday/Services/Mock/MockExerciseService.swift`). So the timed region matches production:
library already loaded at launch, engine assembling per request. The one-time library-load cost is reported separately as
context, outside the timed region.

## 2. Method

Harness: `ios/RepToday/RepTodayTests/SessionGenerationBenchmarkTests.swift`, test
`testSessionGenerationLatencyBenchmark`. Pure measurement - it does not alter engine behavior.

- **Deterministic input.** Fixed clock (injected into the engine) + fixed UTC calendar + a fixed intermediate,
  desk-bound user with a few days of mixed history, so two runs assemble the same sessions and the only variable is host
  speed. History is non-empty on purpose: it gives Steps 2-6 real staleness/capacity signal to chew on rather than the
  cheap empty-history path.
- **Across the range.** Durations sampled: **5 / 10 / 15 / 20 / 30 / 45 / 60** minutes (the chip vocabulary), since the
  claim covers the whole 5-60 range and session length drives how much the engine assembles (single-focus -> blend-extended).
- **Cold (defined).** A freshly constructed engine per sample over the shared, already-decoded library; the engine's
  **first** generation is timed. Models the first Ready Screen generation after a fresh launch (library cached at launch,
  engine instance has done no prior work). `coldIterations = 500` per duration.
- **Warm (defined).** One engine, warmed with a throwaway generation, then repeated timed generations. Models repeated
  one-tap duration-chip regeneration inside a live session. `warmIterations = 2000` per duration.
- **First-in-process.** The single genuinely process-cold generation per duration (captured before any warm-up, so
  process-global Swift type caches are cold), N=1 each - the closest in-process analog to a true device cold launch, and
  itself optimistic on desktop silicon.
- **Percentiles.** Nearest-rank: for a sorted ascending sample of size n, `p` maps to the value at rank `ceil(p*n)`.
  **p95 is the headline the claim is judged on** (`percentile(sorted, 0.95)`), reported alongside p50 and max.
- **Timing clock.** `DispatchTime.now().uptimeNanoseconds` (monotonic; does not drift with the calendar), the same clock
  the existing `SessionAssemblyTests.testGenerationLatencyUnder100ms` uses.

### One-line command to reproduce

The benchmark is **opt-in and skipped by default** (so a plain `xcodebuild test` and the CI `ios` gate never pay its ~17.5k-generation cost); pass `RUN_SESSION_BENCHMARK=1` to run it.
The flag reaches the Simulator-hosted process through the `RepToday` scheme's forwarded environment, exactly like `REPTODAY_WRITE_EVIDENCE`.

Simulator (proxy):

```bash
cd ios/RepToday && xcodegen generate
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  RUN_SESSION_BENCHMARK=1 \
  -only-testing:RepTodayTests/SessionGenerationBenchmarkTests test
```

Real device (authoritative) - **same harness, unchanged; only `-destination` differs**:

```bash
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS,name=<iPhone XS device name>' \
  RUN_SESSION_BENCHMARK=1 \
  -only-testing:RepTodayTests/SessionGenerationBenchmarkTests test
```

The results table is printed to the test log between `BENCH_BEGIN` and `BENCH_END`
(a Simulator-hosted bundle inherits no shell environment, so stdout is the transport):
`... test 2>&1 | sed -n '/BENCH_BEGIN/,/BENCH_END/p'`.

## 3. Proxy results (NON-AUTHORITATIVE - iOS Simulator on host Mac CPU)

> These are an **optimistic proxy** and **do not satisfy** the real-hardware requirement. The Simulator runs on the host
> Mac's CPU; a real iPhone (especially the iPhone XS) is slower. Do not cite these numbers to substantiate the claim.

- **Date captured:** 2026-08-10
- **Runtime:** iOS 18.3.1 Simulator (Build 22D8075), device profile iPhone 16
- **Host Mac CPU:** Intel(R) Core(TM) i9-10910 @ 3.60GHz, 64 GiB RAM
- **Toolchain:** Xcode 26.5 (17F42)
- **Iterations:** warm 2000/duration, cold 500/duration
- **Library load (decode + validate, one-time, outside timed region):** 0.49 ms

| lane | minutes | n | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- |
| cold | 5  | 500 | 0.4859 | 0.6230 | 1.0866 |
| cold | 10 | 500 | 0.5573 | 0.6930 | 1.1104 |
| cold | 15 | 500 | 1.7273 | 2.0415 | 2.5044 |
| cold | 20 | 500 | 1.7909 | 2.1727 | 2.7875 |
| cold | 30 | 500 | 1.8656 | 2.2074 | 2.6836 |
| cold | 45 | 500 | 2.0399 | 2.4553 | 2.8767 |
| cold | 60 | 500 | 2.2919 | 2.7714 | 3.2855 |
| warm | 5  | 2000 | 0.4817 | 0.6104 | 0.9633 |
| warm | 10 | 2000 | 0.5544 | 0.6565 | 1.0395 |
| warm | 15 | 2000 | 1.7242 | 2.1141 | 2.8386 |
| warm | 20 | 2000 | 1.7865 | 2.2247 | 3.0204 |
| warm | 30 | 2000 | 1.8582 | 2.2074 | 2.7144 |
| warm | 45 | 2000 | 2.0285 | 2.3719 | 3.0721 |
| warm | 60 | 2000 | 2.2818 | 2.6896 | 3.2590 |

First-in-process (single genuinely cold generation per duration, N=1 each, high variance): 5m 3.91, 10m 0.60, 15m 2.27,
20m 2.03, 30m 2.04, 45m 2.19, 60m 2.66 (ms). The largest single value observed anywhere in the run was ~3.9 ms.

**Worst-case p95 across the whole 5-60 range (proxy):** cold = **2.77 ms**, warm = **2.69 ms**, against a 100 ms budget.

## 4. PENDING - authoritative on-device run (the box only real hardware can check)

Fill this in by running the **same** harness on physical devices (change only `-destination`), then pull the printed
`BENCH_BEGIN..BENCH_END` table. The iPhone XS on iOS 17 is the gating device: iOS 17.0 is the minimum supported target
(`AGENTS.md`), and the iPhone XS is the slowest device that reaches it.

Do-this-exactly:

1. Install a Debug build on the device (`xcodebuild ... -destination 'platform=iOS,name=<device>'`); the harness needs no
   network and no Convex deployment - it times the engine call directly, so no `.env`/endpoint setup is required.
2. Run `RUN_SESSION_BENCHMARK=1 -only-testing:RepTodayTests/SessionGenerationBenchmarkTests test` (the benchmark is opt-in and skips without that flag).
3. Copy the printed p50/p95/max for cold and warm across 5-60 into the row below; record the device, iOS build, and date.
4. If any device's **p95 (cold or warm, any duration) >= 100 ms**, that is a **blocking finding**: change the number in
   every asset (site, video, screenshots, social, investor teaser) rather than ship an unsupported claim.

| Device | iOS | Cold p50 | Cold p95 | Cold max | Warm p50 | Warm p95 | Warm max | Date captured |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone XS (slowest supported - **gating**) | 17 | pending | **pending (blocking)** | pending | pending | pending | pending | pending |
| iPhone SE (2nd/3rd gen) | 17 | pending | pending | pending | pending | pending | pending | pending |
| iPhone 16 (or current flagship) | 17+ | pending | pending | pending | pending | pending | pending | pending |

Owner of the outstanding capture: whoever runs the pre-publication hardware pass. This file is the substantiation target
the checklist item points at.

## 5. Interpretation

**Proxy margin is very large.** Worst-case p95 across the whole range is ~2.8 ms cold / ~2.7 ms warm - roughly a **36x**
headroom under the 100 ms budget - and the single largest value observed anywhere was ~3.9 ms (~26x headroom). The two
lanes track each other closely, which is expected: the engine holds no per-generation cache, so "first generation on a
fresh engine" and "repeated generation" do near-identical work once the process is warm. Latency scales gently with
duration (5-10 min single-focus sessions are sub-millisecond; 60 min blend-extended sessions are ~2-3 ms), well within
budget across the whole surface, including the regeneration (warm) path the duration chip exercises.

**But this is not the on-device record, and margin on a proxy is not a substitute for it.** A real iPhone is slower than
this host, and the iPhone XS (A12, 2018) markedly so. A ~36x proxy margin makes it *likely* the device clears 100 ms even
after a large device-vs-Simulator slowdown, but "likely" is not "substantiated": only the iPhone XS p95 row above can check
the box. **Do not** publish the "under 100 ms" number on the strength of these Simulator figures.

**Not currently flagged at risk.** The proxy p95 is nowhere near the 100 ms limit, so - unlike the LOUD-flag case the task
calls for when a proxy sits near the budget - there is no evidence here that the claim is at risk. The only open item is
evidentiary (the real-hardware capture), not a suspected miss. If the on-device run ever lands a p95 within a small multiple
of 100 ms, treat that as the at-risk signal and escalate before publishing.

## Links

- Red-team checklist item this substantiates: `gtm/08-redteam/pre-publication-checklist.md` (line 17, "Device benchmark
  record for the 'under 100 milliseconds' claim") - remains **open** until the iPhone XS p95 row above is filled and passes.
- Design-only predecessor (device method, no numbers): `gtm/01-research/session-generation-benchmark.md`.
- The number's appearances in assets: `gtm/01-research/product-facts-brief.md` ("generated on-device, deterministically,
  offline, in under 100ms" and the duration-chip "regenerates the session in under 100ms").
- Harness: `ios/RepToday/RepTodayTests/SessionGenerationBenchmarkTests.swift`.

## Record metadata

- Record created: 2026-08-10 (re-runnable harness landed; proxy captured; on-device p95 outstanding).
- Re-run cost: ~30 s wall-clock on the proxy host for the full 5-60 sweep.
