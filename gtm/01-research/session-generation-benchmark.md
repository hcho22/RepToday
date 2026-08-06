# Session-generation benchmark - substantiation for the "under 100 milliseconds" claim

Substantiation record for the pre-publication checklist item
(`gtm/08-redteam/pre-publication-checklist.md`, "Device benchmark record for the 'under 100 milliseconds' claim")
and the acceptance criterion in US-T09 (`.claude/agent/tasks/prd-funnel-instrumentation_260803.md`).

The marketing number this record must either substantiate or force a change to appears in
`gtm/01-research/product-facts-brief.md` ("generated on-device, deterministically, offline, in under 100ms",
and the duration chip "regenerates the session in under 100ms") and, per the checklist, in the site,
video, screenshots, social, and investor teaser.

## Status: BLOCKED - p95 pending real-hardware capture (iPhone XS / iOS 17)

**This claim is not yet substantiated.**
The percentiles below cannot be produced in this engineering environment: the iOS **Simulator runs on the host Mac's CPU**,
so a Simulator generation time reflects Apple-silicon desktop performance, not the slowest supported iPhone, and is therefore
**not evidence for a device latency claim**.
The measurement code has landed and is Simulator-verified (US-T09); the on-device percentiles are an outstanding
blocking precondition, recorded here so the "under 100ms" number is flagged as **not-yet-substantiated** rather than
silently claimed.
Do not publish any asset carrying the "under 100ms" number until the p95 row for the slowest supported device is filled in
and passes.

This mirrors the recorded-precondition shape US-T07 (production Convex deployment, real-hardware live-wire transcript)
and US-T08 used for their real-hardware / live-deployment legs: land and Simulator-verify the code, record the
device/live leg as an explicit outstanding precondition.

## What US-T09 shipped (the measurement seam)

`generation_ms` is measured in `ReadyViewModel.generate()` as the whole-millisecond wall-time delta straddling the
`workoutEngine.generateWorkout(requestedMinutes:user:recentLogs:sessionPolicy:)` await **specifically** (not the
surrounding view work), read off the view model's injected `now` clock.
It is carried on the `ready_screen_shown` event (emitted once per Ready Screen open; see US-T09), so once a Debug build
runs against the dev Convex deployment on real hardware, the field itself is the raw data source for the distribution
below - the benchmark can be assembled from the `events` table rather than a bespoke harness.

## Devices to measure (must include the slowest supported)

| Device | iOS | Role |
| --- | --- | --- |
| iPhone XS | iOS 17 | **Slowest supported device - the p95 that gates the claim** |
| iPhone SE (2nd/3rd gen) | iOS 17 | Secondary low-end check |
| iPhone 16 (or current flagship) | iOS 17+ | Upper-bound / typical modern device |

Minimum supported target is iOS 17.0 (per `AGENTS.md`); the iPhone XS is the slowest device that reaches it, so it is the
one whose p95 the marketing number lives or dies by.

## Method

1. Debug build (`REPTODAY_ANALYTICS_ENDPOINT` = dev deployment `courteous-dogfish-560`) installed on each physical device.
2. **Cold** generation: first Ready Screen open after a fresh launch (app not in memory), which is the first
   `generateWorkout` of the process - the `ready_screen_shown` `generation_ms` captures exactly this.
3. **Warm** generation: repeated duration-chip taps within the same session (`ReadyViewModel.selectDuration`), each of which
   re-measures `generation_ms` on the same cached engine inputs. Collect many taps across the chip vocabulary
   (5/10/15/20/30/45/60) and across sessions so the sample spans the session-length range that changes the engine's work.
4. Sample size: >= 100 cold and >= 500 warm generations per device (enough to read a stable p95).
5. Pull the `generation_ms` distribution from the Convex `events` table (or a local log), and compute p50 / p90 / p95 / max
   per device, cold and warm separately.

## Results

_Pending real-hardware capture. Do not fill in with Simulator or estimated numbers._

| Device | iOS | Cold p50 | Cold p95 | Cold max | Warm p50 | Warm p95 | Warm max | Date captured |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone XS | 17 | pending | **pending (blocking)** | pending | pending | pending | pending | pending |
| iPhone SE | 17 | pending | pending | pending | pending | pending | pending | pending |
| iPhone 16 | 17+ | pending | pending | pending | pending | pending | pending | pending |

## Blocking finding

- **p95 pending real-hardware capture (iPhone XS / iOS 17).**
  Until the iPhone XS cold and warm p95 are measured on device and both land under 100ms, the "under 100 milliseconds"
  marketing claim is **unsubstantiated**.
  If the slowest supported device misses 100ms at p95, that is a blocking finding for the number: change it in every asset
  (site, video, screenshots, social, investor teaser) rather than ship an unsupported claim.

## Record metadata

- Record created: 2026-08-06 (measurement seam landed; percentiles outstanding).
- Owner of the outstanding capture: whoever runs the pre-publication hardware pass; this file is the substantiation target.
