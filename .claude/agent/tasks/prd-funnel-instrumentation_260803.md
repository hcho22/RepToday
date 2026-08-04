# PRD: Funnel Instrumentation - Anonymous Product Telemetry for the PMF Test

**Opened:** 2026-08-03
**Status:** In progress. US-T01 (transport spike) complete; its outcome re-scoped US-T03 and US-T04 (see the 2026-08-03 re-scope note under US-T03). US-T02 (event model, `AnalyticsService` seam, in-memory mock) complete - the seam only, with no emission call sites and no transport. US-T03 (Convex sink: one append-only `events` table, `logEvent`, `POST /logEvent` -> `204`) complete and validated live against dev deployment `courteous-dogfish-560` (`artifacts/reports/US-T03/validation.md`), then hardened in review with required-field checks on `installId`/`clientTs` and a `4xx`/`5xx` split that were type-checked but not re-run live; the sink exists but nothing emits into it yet. US-T04 onward not started.
**Transport decision (2026-08-03):** the US-T01 spike returned a no-go on `convex-swift` and the captain adopted it. The transport is now a Convex HTTP action (`POST /logEvent`) reached by a plain `URLSession` POST, with **no** new Swift Package dependency. Reason: `convex-swift` ships an arm64-only binary xcframework (no `x86_64` slice), which would make every Simulator-hosted test suite in this repo unbuildable on the captain's Intel host. iOS 17 was never the blocker. See `artifacts/reports/US-T01/spike-note.md`.
**Blocks:** The 90-day PMF evaluation against kill criteria K1-K8. Without this build, K1 (onboarding-to-first-session) and K4 (Weekly Active Exercisers) are unmeasurable, and K2/K3 are untrustworthy.
**Story prefix:** `US-T##` (T for telemetry). See "Story numbering" note below.
**Source of the events:** `gtm/06-channels/event-metric-schema.md` (pre-registered; event names and properties are carried over verbatim and must not be edited to move a threshold).
**Source of the gates:** `gtm/07-thesis/investment-thesis.md` (kill criteria K1-K8, the 200-user minimum-cohort rule, and the fixed week-8 / week-12 review dates).

---

## Introduction / Overview

Rep Today is a discipline-first micro-workout iOS app about to run a product-market-fit (PMF) test against pre-registered kill criteria K1-K8.
The captain has roughly 25 hours a week and a three-month evaluate-or-pivot deadline.
Launch is roughly 8 weeks out, so the checkpoint sits on about five weeks of live data.

**The app currently has zero product telemetry.**
This was verified directly against the iOS source: there is no Firebase, Amplitude, Mixpanel, PostHog, TelemetryDeck, Countly, or Segment anywhere in the tree, and no analytics service, event bus, or logging seam of any kind.
The only "analytics" symbol in the codebase is `Services/Progress/ProgressAnalytics.swift`, which is a pure computation struct that powers the user-facing Progress tab - it is not measurement.
The single third-party Swift Package dependency today is Lottie (`ios/RepToday/project.yml`); there is no other SDK.

Without instrumentation the 90-day review in the investment thesis cannot happen: K1 and K4 are unmeasurable at all, and K2/K3 (retention) are untrustworthy.
Only K5 (weekly installs) and most of K6/K7 (trials, conversions) come free from App Store Connect.

This feature adds the minimal, privacy-preserving, anonymous event pipeline that makes the funnel measurable from the first cohort.
It ships **ingest only** before launch: the app emits 13 pre-registered events to a dumb, append-only event sink, and nothing more.
All cohort and retention math is deliberately deferred to after launch, when real data exists to build it against.

The pipeline also does double duty on a marketing blocker.
One of the 13 events, `ready_screen_shown`, carries a `generation_ms` property that measures on-device session-generation latency.
That measurement is the substantiation record for the "under 100 milliseconds" marketing claim that `gtm/08-redteam/pre-publication-checklist.md` lists as blocking the site, the video, the screenshots, and the investor teaser.
One build clears two blockers.

### Story numbering - avoid a live collision

The existing implementation tracker `.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md` uses `US-A01` through `US-O04`.
A separate account-deletion PRD (`~/Mandu/projects/RepToday/01-prd-account-deletion_260731.md`) reuses `US-D01`-`US-D06`, which **collides** with the already-completed Epic D in that tracker.
To avoid a third collision, every story in this PRD uses the `US-T##` prefix and reuses no letter A through O.
The D-prefix collision is called out in Open Questions as something the captain should fix separately; this PRD does not touch it.

### Why opt-out, not opt-in (settled decision)

Telemetry is **on by default, opt-out**, disclosed in onboarding and the privacy policy, with one clearly-labelled toggle in Settings and zero emission when off.
The rationale is a sample-size argument, not a growth-hack:
at roughly 90 installs/week and a realistic ~30% opt-in acceptance rate, a single cohort would take 7+ weeks to reach the thesis's own 200-user minimum-cohort floor, so an opt-in default would leave the week-8 and week-12 checkpoints reading a tiny, self-selected sample.
The events are anonymous usage counts with no identity attached, so opt-out is a proportionate default for a measurement build whose entire purpose is a one-time PMF read.
Note: `~/Mandu/context/current-priorities.md` currently says "explicit opt-in"; this PRD deliberately overrides that line, and the override is flagged in Open Questions so the captain can reconcile the two documents.

### Why the privacy story is not violated

The shipped copy claims "Generated on your phone, offline, in under 100ms", "no account required", and "your history lives on your device, with optional sync to your own private iCloud".
Anonymous usage counts falsify none of those:
generation still happens on the phone, the app still needs no account, and the workout history still lives on-device with optional private-iCloud sync.
The events carry a random per-install identifier and small non-identifying property bags - never an email, never the IDFA, never the Sign in with Apple identifier.
The phrase "Nothing leaves the device" appears only in internal planning notes, not in any shipped asset, so no shipped promise is broken.

---

## Goals

- Make K1 (onboarding-to-first-session) and K4 (Weekly Active Exercisers) measurable at all, from the first cohort.
- Make K2 (D7 return) trustworthy by emitting a deduplicated, windowed return event rather than inferring retention after the fact.
- Emit all 13 pre-registered in-app events from `gtm/06-channels/event-metric-schema.md`, with their exact names and property lists, to a single append-only sink.
- Substantiate the sub-100ms marketing claim by recording `generation_ms` percentiles on real hardware, including the slowest supported device (iPhone XS on iOS 17).
- Keep the core loop strictly offline-first: telemetry is fire-and-forget and can never wait on, degrade for, or fail because of a network call.
- Keep the pipeline privacy-preserving: anonymous per-install identifier only, no identity, no IDFA, no ATT prompt, opt-out in one place, zero emission when off.
- Ship ingest only. Defer all cohort math, dashboards, and retention modelling to after launch, when real data exists.
- De-risk the transport with a throwaway spike before any app code is written. (Done: US-T01 investigated `convex-swift`, returned a no-go on it, and the adopted transport is now a Convex HTTP action reached by a plain `URLSession` POST - **no** new Swift Package dependency. See the transport-decision note above.)
- Prove the pipeline is trustworthy by reconciling what it reports for the moderated TestFlight cohort against what was actually observed and coded in the room.

---

## User Stories

> Stories are ordered dependency-first: de-risk the dependency, build the seam, wire the backend and the live sink, add the identity and consent foundation, then attach the 13 emissions, then reconcile against ground truth.
> Each story is scoped to one focused session.
>
> **iOS verification note:** this is a native iOS app, so UI-facing stories end their acceptance criteria with "Verify in the iOS Simulator via the `RepTodayUITests` scheme" (build and run the app in a booted Simulator and drive the touch path out of process), replacing the PRD skill's generic "Verify in browser using dev-browser skill" convention. Pure-logic and backend stories end with "Build and tests pass".
>
> As each story lands and its Validation Test passes, flip its acceptance-criteria checkboxes `[ ]` to `[x]` so this PRD doubles as a live progress tracker.

---

### US-T01: Spike - one event reaches the Convex dashboard on a throwaway branch

**Description:** As the developer, I want to prove that `convex-swift` can send one event to a Convex deployment and see it land in the dashboard, before writing any app code, so that the only unproven dependency is de-risked in a codebase that today carries almost no third-party dependencies.

**Acceptance Criteria:**

- [x] Work happens on a throwaway spike branch that is **never merged**; nothing from it lands in the app target.
- [x] A minimal Convex deployment exists with one table and one `logEvent` mutation (may be discarded after). (Scratch deployment `determined-vulture-542`, table `events`, mutation `logEvent`.)
- [x] The `get-convex/convex-swift` package is added to a throwaway Swift target (a command-line tool or a scratch app), the client connects, and one hand-crafted event is sent. **Partly, and this is the finding:** the package (`0.8.1`) was added and built cleanly against an iOS 17.0 deployment target, but its xcframework is arm64-only, so the Swift client **could not be run** on the captain's Intel host (no `x86_64` slice; Rosetta on Intel cannot run arm64). The event was therefore sent via an HTTPS POST and the Convex CLI mutation runner instead, which is exactly the evidence that drove the no-go. See the spike note.
- [x] The event is confirmed visible in the Convex dashboard for that deployment. **Verified equivalently, not via the web dashboard:** the dashboard sits behind an interactive OAuth sign-in and the spike was correctly forbidden from improvising a login, so the event was confirmed with an authenticated `npx convex data events` round-trip that reads the deployment's persisted rows and shows server-stamped `serverTs` timestamps - the same data the dashboard renders. No dashboard screenshot exists; a human with the Convex account can open the URL and see the two rows.
- [x] A one-page spike note is written to `artifacts/reports/US-T01/` recording: the package version pinned, the connection/auth shape, how a mutation is called from Swift, any iOS 17 deployment-target friction, and a go/no-go on `convex-swift`. (`artifacts/reports/US-T01/spike-note.md`.)
- [x] Time-box: roughly two hours. If it cannot connect in that window, stop and record the blocker in the spike note. (Completed inside the box with a decisive no-go.)

**Validation Test:**

- **Setup:** A Convex account and a scratch deployment. A throwaway git branch off the current default branch. Xcode 16.3.
- **Steps:**
  1. Create the scratch Convex deployment with one append-only table and one `logEvent` mutation.
  2. Add `convex-swift` to a throwaway Swift target and write ~20 lines that connect and call `logEvent` once with a fake event.
  3. Run it, then open the Convex dashboard data view for that deployment.
- **Expected Result:** Exactly one row appears in the dashboard table with the fields sent. The spike note captures the integration shape and a go/no-go.
- **Failure Indicator:** The client cannot connect or authenticate, the mutation is rejected, no row appears, or `convex-swift` does not build against an iOS 17 deployment target - any of which is a real finding that changes the transport decision before app code is written.

---

### US-T02: Define the event model, `AnalyticsService` protocol, and in-memory mock

**Description:** As the developer, I want a typed event value and an `AnalyticsService` seam with an in-memory mock, following the codebase's protocol + mock + live convention, so that every later story emits through one interface and tests can assert on emitted events with no network.

**Acceptance Criteria:**

- [x] A `Codable` value type (e.g. `AnalyticsEvent`) holds: the event name (a closed enum over the 13 event names), the millisecond timestamp, and a small string-keyed property bag (`[String: AnalyticsValue]` where `AnalyticsValue` is a closed union of the scalar types the schema uses - `Int`, `Double`, `String`, `Bool`).
- [x] The event name enum has exactly the 13 in-app cases from `gtm/06-channels/event-metric-schema.md`: `app_install`, `onboarding_started`, `onboarding_completed`, `ready_screen_shown`, `session_started`, `session_completed`, `session_abandoned`, `day7_return`, `day30_return`, `week_active`, `paywall_shown`, `trial_started`, `subscribe`. (The two web-side events `landing_page_view` and `waitlist_signup` are out of scope for the app build.)
- [x] `AnalyticsServiceProtocol` is declared in `Services/Protocols/ServiceProtocols.swift` alongside the existing service protocols. Its single emission method is `async throws` and is named to read as fire-and-forget at the call site (e.g. `func record(_ event: AnalyticsEvent) async`). - *shipped as `func record(_ event: AnalyticsEvent) async`, deliberately **not** `throws` - the criterion's two halves pulled against each other, and the parenthetical won: emission is strictly fire-and-forget, so a call site reads `await analytics.record(event)` with no `try`, and the live transport (US-T04) swallows every failure rather than surfacing it. This is the one departure from that file's `async throws` house style and is documented as such on the protocol, in `CLAUDE.md`, and in `README.md`.*
- [x] A `MockAnalyticsService` records every event into an in-memory array exposed for test assertions, performs no I/O, and never touches the network.
- [x] `analyticsService` is added as a property on `ServiceContainer` and wired in **both** `mock()` and `live(context:)` in `DI/ServiceContainer.swift` (live may temporarily point at the mock until US-T04 lands). - *live points at a `NoOpAnalyticsService` (`Services/Analytics/`) rather than the mock: the allowance was for an inert placeholder, but `MockAnalyticsService` is a recorder, so shipping it in production would grow an unbounded `recordedEvents` array the moment an emission story landed ahead of US-T04. The no-op carries the same "nothing leaves the process" guarantee with nothing retained.*
- [x] No emission call sites are added in this story - this is the seam only.
- [x] Uses `@Observable` only (never `ObservableObject`), all service methods `async`, `Theme` tokens where any UI appears (none here). Build and tests pass.

**Validation Test:**

- **Setup:** The app target builds. A new `AnalyticsServiceTests` file.
- **Steps:**
  1. Construct a `MockAnalyticsService`.
  2. Build three events (one per scalar-bag shape) and `record` each.
  3. Read back the mock's recorded array.
- **Expected Result:** The array holds exactly the three events in order, with names, timestamps, and property bags intact. `ServiceContainer.mock()` and `.live(context:)` both compile with the new property. No network call occurs.
- **Failure Indicator:** The enum is missing a case, the property bag cannot round-trip a scalar type, the container does not compile, or the mock performs any I/O.

---

### US-T03: Convex backend - one append-only table and one `logEvent` mutation

**Description:** As the developer, I want a single append-only Convex table, one `logEvent` mutation, and one `POST /logEvent` HTTP action in the repo's `convex/` placeholder, so that events have a dumb sink to land in - reachable over plain HTTPS so the client needs no Convex SDK - and analysis stays fully deferred and revisable.

> **Transport note (per the US-T01 spike, adopted 2026-08-03):** the HTTP action is what makes the no-SDK `URLSession` transport in US-T04 possible. It is not optional polish; it is the client's only entry point.

**Acceptance Criteria:**

- [x] The empty `convex/` placeholder (currently just `.gitkeep`) gains a real Convex project: a schema with **one** table (e.g. `events`) and **one** mutation, `logEvent`.
- [x] The `events` table stores: event name (string), install identifier (string), client timestamp (number, ms), server-received timestamp (number, ms, set by the mutation), and a JSON property bag (a Convex object/`any`).
- [x] `logEvent` is append-only: it inserts one row and returns. It performs **no** funnel modelling, no aggregation, no dedup, and no cohort math - the whole point is that analysis stays deferred.
- [x] Basic input validation only: the mutation rejects an unknown event name (a `v.union` of the 13 string literals, or an explicit check) and an oversized property bag, so a malformed client cannot poison the table, but it does nothing else.
- [x] A `convex/http.ts` HTTP action routes `POST /logEvent` and wraps the same `logEvent` mutation via `ctx.runMutation`, so the client reaches the sink over plain HTTPS with no Convex SDK. It reads the JSON body, coerces the scalar fields, calls `logEvent`, and returns `204` (the shape validated in US-T01). - *post-review hardening, still within "a malformed client cannot poison the table": the action requires `installId` and `clientTs` to be present and of the right kind before coercing them, because `String(undefined)` and `Number(undefined)` would otherwise have written the literal string `"undefined"` and `NaN` into the two columns K4 and K1 are computed from - a row that looks valid but is junk. Presence and kind only; no length, format, or shape constraint. `clientTs` still goes through `Number(...)`, so the pinned convention above is unchanged for any well-formed client. The action also separates a rejection it asked for (`400`, message carried) from a deployment or database failure (`5xx`, no detail echoed), since US-T04's client swallows every error and the status is the only signal a human watching the PMF test gets. Not re-validated live: see the superseded note in `artifacts/reports/US-T03/validation.md`.*
- [x] The numeric convention is pinned explicitly. Convex distinguishes `int64` from `float64` (a `v.number()` field rejects a Swift `Int` sent through the SDK - the `$integer` vs float64 trap the US-T01 spike documents), but the HTTP action coerces the top-level `clientTs` scalar with `Number(...)`, so that timestamp lands as `float64` regardless of how the client formats it. Declare that top-level numeric field `v.number()` to match. `generation_ms` is **not** a top-level scalar: it travels inside the `props` bag (the Convex `any`/object the action passes through untouched), so it is not reached by the top-level `Number(...)` coercion and is stored as-is.
- [x] A short `convex/README.md` documents the table shape, the mutation contract, the HTTP action (`POST /logEvent` -> `204`), and the explicit non-goal ("no analysis in the backend; the sink is dumb by design").
- [x] No app code changes in this story. Build and tests pass (Convex functions carry their own TypeScript checks; the iOS build is untouched).

**Validation Test:**

- **Setup:** The Convex CLI configured against a development deployment (may reuse the US-T01 scratch deployment or a fresh one).
- **Steps:**
  1. Deploy the schema, `logEvent`, and the `convex/http.ts` HTTP action.
  2. `POST` a valid event as JSON to `<deployment>.site/logEvent` (the transport US-T04 uses); confirm `204` and read the row back with `npx convex data events`.
  3. Call `logEvent` again with an unknown event name and with an oversized bag (via the function runner or a second POST).
- **Expected Result:** The valid POST returns `204` and inserts exactly one row with both timestamps populated. The invalid calls are rejected without inserting. The table has no indexes or logic beyond append.
- **Failure Indicator:** The mutation aggregates or transforms data, accepts an unknown event name, the HTTP action fails to reach the mutation, or the schema carries funnel/cohort structure.

---

### US-T04: Live Convex-backed `AnalyticsService` - fire-and-forget transport

**Description:** As the developer, I want a `LiveAnalyticsService` that sends events to Convex over a plain `URLSession` POST in a strictly fire-and-forget way, wired into `live(context:)`, so that real builds emit anonymous events without the core loop ever waiting on or failing because of the network - and with no new Swift Package dependency.

> **Transport re-scope (US-T01 spike, adopted 2026-08-03):** this story previously mandated adding `get-convex/convex-swift` to `ios/RepToday/project.yml`. That is dropped. The US-T01 spike returned a no-go (`convex-swift` ships an arm64-only xcframework, which breaks every Simulator-hosted test suite on the captain's Intel host) and the captain adopted it. `LiveAnalyticsService` now posts JSON to the deployment's `.site/logEvent` HTTP action (US-T03) with `URLSession`. Lottie stays the app's only third-party package.

> **Wire-shape note (US-T02):** `AnalyticsValue`'s `Codable` form is deliberately tagged (`{"type":...,"value":...}`) so `Int` and `Double` round-trip losslessly in process - that is a US-T02 requirement and stays. It is **not** the wire shape: US-T04 must flatten the property bag on the way out so the Convex sink stores plain scalars (e.g. `"props": {"generation_ms": 38}`), matching the rows the US-T01 spike persisted and US-T03's "stored as-is".

**Acceptance Criteria:**

- [ ] `LiveAnalyticsService` conforms to `AnalyticsServiceProtocol`, encodes an `AnalyticsEvent` as JSON, and `POST`s it to the deployment's `.site/logEvent` HTTP action with `URLSession`. No Convex SDK is used. The property bag is flattened to plain scalars for the wire (see the wire-shape note above), so `props` holds numbers, strings, and booleans rather than `AnalyticsValue`'s tagged in-process form.
- [ ] **No new Swift Package dependency is added.** `ios/RepToday/project.yml` still lists Lottie as the only third-party package; `convex-swift` is **not** added. Only the deployment `.site` URL is new config (a build setting or plist value), alongside the install id from US-T05 and the opt-out flag from US-T06.
- [ ] Emission is **strictly fire-and-forget**: `record(_:)` returns immediately, the send happens on a detached/background task (`Task.detached`), and no caller ever awaits network completion. A failed, slow, or offline send is swallowed (`try?`, best-effort), exactly like every other integration in this app (HealthKit, CloudKit, StoreKit observation).
- [ ] The core loop is never blocked, degraded, or failed by telemetry: verified by the offline validation test below.
- [ ] `live(context:)` in `DI/ServiceContainer.swift` swaps the temporary `NoOpAnalyticsService` for `LiveAnalyticsService`; `mock()` keeps `MockAnalyticsService`. The environment/injection path (`@Environment(\.services)`) is unchanged.
- [ ] Events carry the anonymous install identifier from US-T05 and honour the opt-out flag from US-T06 (integration wired here; the identifier and flag land in those stories - order T05/T06 before T04's final wiring, or stub then connect).
- [ ] The `POST /logEvent` HTTP action bounds `installId`'s length. US-T03 shipped it as an unbounded `v.string()` - reviewed and consciously accepted there, because nothing was sending it yet - which leaves it the one client-controlled field with no ceiling while `props` is capped at 32 keys / 4096 UTF-8 bytes, so a hostile client could write rows up to Convex's ~1MB document limit through it. The bound belongs in the story that first puts a real identifier on the wire: a short cap sized for US-T05's UUIDv4, rejected with the same `400`-and-no-insert as the sink's other rejections, and no format or UUID-shape check beyond it.
- [ ] Build and tests pass; no test run performs a real network call. Unit tests either use `MockAnalyticsService` or exercise `LiveAnalyticsService` through a `URLProtocol` stub that intercepts the request in-process (asserting the URL, method, and JSON body without touching the network), so FR-13 holds with no live call.

**Validation Test:**

- **Setup:** A Debug build on an iPhone 16 Simulator, pointed at a development Convex deployment. Airplane mode toggle available.
- **Steps:**
  1. Launch the app online; complete onboarding and start a session.
  2. Confirm events land in the Convex dashboard.
  3. Put the Simulator/device offline (airplane mode), repeat the same flow, and time the core interactions.
- **Expected Result:** Online, events appear in Convex. Offline, the app behaves identically with no perceptible delay - session generation, start, and completion are unaffected - and no error surfaces to the user. When connectivity returns, new events resume (queued events are best-effort; loss of a few offline events is acceptable and expected).
- **Failure Indicator:** Any core interaction blocks, spins, stalls, or shows an error while offline; the app awaits a network round-trip on the start path; or a telemetry failure propagates into the loop.

---

### US-T05: Anonymous per-install identifier and first-launch timestamps

**Description:** As the developer, I want a random per-install identifier and first-launch / last-active timestamps persisted locally, so that events can be cohorted by install week and return events can be computed - with no identity attached.

**Acceptance Criteria:**

- [ ] A random UUIDv4 install identifier is generated once, on first launch, and stored in `UserDefaults` (so it dies with the app on uninstall and is truly per-install). It is **never** derived from the IDFA, `identifierForVendor`, the Sign in with Apple identifier, email, or any Keychain-persisted value, and it is never stored in the Keychain (which would survive reinstall and resurrect a "deleted" identity - the exact failure mode flagged in the account-deletion PRD).
- [ ] A `firstLaunchAt` timestamp and a `lastActiveAt` timestamp are added as `UserDefaults` keys. `AppState` (`Utilities/AppState.swift`) is the natural home: it is already the `UserDefaults`-backed app-state object, though it holds only `isOnboarded` and `selectedTab` today - these three values (`installId`, `firstLaunchAt`, `lastActiveAt`) are net-new and must be added, because no first-launch timestamp exists in the codebase yet.
- [ ] `install_week` is derived from `firstLaunchAt` using the existing `ConsistencyScore.startOfWeek(...)` helper (reused, not re-implemented), and is coarse (a week-start date), never a precise install time.
- [ ] The identifier and timestamps read/write through injected values, not the wall clock read inline, consistent with the codebase rule that pure logic takes an injected `asOf` clock.
- [ ] Uses `@Observable` only. Build and tests pass.

**Validation Test:**

- **Setup:** A fresh Simulator install (delete the app first so `UserDefaults` is clean).
- **Steps:**
  1. Launch the app for the first time; read the persisted `installId`, `firstLaunchAt`, and `lastActiveAt`.
  2. Force-quit and relaunch; read them again.
  3. Delete and reinstall the app; read them a third time.
- **Expected Result:** First launch sets all three. Relaunch preserves the same `installId` and `firstLaunchAt` and updates `lastActiveAt`. Reinstall produces a **new** `installId` and a **new** `firstLaunchAt` (nothing survived the uninstall). `install_week` matches `ConsistencyScore.startOfWeek(firstLaunchAt)`.
- **Failure Indicator:** The identifier is empty, is the same across a reinstall (i.e. persisted in Keychain), is derived from a device or account identifier, or `firstLaunchAt` is missing.

---

### US-T06: Opt-out consent flag, Settings toggle, and onboarding disclosure

**Description:** As a user, I want telemetry on by default with a clearly-labelled way to turn it off, and to be told about it during onboarding, so that my choice is respected and no events are emitted when I opt out.

**Acceptance Criteria:**

- [ ] A single `analyticsEnabled` boolean, default `true`, persisted in `UserDefaults` (alongside the US-T05 keys), gates **all** emission: when `false`, `LiveAnalyticsService` emits nothing (zero network calls) and drops events silently.
- [ ] A clearly-labelled toggle ("Share anonymous usage data" or similar, using `Theme` tokens) lets the user turn telemetry off and back on. **Note:** the Profile tab is currently a placeholder (`RootView.PlaceholderTabView`) with no Settings surface, so this story either introduces a minimal Settings surface reachable from Profile or documents where the toggle lands - see Open Questions; it must be reachable, not buried.
- [ ] Onboarding discloses the anonymous-usage-data collection in one plain sentence with a link to the privacy policy, consistent with the opt-out-with-disclosure decision.
- [ ] Copy is identity-framed and honest ("anonymous usage data helps us see whether Rep Today is working"), never dark-patterned, and the toggle reflects the real current state.
- [ ] Turning the toggle off is honoured immediately by the live service without an app restart.
- [ ] Verify in the iOS Simulator via the `RepTodayUITests` scheme. Build and tests pass.

**Validation Test:**

- **Setup:** A Debug build pointed at a development Convex deployment, with the Convex dashboard open.
- **Steps:**
  1. Complete onboarding and confirm the disclosure sentence and privacy-policy link were shown.
  2. With telemetry on (default), start a session and confirm events land in Convex.
  3. Open Settings, toggle telemetry off.
  4. Repeat the session flow.
- **Expected Result:** The disclosure appears in onboarding. With the toggle on, events land. With the toggle off, **no** new rows appear in Convex for that install and the app behaves identically. Toggling back on resumes emission without a restart.
- **Failure Indicator:** Any event lands while the toggle is off; the toggle is unreachable or unlabelled; the disclosure is missing from onboarding; or the change requires an app restart.

---

### US-T07: Emit `app_install`, `day7_return`, `day30_return` at app entry

**Description:** As the developer, I want the install and return events emitted from the app entry point, gated on the first-launch timestamp, so that the retention denominators (D7, D30, WAE, free-to-paid) and K2/K3/K5 have their base cohort marker.

**Acceptance Criteria:**

- [ ] `app_install` is emitted exactly once, the first time the app is ever opened (when `firstLaunchAt` is being set for the first time), carrying `install_week` (coarse week-start from US-T05). Emission hook: `RepTodayApp.init()` or `AppState.init(userDefaults:)`, where first-launch is detected.
- [ ] `day7_return` is emitted at most once, on any open during days 7-13 after `firstLaunchAt` (the 7-day window is the schema's stated instrumentation convention). A per-event "already emitted" flag in `UserDefaults` enforces emit-once.
- [ ] `day30_return` is emitted at most once, on any open during days 30-36 after `firstLaunchAt`, with the same emit-once dedup.
- [ ] Neither return event carries properties (per schema); `app_install` carries only `install_week`.
- [ ] The window and dedup logic take an injected clock (never a raw `Date()` read inline), so the behaviour is deterministic under test.
- [ ] Build and tests pass (this is app-lifecycle logic; the Simulator exercises the happy path but window logic is unit-tested against an injected clock).

**Validation Test:**

- **Setup:** `AppInstallEventTests` with an injected clock and a clean `UserDefaults`.
- **Steps:**
  1. Simulate a first launch; assert `app_install` with the correct `install_week`.
  2. Advance the injected clock to day 3, day 8, day 12, day 20, day 33, and day 40, launching at each; capture emitted events.
  3. Launch twice within the day 7-13 window and twice within the day 30-36 window.
- **Expected Result:** `app_install` fires once at first launch. `day7_return` fires once, on the first open inside days 7-13, and never again. `day30_return` fires once, on the first open inside days 30-36. No return event fires outside its window (day 3, day 20, day 40 produce none).
- **Failure Indicator:** A return event fires more than once, fires outside its window, `app_install` fires on a later launch, or `install_week` is a precise timestamp rather than a coarse week-start.

---

### US-T08: Emit `onboarding_started` and `onboarding_completed`

**Description:** As the developer, I want the onboarding funnel endpoints emitted, so that K1 (onboarding-to-first-session) has its numerator base and its completion timing.

**Acceptance Criteria:**

- [ ] `onboarding_started` is emitted once when the first onboarding screen is shown. `OnboardingView.body` has no `.onAppear`/`.task` today, so one is added (a one-shot) as the emission hook; it carries no properties (per schema).
- [ ] `onboarding_completed` is emitted from `OnboardingViewModel.finish()`, in the success branch just before it returns `true` (after the user is saved and the cold-start policy seeded), carrying `elapsed_seconds` (whole seconds from onboarding start to finish).
- [ ] `elapsed_seconds` is computed from an injected clock captured at `onboarding_started`, not from a wall-clock read at completion.
- [ ] Emission is fire-and-forget through the injected `analyticsService`; a telemetry failure never blocks the onboarding-to-main-tabs transition (`onComplete` still flips `AppState.isOnboarded`).
- [ ] Verify in the iOS Simulator via the `RepTodayUITests` scheme. Build and tests pass.

**Validation Test:**

- **Setup:** A Debug build with the mock analytics service (for the unit assertion) and, separately, the live service against a dev deployment (for the Simulator run).
- **Steps:**
  1. In a unit test, drive the onboarding view model from first screen to `finish()` with an injected clock advanced by a known interval.
  2. In the Simulator, complete onboarding end to end and watch the Convex dashboard.
- **Expected Result:** Exactly one `onboarding_started` (no properties) and exactly one `onboarding_completed` with `elapsed_seconds` equal to the injected interval. In the Simulator both events land and the app reaches the main tabs regardless of telemetry outcome.
- **Failure Indicator:** Either event fires more than once or not at all, `elapsed_seconds` is wrong or missing, or a telemetry failure stalls the transition into the app.

---

### US-T09: Emit `ready_screen_shown` with `generation_ms` (and substantiate the sub-100ms claim)

**Description:** As the developer, I want the Ready Screen render emitted with the measured session-generation time, so that K8's wedge check has its latency signal and the "under 100 milliseconds" marketing claim gets its substantiation record on real hardware.

**Acceptance Criteria:**

- [ ] `generation_ms` is measured as the wall-time delta around the engine call in `ReadyViewModel.generate()` (the `workoutEngine.generateWorkout(requestedMinutes:user:recentLogs:sessionPolicy:)` await), which is untimed today. The measurement is planning-honest: it wraps the generation call specifically, not unrelated view work.
- [ ] `ready_screen_shown` is emitted once per Ready Screen appearance (scoped to the first load, using a one-shot flag in the same style as the view model's existing `hasComputedConsistency` / `hasSeededSelection` guards), carrying `generation_ms`.
- [ ] Re-generations from duration-chip taps do not each re-emit `ready_screen_shown` (that would inflate the count); the property is still measured on those paths for internal debugging but only the first-load render emits the event. (If the schema's intent is one emission per generation, resolve in Open Questions before implementing - default here is one per Ready Screen open.)
- [ ] A device benchmark record is produced under `01-research/` (per `gtm/08-redteam/pre-publication-checklist.md`): cold and warm `generation_ms` percentiles (including p95) measured on real hardware including the slowest supported device (iPhone XS on iOS 17), with device list, method, and date. If the slowest device misses 100ms, that is a blocking finding for the marketing number, recorded as such.
- [ ] Verify in the iOS Simulator via the `RepTodayUITests` scheme (for emission); the benchmark percentiles require real hardware and are captured separately.
- [ ] Build and tests pass.

**Validation Test:**

- **Setup:** A Debug build against a dev Convex deployment, plus at least one physical device including an iPhone XS on iOS 17 for the benchmark.
- **Steps:**
  1. In the Simulator, open the app to the Ready Screen and confirm exactly one `ready_screen_shown` with a plausible `generation_ms`.
  2. Tap several duration chips; confirm `ready_screen_shown` does **not** re-fire per tap.
  3. On the iPhone XS, generate many sessions (cold and warm) and record the `generation_ms` distribution into the substantiation file.
- **Expected Result:** One `ready_screen_shown` per Ready Screen open, carrying a real measured `generation_ms`. The benchmark file records p95 on the slowest device with method and date; the marketing claim is either substantiated or flagged for change.
- **Failure Indicator:** `generation_ms` is zero, hard-coded, or measures the wrong span; the event re-fires on every chip tap; or no benchmark record is produced for the slowest supported device.

---

### US-T10: Emit `session_started`, `session_completed`, `session_abandoned`

**Description:** As the developer, I want the session lifecycle events emitted, so that session-completion rate (>=80% target), WAE, and the Re-entry Ramp signal are measurable, and abandonment is diagnosable.

**Acceptance Criteria:**

- [ ] `session_started` is emitted from `ActiveSessionViewModel.start()` (already idempotent via `guard startedAt == nil`), carrying `requested_minutes`.
- [ ] `session_completed` is emitted from the single finishing transition `ActiveSessionViewModel.finish()`, carrying `requested_minutes`, `completed_minutes`, `was_return`, and `perceived_difficulty` - all already available on the completion log built there (`WorkoutLog.requestedMinutes`, `durationMinutes`, `wasReturn`, `perceivedDifficulty`).
- [ ] `session_abandoned` is emitted when the player is dismissed before completion. There is **no** abandonment method today: abandonment is implicit, surfaced through `ActiveSessionView.close()` (which captures `completed = viewModel.isComplete`) and `ReadyViewModel.handlePlayerDismiss(completed:)` (the `completed == false` branch). Emit at that dismiss-with-`completed == false` point, carrying `completed_minutes` and `abandon_point`.
- [ ] `abandon_point` is a new **small closed enum** (per the schema's stated convention that `abandon_point`/`entry_point` are small non-identifying enums), derived from the player's progress at dismissal (e.g. `warmup` / `mainWork` / `cooldown`, computed from `currentStepIndex` / `progress`). It carries no free text.
- [ ] Exactly one lifecycle event fires per session outcome: a completed session emits `started` then `completed` and never `abandoned`; an abandoned session emits `started` then `abandoned` and never `completed`.
- [ ] Verify in the iOS Simulator via the `RepTodayUITests` scheme. Build and tests pass.

**Validation Test:**

- **Setup:** A Debug build against a dev Convex deployment.
- **Steps:**
  1. Generate and start a session; complete it fully; observe events.
  2. Generate and start a second session; exit it partway through (during main work); observe events.
- **Expected Result:** Session one: `session_started` (with `requested_minutes`) then `session_completed` (with all four properties, `was_return` correct, `perceived_difficulty` matching the rating given). Session two: `session_started` then `session_abandoned` with `completed_minutes` and an `abandon_point` of `mainWork`; no `session_completed`. No double emission.
- **Failure Indicator:** Both `completed` and `abandoned` fire for one session, `abandon_point` is free text or wrong, `was_return`/`perceived_difficulty` are missing or incorrect, or a lifecycle event double-fires.

---

### US-T11: Emit `week_active` by reusing the existing weekly rollup

**Description:** As the developer, I want the first completed session of each calendar week emitted once, reusing the weekly rollup that `ProgressAnalytics` already computes, so that the North Star (Weekly Active Exercisers) and K4 are measurable without recomputing week bucketing.

**Acceptance Criteria:**

- [ ] `week_active` is emitted at most once per distinct calendar week that contains at least one completed session, carrying no properties (per schema).
- [ ] The week bucketing **reuses** the existing rollup rather than re-deriving it: `ProgressAnalytics` already computes a `[Date: Int] sessionsByWeek` keyed by `ConsistencyScore.startOfWeek(log.completedAt, calendar)` (in `makePersonalBests`), whose keyset is exactly the set of active week-starts. The emission logic keys off that same week-start, not a fresh calendar calculation.
- [ ] Because `ProgressAnalytics` is a pure computation struct with no emission side, the event is emitted from a caller that has both the new log and the analytics service - the natural site is the session-completion path (`SessionCompletionService.recordCompletedSession`) diffing whether the just-completed session opened a previously-empty week bucket. The chosen site is documented in the story's implementation note.
- [ ] Emit-once per week is enforced by a persisted set of already-emitted week-start dates (e.g. in `UserDefaults`), so a second session in the same week does not re-emit.
- [ ] The emission takes an injected clock/calendar consistent with `ConsistencyScore`'s existing conventions.
- [ ] Build and tests pass.

**Validation Test:**

- **Setup:** `WeekActiveEventTests` with an injected clock/calendar and a controllable log history.
- **Steps:**
  1. Record one completed session in week W; assert one `week_active`.
  2. Record a second completed session in the same week W; assert no new `week_active`.
  3. Advance the clock into week W+1 and record a completed session; assert one new `week_active`.
- **Expected Result:** Exactly one `week_active` per distinct active week, keyed off the same `ConsistencyScore.startOfWeek` bucketing `ProgressAnalytics` uses. Multiple sessions in one week emit it once.
- **Failure Indicator:** `week_active` fires per session instead of per week, uses a different week definition than `ProgressAnalytics`, re-derives bucketing instead of reusing the existing rollup, or double-emits within a week.

---

### US-T12: Emit `paywall_shown`, `trial_started`, `subscribe`

**Description:** As the developer, I want the monetization funnel events emitted, so that K6 (trial starts) and K7 (free-to-paid) have their base and conversion signals from the first cohort.

**Acceptance Criteria:**

- [ ] `paywall_shown` is emitted when the paywall renders (`PaywallView.body`'s `.task`/`PaywallViewModel.load()`), carrying `entry_point`.
- [ ] `entry_point` is a new **small closed enum** (per the schema's convention). Today the only presentation path is the Progress-tab premium upsell (`ProgressTabView`'s `PremiumUpsellCard`), so the enum starts with that case (e.g. `progressUpsell`) and is extended as new entry points appear - never free text.
- [ ] `subscribe` is emitted when a purchase succeeds, carrying `plan` (the plan id / period). The success site is `PaywallViewModel.purchase(_:)`'s resolved branch (or `StoreKitSubscriptionService.purchase(_:)`'s `.success`); emit at one of those, with `plan` from the `SubscriptionPlan` argument.
- [ ] `trial_started` is emitted when the purchased subscription is a trial. There is no distinct trial hook; trial-ness is derived from the resolved `Subscription.trialEndsAt != nil`. At the same success site, branch: a trial-bearing subscription emits `trial_started` (no properties) and a direct/converted paid subscription emits `subscribe` (with `plan`). (Clarify in Open Questions whether a trial that later converts should also emit `subscribe` at conversion; default here follows the schema's "trial converts or direct" note for `subscribe`.)
- [ ] These paths are entitlement-gated and only build for device; they verify only on real hardware, never in the Simulator (StoreKit 2 live purchases). The Simulator run uses the `.storekit` test configuration where possible.
- [ ] Verify on device (or via the StoreKit test configuration) rather than the plain Simulator. Build and tests pass.

**Validation Test:**

- **Setup:** A build with the StoreKit test configuration (`.storekit`) or a sandbox account on device, against a dev Convex deployment.
- **Steps:**
  1. Open the paywall from the Progress-tab upsell; observe `paywall_shown` with `entry_point = progressUpsell`.
  2. Purchase a trial-bearing plan; observe events.
  3. Purchase (or simulate) a direct paid plan; observe events.
- **Expected Result:** `paywall_shown` fires on render with the correct `entry_point`. A trial purchase emits `trial_started`; a direct paid purchase emits `subscribe` with the correct `plan`. No event fires on a cancelled or failed purchase.
- **Failure Indicator:** `paywall_shown` misses or double-fires, `entry_point`/`plan` are free text or wrong, `trial_started` fires for a non-trial purchase (or vice versa), or a cancelled purchase emits `subscribe`.

---

### US-T13: Ground-truth reconciliation against the moderated TestFlight cohort

**Description:** As the captain, I want the pipeline's numbers for the moderated TestFlight cohort reconciled against what was actually observed and coded in the room, so that a self-built sink is proven trustworthy before any funnel number it produces is believed.

**Acceptance Criteria:**

- [ ] After the moderated TestFlight cohort has run (the ~25 observed first runs used for K8), the events the pipeline recorded for those installs are pulled from Convex and tabulated per install.
- [ ] For each observed session, the pipeline's record (installed, onboarding started/completed, ready shown, session started/completed/abandoned, paywall/trial/subscribe) is compared line by line against what the non-founder coder actually observed and coded from the recordings.
- [ ] A reconciliation report is written to `artifacts/reports/US-T13/` listing every disagreement between the pipeline and the room, with a root cause for each (missed emission, double emission, wrong property, clock/window bug, opt-out interaction, etc.).
- [ ] Every disagreement is either fixed (with a follow-up story) or explicitly accepted with a written reason; the funnel is not trusted until the pipeline and the recordings agree for the cohort.
- [ ] The report states plainly that this ground-truth check is what makes a self-built sink an acceptable risk: for 25 installs the truth is independently known, so the pipeline can be validated against it before it is used on thousands of installs whose truth is not otherwise observable.
- [ ] This is a QA/verification story: no shipping app code beyond fixes surfaced by the reconciliation.

**Validation Test:**

- **Setup:** A completed moderated TestFlight cohort with recordings coded by the named non-founder coder (per K8), and the Convex `events` table populated for those installs.
- **Steps:**
  1. Export the events for the cohort's install identifiers from Convex.
  2. Build the per-install funnel and place it next to the coder's observation log.
  3. Diff them event by event; record every mismatch and its cause.
- **Expected Result:** The pipeline's funnel matches the observed sessions within a documented, understood tolerance; every mismatch has a named cause and a fix or an accepted-reason. The report concludes whether the pipeline is trustworthy.
- **Failure Indicator:** The pipeline and the recordings disagree in ways with no identified cause - which means no number the pipeline later produces for the real cohort can be trusted, and the reconciliation must not be marked passing.

---

### US-T14: Protect the public `POST /logEvent` HTTP action against abuse

**Description:** As the developer, I want the public, unauthenticated `POST /logEvent` HTTP action guarded against casual abuse, so that a stranger who discovers the endpoint URL cannot flood the `events` table with junk rows.
This story **depends on US-T03** (the HTTP action must exist before it can be guarded), plus **US-T05** (which generates the per-install identifier) and **US-T04** (which actually carries that identifier in the request body); without both, the primary rate-limit key does not exist at the endpoint.
So US-T14's per-install rate-limit key only exists once US-T05 and US-T04 have landed, and it sequences after them; if US-T14 is built earlier, it runs on the source-IP backstop alone, which the story already treats as the weaker secondary key.
It must land **before launch**, not after: the checkpoint reads kill criteria off this table, so the protection has to be in place the moment the endpoint is internet-reachable with real installs behind it, and sequencing later does not make it optional.
The `events` table is the evidence base for K1, K2, and K4.
Junk rows injected by anyone who finds the endpoint would inflate installs, sessions, and weekly-active counts, so the captain would be reading kill criteria off poisoned data at the checkpoint; wasted Convex quota and billing is a secondary cost.
This story adds **no** user accounts, no per-user authentication, no App Tracking Transparency prompt, and no identity in events - those remain hard non-goals and this story must not weaken them.

**Acceptance Criteria:**

- [ ] A shared secret is embedded in the client build and sent with each `POST /logEvent` request (e.g. a header); the HTTP action rejects any request that does not carry the expected secret with a non-`204` status and no insert.
- [ ] The criteria state honestly that a client-embedded secret is extractable from the app binary and therefore **raises the cost** of abuse rather than preventing it: it stops opportunistic flooding of a freshly-discovered URL, not a determined attacker who unpacks the app.
- [ ] Rate limiting is applied in the HTTP action, keyed on the per-install identifier carried in the request, with the coarse request source IP as a backstop; the shared secret is never used as a rate-limit key, because every client build embeds the same secret so keying on it would collapse the whole user base into one global bucket and throttle legitimate telemetry while stopping nothing.
- [ ] A single per-install identifier (or, on the IP backstop, a single source) cannot insert more than a sane ceiling of rows in a window; requests over the ceiling are rejected without inserting.
- [ ] The criteria state honestly that the per-install identifier is generated by the client itself and can be rotated freely, so an abuser can mint unlimited fresh ones: keying on it stops accidental floods and casual abuse, not a determined attacker, and the request source IP is the only key the client does not control - and even that is weakened by proxies and shared egress.
- [ ] The rate-limit counter state lives in exactly one of two shapes: either a dedicated helper table holding only ephemeral per-key counters (the per-install identifier or request source IP, plus a time window) and nothing else, or Convex's official rate-limiter component; the counter store is separate from the `events` table, carries no identity, accumulates no history, is read only by the throttle check, and is not part of the K1/K2/K4 evidence base.
- [ ] The secret check and rate limiting run **before** the `logEvent` mutation is called, so a rejected request never writes a row.
- [ ] The guard introduces no user accounts, no per-user auth, no ATT prompt, and no identity in events; the row shape from US-T03 is unchanged (event name, install id, client timestamp, server timestamp, property bag).
- [ ] The `convex/README.md` documents the shared-secret check and the rate-limit ceiling, and states plainly that the secret is a cost-raiser, not a guarantee.
- [ ] Build and tests pass (this is backend and pure-logic work; the mutation and validation stay covered by their own TypeScript checks).

**Validation Test:**

- **Setup:** The US-T03 backend deployed to a development deployment, with the shared secret configured.
- **Steps:**
  1. `POST` a valid event **with** the correct shared secret; confirm `204` and one inserted row.
  2. `POST` a valid event **without** the secret (or with a wrong one); confirm rejection and **no** inserted row.
  3. `POST` past the rate-limit ceiling from a single per-install identifier (or, exercising the backstop, from one source IP) in a short window; confirm the over-ceiling requests are rejected without inserting.
- **Expected Result:** Only secret-bearing requests under the ceiling insert rows; missing/wrong-secret and over-ceiling requests are rejected with no insert. No user identity is introduced anywhere in the path. Build and tests pass.
- **Failure Indicator:** A secretless or over-ceiling request inserts a row; the check runs after the mutation writes; the guard introduces user accounts, per-user auth, an ATT prompt, or identity into events; or the row shape changes.

---

## Functional Requirements

- **FR-1:** The app must emit the 13 pre-registered in-app events from `gtm/06-channels/event-metric-schema.md`, using their exact names and property lists, and no others: `app_install`, `onboarding_started`, `onboarding_completed`, `ready_screen_shown`, `session_started`, `session_completed`, `session_abandoned`, `day7_return`, `day30_return`, `week_active`, `paywall_shown`, `trial_started`, `subscribe`.
- **FR-2:** Each event's properties must match the schema exactly: `app_install` -> `install_week`; `onboarding_completed` -> `elapsed_seconds`; `ready_screen_shown` -> `generation_ms`; `session_started` -> `requested_minutes`; `session_completed` -> `requested_minutes`, `completed_minutes`, `was_return`, `perceived_difficulty`; `session_abandoned` -> `completed_minutes`, `abandon_point`; `paywall_shown` -> `entry_point`; `subscribe` -> `plan`; the remaining events carry no properties.
- **FR-3:** Emission must go through a single `AnalyticsServiceProtocol` seam declared in `Services/Protocols/ServiceProtocols.swift`, with a `MockAnalyticsService` (records to an in-memory array, no I/O) and a `LiveAnalyticsService` (Convex-backed), both registered in `DI/ServiceContainer.swift` (`mock()` and `live(context:)`) and reached via `@Environment(\.services)`.
- **FR-4:** Emission must be strictly fire-and-forget: `record(_:)` returns immediately, sending happens off the calling path, and no core-loop interaction ever waits on, degrades for, or fails because of a telemetry call. Offline behaviour must be identical to online behaviour for the user.
- **FR-5:** Each event must carry a random per-install identifier (UUIDv4 in `UserDefaults`, never Keychain, never derived from IDFA / `identifierForVendor` / Sign in with Apple / email), the client timestamp, and its property bag. No user-level identity may appear in any event.
- **FR-6:** The Convex backend must be one append-only `events` table plus one `logEvent` mutation that inserts and returns, with input validation only and no aggregation, dedup, or cohort math. It must also expose a `POST /logEvent` HTTP action (`convex/http.ts`) that wraps that same mutation, so the app reaches the sink over plain HTTPS with no Convex SDK (the transport adopted after the US-T01 spike). US-T14's abuse guard may add a small rate-limit counter store in exactly one of two shapes - either a dedicated helper table holding only ephemeral per-key counters (the per-install identifier or request source IP, plus a time window) and nothing else, or Convex's official rate-limiter component - but that counter store is separate from the `events` table, carries no identity, accumulates no history, is read only by the throttle check, and is never an evidence surface; the `events` table itself stays single, append-only, and dumb.
- **FR-7:** Telemetry must be opt-out: on by default, disclosed in onboarding and the privacy policy, controlled by one clearly-labelled Settings toggle, and must emit **zero** events (zero network calls) when off.
- **FR-8:** `app_install` must fire exactly once at first launch; `day7_return` and `day30_return` must each fire at most once, within days 7-13 and 30-36 of `firstLaunchAt` respectively; `week_active` must fire at most once per active calendar week. All dedup and windowing must be deterministic under an injected clock.
- **FR-9:** `week_active`'s week bucketing must reuse the existing `ConsistencyScore.startOfWeek` rollup that `ProgressAnalytics` already computes, not a re-implemented calendar calculation.
- **FR-10:** `generation_ms` must be measured as the wall-time delta around the `ReadyViewModel.generate()` engine call, and a device benchmark record (cold/warm, p95, slowest supported device iPhone XS on iOS 17, method, date) must be produced under `01-research/` as the substantiation for the sub-100ms marketing claim.
- **FR-11:** `abandon_point` and `entry_point` must be small closed enums (no free text), introduced as new types since neither has a backing field today.
- **FR-12:** The app must not present an App Tracking Transparency prompt and must not touch the advertising identifier; the App Store privacy nutrition label reflects Usage Data (and a Device ID if the install identifier is classed as one), both marked not linked to identity and not used for tracking.
- **FR-13:** No test run may perform a real network call. Tests satisfy this either by emitting through `MockAnalyticsService` or by exercising `LiveAnalyticsService` through an in-process `URLProtocol` stub that intercepts the request without touching the network.

---

## Non-Goals (Out of Scope)

- **No cohort, retention, or funnel math in this build.** Ingest only. All derived-metric computation (D7/D30 rates, WAE share, free-to-paid, session-completion rate) is deferred to after launch, when real data exists.
- **No dashboards, charts, or reporting UI.** The Convex dashboard's raw table view is the only surface; no in-app or web analytics view ships.
- **No third-party analytics SDK.** No Firebase, Amplitude, Mixpanel, PostHog, TelemetryDeck, Countly, or Segment. And, following the US-T01 spike, **no new Swift Package dependency at all**: the client reaches Convex over a plain `URLSession` POST to an HTTP action, so Lottie stays the app's only third-party package. (This is a stronger version of the original "the only new dependency is `convex-swift`" principle - the spike removed even that one.)
- **No user-level identity in any event.** No email, no IDFA, no `identifierForVendor`, no Sign in with Apple identifier - only a random per-install UUID.
- **No ATT prompt** and no access to the advertising identifier.
- **No change to the deterministic engine, the paywall logic, the session loop, or any existing service behaviour.** Emissions are additive hooks; they never alter what the app does.
- **No backend beyond the single append-only `events` table, its one `logEvent` mutation, the `POST /logEvent` HTTP action, and US-T14's rate-limit counter store.** The abuse guard's throttle state lives in exactly one of two permitted shapes - either a dedicated helper table holding only ephemeral per-key counters (the per-install identifier or request source IP, plus a time window) and nothing else, or Convex's official rate-limiter component - and nothing wider is allowed. That counter store is not a second evidence surface: it carries no identity, accumulates no history, is read only by the throttle check, and is **not** part of the evidence base for K1, K2, or K4; it exists only to answer "has this key exceeded its window", and its contents are ephemeral. The `events` table itself stays single, append-only, and dumb, with no aggregation, dedup, or cohort math. No queues, no user accounts, no per-user authentication, no identity in events, and no server-side analysis; the US-T14 abuse guard (a client-embedded shared secret checked at the endpoint plus per-install/IP rate limiting) is the only auth-shaped logic and exists solely to keep strangers from flooding the table, not to identify users.
- **No web-side events.** `landing_page_view` and `waitlist_signup` are web events handled outside the app and are not part of this build.
- **No attempt to read K3 (D30 retention) or K7 (day-35 conversion) at the checkpoint.** They are structurally unreadable in the window (see Success Metrics); this build makes them measurable later, not now.

---

## Design Considerations

- **Toggle placement.** The one Settings toggle needs a home, but the Profile tab is currently a placeholder (`RootView.PlaceholderTabView`) with no Settings surface. US-T06 either introduces a minimal reachable Settings surface from Profile or documents the chosen location; the toggle must be clearly labelled and reachable, using `Theme.Colors` / `Theme.Typography` / `Theme.Spacing`, a 56pt control height, and 44pt touch targets, per the design-system conventions.
- **Onboarding disclosure.** One plain, identity-framed sentence with a privacy-policy link, consistent with the existing onboarding tone ("you're someone who moves"), never loss-framed and never a dark pattern.
- **Copy honesty.** All telemetry copy must be consistent with the shipped privacy claims (offline generation, no account required, on-device history with optional iCloud sync); "anonymous usage data" is the honest frame.

---

## Technical Considerations

- **Architecture / seam.** `AnalyticsServiceProtocol` follows the codebase's protocol + mock + live convention (`Services/Protocols/ServiceProtocols.swift`, `Services/Mock/`, a live impl), registered in `DI/ServiceContainer.swift` in both `mock()` and `live(context:)`, and reached via `@Environment(\.services)` exactly like every other service. `@Observable` only, `async` methods, `Theme` tokens for any UI, tests under `ios/RepToday/RepToday/RepTodayTests/` with a row added to `docs/test-coverage.md` per story.
- **Fire-and-forget precedent.** Every existing integration in this app already degrades quietly and never gates the core loop (HealthKit writes, CloudKit sync, StoreKit transaction observation via `startObservingTransactions()`). `LiveAnalyticsService` follows the same rule: best-effort, background, swallowed failures.
- **Convex transport (no client SDK).** The client reaches Convex over a plain `URLSession` POST to the deployment's `.site/logEvent` HTTP action (US-T03), so **no** Convex Swift package is added; `ios/RepToday/project.yml` keeps Lottie as its only third-party dependency. The US-T01 spike investigated `get-convex/convex-swift` and returned a no-go: it builds fine against an iOS 17.0 target (iOS 17 was never the blocker), but it ships an arm64-only binary xcframework with no `x86_64` slice, which would make every Simulator-hosted test suite in this repo unbuildable on the captain's Intel host - for what needs to be one fire-and-forget JSON POST. The captain adopted the no-go on 2026-08-03. If live reactive Convex queries are ever wanted, the first thing to re-check is that arm64-only xcframework against the Macs and CI runners in use, not the iOS deployment target. See `artifacts/reports/US-T01/spike-note.md`.
- **Install identifier lifecycle.** A random UUIDv4 in `UserDefaults` dies on uninstall (per-install by construction) and is deliberately **not** Keychain-persisted - Keychain persistence would survive reinstall and resurrect a "deleted" identity, the exact failure mode the account-deletion PRD flags. This also keeps the identifier cleanly outside anything the account-deletion path must tear down.
- **Clock injection.** All windowing/dedup logic (returns, `week_active`, `elapsed_seconds`, `generation_ms`) takes an injected clock, consistent with the rule that pure engine/evaluator logic never reads the wall clock inline, so every event's timing is deterministic under test.
- **New timestamps in `AppState`.** `AppState` today persists only `isOnboarded` and `selectedTab`; `installId`, `firstLaunchAt`, `lastActiveAt`, and `analyticsEnabled` are net-new `UserDefaults` keys added there (or a small sibling store), because no first-launch marker exists in the codebase.
- **Emission sites, confirmed against the code:**
  - `app_install` / `day7_return` / `day30_return`: `RepTodayApp.init()` or `AppState.init(userDefaults:)` (first-launch detection lives here; no timestamp exists yet).
  - `onboarding_started`: a new one-shot `.onAppear`/`.task` on `OnboardingView.body` (none today). `onboarding_completed`: `OnboardingViewModel.finish()` success branch, before `return true`.
  - `ready_screen_shown` + `generation_ms`: wrap the untimed engine call in `ReadyViewModel.generate()`; scope the event to first load via a one-shot flag like `hasComputedConsistency`.
  - `session_started`: `ActiveSessionViewModel.start()`. `session_completed`: `ActiveSessionViewModel.finish()`. `session_abandoned`: the `completed == false` dismiss path (`ActiveSessionView.close()` / `ReadyViewModel.handlePlayerDismiss(completed:)`) - no abandonment method exists today.
  - `week_active`: emitted from the completion path (`SessionCompletionService.recordCompletedSession`), reusing `ProgressAnalytics`'s `sessionsByWeek` week-start keys; `ProgressAnalytics` only computes and has no emission side.
  - `paywall_shown` / `trial_started` / `subscribe`: `PaywallViewModel.load()` / `.purchase(_:)` and `StoreKitSubscriptionService.purchase(_:)`; trial-ness derived from `Subscription.trialEndsAt != nil`.
- **Privacy label.** Nutrition label becomes Usage Data (and a Device ID if the install UUID is classed as a device identifier), both marked not linked to identity and not used for tracking; no ATT, no IDFA.

---

## Success Metrics

Framed against the kill gates, not vanity numbers.

- **K1 (onboarding-to-first-session) becomes measurable at all.** The canonical denominator (installs with `onboarding_started`) and numerator (installs with a `session_started`) both exist as events, so the ratio the thesis reads at the checkpoint can actually be computed. Before this build it cannot.
- **K4 (Weekly Active Exercisers) becomes measurable at all.** `week_active` gives the North Star its numerator (distinct installs active in a week) and `app_install` gives the denominator (cumulative installs).
- **K2 (D7 return) becomes trustworthy.** A deduplicated, windowed `day7_return` is emitted rather than retention being inferred later from noisy open logs the app does not keep.
- **The sub-100ms claim is substantiated.** `generation_ms` percentiles (including p95) are recorded on real hardware including the slowest supported device (iPhone XS on iOS 17), clearing the marketing blocker that gates the site, video, screenshots, and investor teaser.

### What is readable at the checkpoint, and what is not (state plainly)

Launch is roughly 8 weeks out and the checkpoint sits on about five weeks of live data.

- **Readable in that window:** K5 (weekly installs, also free from App Store Connect), K1 (onboarding-to-first-session), early K2 (D7 return), K6 (trial starts), and K8 (wedge comprehension from the moderated cohort).
- **Structurally unreadable at the checkpoint, by construction, not by omission:**
  - **K3 (D30 retention)** needs 30 days per cohort plus the thesis's 200-user pooling floor; the data does not exist yet in a five-week window.
  - **K7 (free-to-paid, day-35 cohort view)** needs a day-35 horizon that has not elapsed.
  This build makes K3 and K7 *measurable later*; nobody should expect them *at the checkpoint*. Ingesting the events now is exactly what lets those reads happen once the horizon arrives.

---

## Open Questions

- **Story-prefix collision to fix separately (not here).** The account-deletion PRD (`~/Mandu/projects/RepToday/01-prd-account-deletion_260731.md`) reuses `US-D01`-`US-D06`, which collides with the completed Epic D in `prd-fitsnack-mvp-v6_0702.md`. This PRD sidesteps it with the `US-T##` prefix; the captain should reconcile the D-prefix collision in the other document separately.
- **`current-priorities.md` says "explicit opt-in".** `~/Mandu/context/current-priorities.md` currently states explicit opt-in; this PRD deliberately overrides that with opt-out (sample-size rationale above). The captain should update `current-priorities.md` so the two documents agree, or overrule this PRD.
- **No first-launch timestamp exists today (contradiction with the brief's framing).** The brief describes the install/return events as "gated on a first-launch timestamp", but `AppState` persists only `isOnboarded` and `selectedTab` - there is no install date anywhere. The timestamp is therefore net-new (US-T05). Flagged per "trust the code and flag the contradiction"; the code is trusted and the timestamp is added.
- **No Settings surface exists for the toggle.** The Profile tab is a placeholder with no Settings screen, so US-T06 must introduce a minimal reachable surface. Confirm whether a dedicated minimal Settings screen is acceptable for this build or whether the toggle should wait on a broader Profile/Settings story.
- **`ready_screen_shown` emission granularity.** Is the intended semantics one emission per Ready Screen open (default here) or one per generation (which would re-fire on every duration-chip tap)? The K8 wedge-check and latency reads differ slightly between the two; confirm against the schema author's intent.
- **`trial_started` vs `subscribe` at conversion.** The schema says `subscribe` fires when "trial converts or direct". Should a trial that later converts emit `subscribe` at conversion time (in addition to `trial_started` at trial start)? StoreKit surfaces renewals through the transaction listener; confirm whether conversion should be a distinct emission and, if so, where.
- **Nutrition-label class for the install UUID.** Confirm with the privacy-policy author whether a random app-generated per-install UUID is declared as "Device ID" or "User ID" in the App Store nutrition label; either way it is marked not linked to identity and not used for tracking.
- **Named non-founder coder for the K8 / US-T13 reconciliation.** The investment thesis leaves "[FOUNDER TO FILL: name of the non-founder coder]" open; US-T13's ground-truth reconciliation depends on that person's coded observations existing.
- **Convex deployment ownership and cost.** Confirm which Convex account/plan hosts the production sink and that its free-tier limits comfortably cover launch-scale event volume (roughly 90 installs/week times ~10 events per active user).
