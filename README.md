# Rep Today - Discipline-First Micro-Workout App

**Open the app. Tell it how many minutes you have. Press play.**

Rep Today is an iOS app for busy, desk-bound adults who can give exercise 5-60 minutes a day.
It exists to build one thing: the discipline of showing up.
The user says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session that blends bodyweight strength and mobility.
No browsing, no choosing, no thinking.

> **Status:** clean rebuild in progress.
> The previous app (XP/badges/streaks, AI services, SwiftData) was removed and lives only in git history as reference.

---

## Why Rep Today?

Most fitness apps assume you have an hour to spare and the mental bandwidth to pick a routine.
Rep Today assumes the opposite:

- **Zero-decision workouts** - a deterministic on-device engine builds a complete session the moment you select a duration.
- **Time-flexible by design** - every session is 5-60 minutes, generated to land within ±1 minute of the time you asked for.
- **Discipline first, strength earned** - consistency is the entry promise; strength is earned over time, never the headline.
- **Forgiving, not fragile** - a rolling Consistency Score replaces the brittle streak, so a single miss dents but never zeroes your progress.

---

## Target Audience

**Primary:** busy, desk-bound adults (working parents, professionals) who previously moved regularly but lost the routine.
They don't lack motivation - they lack time and mental bandwidth.

**Secondary:** people who travel frequently or work unpredictable hours and can't commit to a fixed gym schedule.

---

## The Two-Phase Journey

The product builds the habit of moving; strength is *earned*, never the launch headline.

- **Discipline Phase** - where every user starts. Consistency is the only goal; sessions stay short and simple.
- **Strength Phase** - earned over time by sustaining the habit *and* progressing the foundational movement chains.

The `PhaseEvaluator` is deterministic and never user-selectable.
At launch no user has earned the Strength Phase, so the MVP ships the Discipline-Phase experience with the evaluator already in place.

---

## Features

### Onboarding

- **The units you think in** - height goes in as feet and inches and weight in pounds, on 44pt step buttons that repeat when held; the stored profile stays metric, converted once at the onboarding boundary, so everything downstream (including the energy Rep Today writes to Health) is in centimeters and kilograms whatever you typed.

### Core Workout Loop

- **Deterministic session generation** - select a duration (5-60 min) and the engine assembles a structured session (warm-up, main work, cooldown over 10 min) on-device, with no network and no LLM.
- **Smart movement selection** - leads every session with strength, rotates the stalest movement pattern, filters by phase, injuries, difficulty cap, and recent skips, and never repeats yesterday's primary pattern.
- **Adaptive Overload** - prescribes capacity-relative reps/sets/holds (never a fixed heroic number); an asymmetric ramp adjusts within one cycle - a `too_hard` or a skip backs off fast, `too_easy` climbs slow.
- **A start matched to your level** - the first sessions open at the difficulty band and volume seeded from the fitness level you reported at onboarding, rather than at the library's absolute beginner tier; a `too_hard` rating walks both the tier and the volume back down within one session, and the seeding retires on its own once there is real history to steer by.
- **In-session swap** - substitutes deterministically within the same pillar, pattern, difficulty band, and time budget.

### Active Session Experience

- Large touch targets (60pt minimum on active workout screens).
- Follow along without touching the phone - a rep-based set in the main work shows the movement on screen beside its own counting-down window and flows into the rest and on to the next movement with no tap, so you can follow by eye without a voice. A prominent "Done" ends the window the moment you finish your reps, and being caught mid-rep when it reaches zero costs you nothing: it's an escape hatch, not a demand.
- Rounds, not a list to grind through - the main work is played as a circuit, one set of each movement and then around again, with the screen reading "Round 2 of 4" so you always know where you are; no movement is ever prescribed more than four times, and a longer session adds more movements instead of more rounds. Warm-up and cooldown stay linear.
- Timed rests carry the flow between everything - a short one between movements inside a round, a longer one between rounds - each naming what's up next, and each skippable, extendable, and paused correctly when the app is backgrounded.
- No running clock during the session - a total ticking up in the corner turns a five-minute session into something to get through, so the time you took is revealed once, on the completion summary.
- A hold timer where a clock actually helps - a warm-up or cooldown stretch starts its hold on its own with no tap, and a per-side one flows side 1 into a brief "Switch sides" beat into side 2 hands-free; a timed strength movement still waits for "Start hold", so you set yourself up before the clock runs. Either way the countdown records the set itself at zero with the same haptic/audio cue the rest timer uses, and a per-side hold is counted one side at a time, so a plank is never logged at half the work the session was planned around. A hold can always be banked by hand instead - including part-way through a countdown - so being interrupted never costs you the sets you already did.
- Pause, with no "manual mode" to find - one control freezes whichever countdown is live (work window, hold, or rest) and picks back up at the exact second you left, without having to leave the app. The other ways out - done early, skip, swap, more rest - stay quietly in the flow rather than behind a mode switch.
- Per-side movements say so in the prescription itself - "3 × 0:30 per side" on screen, "3 sets of 30 second holds per side" read aloud - because the session is planned around the work on both sides, so a user who works one side never does half the session by accident.
- Haptic feedback (and an audio alternative) when a rest ends, so you can start the next set without watching the clock.
- In-session swap - replace the current movement with a same-pillar/pattern peer in one tap, or an honest "no alternative" notice when none is safe and in budget, so one movement you can't or won't do never derails the session. Inside a circuit the choice holds for the rest of the session: a swapped-in movement carries through every remaining round, and skipping one drops it from every remaining round, so you decide once instead of again each time it comes around.
- Background and resume - an in-progress session is persisted and survives backgrounding and a full relaunch; an abandoned session can be resumed at the exact place you left off, or discarded, from the Ready Screen - identity-framed, never guilt-framed.
- Post-session celebration and summary - finishing writes the durable workout log automatically (fire-and-forget, so quitting on the celebration screen never loses the record) and shows an identity-framed wrap-up ("You showed up. That's the whole game.") with the session's actual duration and honest muscle/mobility coverage - a skipped movement is never counted.
- Optional one-tap perceived-difficulty rating ("Too easy / Just right / Too hard") on the completion screen - it never gates Done, skipping it leaves the session unrated, and the answer tunes the next session's targets within one cycle via the asymmetric ramp.
- Accessibility throughout: VoiceOver, Dynamic Type, and a static demo fallback for Reduce Motion. The spoken prescription reads as a sentence that agrees with its own counts - a single-set warm-up or cooldown is "1 set of a 45 second hold", never "1 sets of 45 second holds" - and the Ready Screen's lineup speaks it exactly as the player does rather than reading the "×" glyph aloud.

### Consistency, Not Gamification

There is no XP, no levels, and no badges in the MVP.

- **Consistency Score** - a rolling, weighted measure of showing up; a 5-minute session counts as a full show-up, and recent weeks weigh more.
- **Longest chain** - tracked and surfaced as an earned point of pride, never as a threat.
- **Progress tab** - the reflection surface: a calendar marking every completed day, a Consistency Score trend chart (each point the real forgiving score sampled at an earlier week's vantage, so the chart's right edge always equals the headline number), the longest chain surfaced as pride, a free "visible climb" toward the earned Strength Phase (the two real earn signals - weeks of steady practice and foundations cleared - shown to a Discipline-Phase user from the same logic that gates the phase), a free per-pattern progression map (a read-only ladder for push/squat/hinge/core marking where you stand and which Strength-Phase rungs are still locked, previewable but never selectable), and a legibility layer (pillar balance, progression-chain position, personal bests) with deeper analytics gated behind premium - all reading real workout history.
- **Identity-framed copy** - "you're someone who moves," never loss-framed.

### Premium AI Coach

- **Talks, never programs** - the premium Coach explains the deterministic engine's choices, gives concise bodyweight form guidance, narrates strength-journey trends, and can offer bounded preference nudges; it never generates or directly edits a workout or safety filter.
- **Best-effort and bounded** - Coach turns use the stateless Cloudflare proxy's `POST /coach` route and a source-pinned OpenAI `gpt-5.6-luna` Responses API call. The request has a 30-second timeout and 1024-token output ceiling, and any failure leaves the free core loop untouched. The production endpoint is currently empty, so shipped builds show the Coach as unavailable until a deployment is chosen.

### Privacy

- **Anonymous usage data, disclosed and optional** - the first onboarding screen says in one sentence what is collected and where the off switch is, and Profile -> Settings -> Privacy carries a "Share anonymous usage data" toggle that takes effect on the next event rather than the next launch. It is on by default (opt-out, not opt-in), counted against a random per-install number that is never a name, an email, or a device identifier. Turning it off leaves that number untouched; deleting the account rotates it so later events cannot be linked to the pre-deletion install identity.
- **Emitting the whole funnel** - the pipeline is complete, consented, and gated, and every call site now feeds it: app entry (US-T07), the onboarding funnel (US-T08), the Ready Screen (US-T09), the session lifecycle (US-T10), the weekly rollup (US-T11's `week_active`), and the monetization funnel (US-T12's `paywall_shown`/`trial_started`/`subscribe`). All 13 events now have their emission sites, and every emission is read against the opt-out flag afresh, so an opted-out build sends nothing either way.
- **Coach data is disclosed before first use** - a Coach turn sends the user's message, the audited non-identifying training summary, and a separate random Coach abuse-prevention pseudonym to Rep Today's proxy, which forwards the pseudonym as OpenAI's `safety_identifier`. The proxy stores no request or response content and sets `store: false`; under standard retention, OpenAI may still retain the prompt and reply in abuse-monitoring logs for up to 30 days. The pseudonym is not the telemetry `installId` or an account value, remains stable across launches, and rotates on account deletion.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Platform** | iOS 17.0+, Swift 5.9, Xcode 16.3 |
| **UI Framework** | SwiftUI with the Observation framework (`@Observable`) |
| **Architecture** | MVVM + protocol-based service injection |
| **Persistence** | CoreData backed by `NSPersistentCloudKitContainer` (entities `CDUser`, `CDWorkoutLog`, `CDSessionPolicy`, `CDActiveSession`) |
| **Engine** | Pure Swift, on-device, deterministic (no network, no LLM, <100ms) |
| **Apple integrations** | Sign in with Apple, CloudKit (private DB sync), HealthKit, StoreKit 2 |
| **Backend** | None behind the core loop; `convex/` is the anonymous-telemetry sink only (US-T03), reached by a plain `URLSession` POST (US-T04) that the user's opt-out flag gates (US-T06) and a shared-secret + per-caller rate-limit abuse guard fronts (US-T14) |
| **LLM proxy** | `proxy/` is a stateless Cloudflare Worker: Anthropic `claude-opus-4-8` remains independently configurable for deferred Variety Language, while the premium Coach is source-pinned to OpenAI `gpt-5.6-luna`; neither route is behind the deterministic core loop |
| **Bundle ID** | `com.reptoday.app` |

The Phase-2 premium Coach is implemented but its production endpoint is not deployed or configured. It does language plus bounded preference offers only; the deterministic on-device engine remains sovereign over every workout and safety filter.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Views (SwiftUI)                                │
│  Access services via @Environment(\.services)   │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  ViewModels (@Observable classes)                │
│  Async service calls, UI state management       │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Service Protocols (Services/Protocols/)         │
│  Methods async throws; mock implementations     │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  ServiceContainer (DI/)                          │
│  Holds all services, injected at the app root    │
│  Swap one line to replace a mock with the real   │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Protocol-based services** - all services are protocol-defined with mock implementations. To swap a mock for a real implementation, change one line in `ServiceContainer`; views and viewmodels remain untouched. Service methods are `async throws`, with one deliberate exception: `AnalyticsServiceProtocol.record(_:)` is `async` but never `throws`, because anonymous telemetry is strictly fire-and-forget and must not hand a caller a failure to think about.
- **CoreData with domain separation** - domain models are plain `Codable` structs; CoreData entities convert via `toUser()`/`update(from:)`-style methods, with complex nested fields stored as JSON-encoded `Data`. The core loop works fully offline; CloudKit handles sync and backup when available.
- **Deterministic engine** - the workout engine runs entirely on-device with no network or LLM calls (see below).
- **Environment-based DI** - `ServiceContainer` holds all service instances, injected at the app root via a custom `EnvironmentKey`.

---

## The Deterministic Engine

The on-device engine runs this pipeline (one step per Epic C story in the PRD).
**Step 0 overrides** run ahead of it and are no-ops in the steady state: a cold start seeds the first sessions from the reported fitness level (a difficulty band and a volume seed, both eased by a `too_hard` rating and retired once there is enough history), and a Return after a gap serves a deliberately easy session. Both keep only these gentleness rails - since the strength lead is structural, neither steers which pillar leads.

1. **Session shape** - 5-10 min single-focus; 11-20 min blend (light); 21-40 min blend (full); 41-60 min blend (extended).
2. **Pillar balance** - every session is strength-led, structurally: the engine builds a single strength training block (primal folded in) for single-focus and the shorter blends, or a strength block plus a dedicated primal block for an extended (41-60 min) blend - never a mobility training block at any length. Mobility survives only as the warm-up and cooldown bookends; the minutes the retired Movement Practice mobility block used to hold were reallocated to strength.
3. **Movement-pattern focus** - rank patterns by staleness; never repeat yesterday's primary pattern.
4. **Filter pool** - drop by phase, injuries, difficulty cap, and recent skips; everything is bodyweight (Zero-Equipment Floor).
5. **Progression-chain selection** - pick the current chain position; offer the next when advancement criteria are met; avoid the last few sessions (a policy-tunable `varietyWindow`, default 3).
6. **Adaptive Overload** - prescribe capacity-relative reps/sets/holds; feedback (or a skip) adjusts within one cycle via an asymmetric ramp (back off fast, climb slow), the advancing bump paced by the policy's `progressionRate`.
7. **Assemble + fit timing** (even-round circuit model, US-CC03/US-CC04, round-capped by US-RC01) - always open with a warm-up, add a cooldown over 10 min, and land within ±1 min of the requested time. A training block is a circuit of **even rounds**: every exercise in it carries the same set count (the block's round count, bounded to **2-4** so no movement is ever prescribed more than four times), so "Round N of M" is well-defined. A set is priced as a fixed setup cost plus the per-unit work of the target actually prescribed (a per-side hold costing both sides), so a grown or seeded target is planned as the longer session it really is, then paced generously (US-CC08): the rep half is scaled to a slower-end tempo a typical user comfortably finishes within, while a hold is left alone because its per-second cost is definitional rather than estimated. That paced number is one source of truth - the seconds the fit budgets for a set are the seconds the player's on-screen work window counts down - so the screen can never be roomier than the plan; the cost is that a session fits a few fewer rounds, and a fast user simply finishes early and taps Done. Two rest gaps carry the timing fit: a fixed ~15s between-station transition inside a round, and a bounded between-round rest (30-75s) that the fit tunes as its **primary lever**, falling back to whole rounds or whole exercises - it never touches the Step 6 per-set target and never makes a block uneven. Once every active station reaches the 4-round cap, a longer session is filled **wider** instead of deeper - a strength pattern's further progression chain joins the block reserve as an accessory (US-RC01) - so short/medium sessions stay one movement per pattern and only a long session goes wide. The warm-up and cooldown bookends are one set per exercise - a stretch is never multi-set - so a longer session grows them only by adding distinct movements.

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget, or returns a clear "no alternative" when no safe peer fits.
The substitute is sized by the same levers the session was generated with (the policy's `progressionRate`, the cold-start seed, and any Return / re-entry ease), and under the even-round model (US-CC03) it **keeps the slot's set count** - on a training block that is the block's uniform round count - so a swap can never make a circuit uneven; a substitute joins at that round count or declines. Because no slot re-picks a set count anymore, a swap can move the session by up to the swapped slot's own time tolerance. Applying a swap across all remaining rounds landed in US-CC07 (player-side: replacing the one step per station carries the substitute through every remaining round with the circuit staying even, and the substitute is an honest late entrant that logs only the rounds it played); reshaping the block's shared round-rest on swap to re-absorb that in-tolerance drift was scoped out of US-CC07, since the drift is already bounded by the slot's tolerance.

---

## Project Structure

```
RepToday/
├── ios/RepToday/RepToday/
│   ├── App/                 # App entry point (RepTodayApp.swift)
│   ├── DesignSystem/        # Theme tokens (Theme.swift)
│   ├── Models/              # Domain enums and Codable structs
│   ├── Persistence/         # CoreData stack (NSPersistentCloudKitContainer) + conversions
│   ├── Services/
│   │   ├── Protocols/       # Service protocol definitions
│   │   ├── Mock/            # Mock implementations wired in ServiceContainer
│   │   ├── Engine/          # Deterministic workout-engine pipeline steps (pure, on-device)
│   │   ├── Programmer/      # Deterministic AI Programmer (re-program trigger detection, plateau diagnosis, Default Duration learning, templated policy note, and the persistence-backed re-weighting service that composes them; pure logic on-device)
│   │   ├── ActiveSession/   # In-progress session persistence seam (ActiveSessionStore protocol + InMemoryActiveSessionStore) so an abandoned session survives backgrounding/relaunch and can be resumed or discarded (US-K04); the post-session recorder (SessionCompletionService + protocol) that writes the WorkoutLog and does the completion bookkeeping - Consistency Score refresh + cold-start handoff (US-L01) plus the minimal, cold-start-safe in-place rating update recordPerceivedDifficulty (US-L02) - and the pure SessionSummary behind the celebration screen's muscle/mobility coverage (US-L01)
│   │   ├── Analytics/       # Telemetry sinks: the live Convex POST (US-T04), the inert no-op fallback, and the Debug-only XCUITest probe harness (US-T06)
│   │   └── …                # Consistency/, Progress/, Language/, Auth/, Health/, Subscription/ - see AGENTS.md for the full listing
│   ├── DI/                  # ServiceContainer + environment injection
│   ├── ViewModels/          # @Observable view models
│   ├── Views/               # SwiftUI screens (Onboarding, Ready, ActiveSession, Progress, Paywall, Settings, plus RootView)
│   ├── Utilities/           # AppState (routing, telemetry identity/consent, and the separate Coach safety pseudonym), LegalLinks, and shared helpers
│   └── Resources/           # Exercises.json, Assets.xcassets, RepToday.storekit (no demo animation ships yet - see docs/asset-attribution.md)
├── ios/RepToday/RepTodayTests/     # The default suite (XCTestCase + @testable import), plus the shared seams every suite is expected to use instead of its own copy: EvidenceOutput, HostedSurface/AccessibilityTree, DefaultsSnapshot
├── ios/RepToday/RepTodayUITests/   # The out-of-process XCUITest bundle under its own scheme, for the few things only a real touch can exercise; HealthAccessPrompt is its shared helper
├── convex/                  # Anonymous-telemetry sink only (append-only events table, US-T14's ephemeral rateLimits helper, internal indexed reconciliation read); no core-loop backend
├── package.json             # npm root for the Convex functions - standard Convex layout puts it here, not in convex/ (see convex/README.md)
├── tools/                   # Release archive + production-telemetry validators, and the offline US-T13 reconciliation harness
├── proxy/                   # Stateless key-holding Worker: deferred Anthropic Variety Language + the OpenAI gpt-5.6-luna Coach route; no production Coach endpoint is configured
├── docs/                    # Implementation log (story-by-story narrative), test-coverage map, asset-attribution ledger
├── .claude/agent/tasks/     # Strategic plan + implementation PRD (source of truth)
├── AGENTS.md                # Repo guidance and architecture reference - the real file
└── CLAUDE.md                # Symlink to AGENTS.md; edit AGENTS.md
```

---

## Source of Truth

| Document | Purpose |
|----------|---------|
| The v6.0 strategic PRD under `.claude/agent/tasks/` | Strategic plan (v6.0) - the discipline-first vision plus the v6 wedge (a daily-adaptive AI Programmer that writes a per-user Session Policy the deterministic engine runs on). Supersedes the prior v5 strategic PRD (kept for reference). |
| `.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md` | Implementation PRD and live progress tracker - the v6 MVP as ~51 user stories (US-A01 … US-N05) with acceptance criteria. Supersedes `prd-fitsnack-mvp_0626.md` (v5, kept for reference). |
| `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` | A second, in-progress PRD - anonymous product telemetry for the 90-day PMF test, as `US-T##` stories. The analytics seam (US-T02), Convex sink (US-T03), anonymous install identity (US-T05), fire-and-forget transport (US-T04), opt-out/disclosure (US-T06), and all 13 emission sites (US-T07...T12) have landed. US-T14 abuse-hardened `POST /logEvent`; Release now targets the production deployment with a private Keychain-backed token injection. US-T13 (ground-truth reconciliation) remains the one open story. |
| `.claude/agent/tasks/prd-continuous-circuit-sessions_260814.md` | A third PRD, now complete - the hands-free follow-along player (`US-CC##`) that replaced the manual tap-to-advance active-session player: auto-advancing work windows, circuit rounds ("Round N of M"), non-verbal audio cues, a first-run explainer, and full accessibility acceptance, plus the even-round engine timing model (ADR-0003) every training block now runs on. |
| `.claude/agent/tasks/prd-round-cap-wide-circuits.md` | A fourth, complete PRD - caps every training-block exercise at **2-4 rounds** (`US-RC##`) and fills longer sessions by adding distinct movements instead of more rounds; ADR-0004 and the `CONTEXT.md` "Wide Circuit" term record the settled design. |
| `.claude/agent/tasks/prd-phase-2-strength-coach-analytics_260825.md` | A fifth, complete PRD - makes the earned Strength Phase real and visible, adds the premium Coach and its two-writer safety boundary (ADR-0005), and adds premium strength-journey analytics. The Coach transport is implemented and tested against OpenAI `gpt-5.6-luna` without live paid calls, but remains inert until its production proxy endpoint is deployed and configured. |
| `CLAUDE.md` | Repo conventions and architecture for contributors and AI assistants - kept deliberately short, with the detail split into `docs/`. It is a symlink to `AGENTS.md`, which is the file to edit. |
| `convex/README.md` | The telemetry sink's own reference: the `events` table, the `logEvent` contract, `POST /logEvent`, the US-T14 abuse guard (shared secret + rate limiting), its boundary suite, the deliberate non-goals, and the residual it still carries. |
| `docs/implementation-log.md` | What has actually been built, story by story - the narrative behind each landed story. |
| `docs/test-coverage.md` | The test-coverage map: one row per suite, added as the owning story lands. |
| `docs/asset-attribution.md` | The source/license ledger every third-party asset must have a cleared row in before it ships. |

Always check the PRD for the relevant story before building a feature.

---

## Getting Started

### Prerequisites

- **Xcode 16.3+**
- **iOS 17.0+ Simulator or device**
- **XcodeGen** (to generate the project from `project.yml`)

```bash
brew install xcodegen
```

### Build & Run

```bash
# Generate the Xcode project
cd ios/RepToday && xcodegen generate

# Build for the simulator
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

# Or open in Xcode
open ios/RepToday/RepToday.xcodeproj
```

### Run Tests

The `RepToday` scheme builds the app and runs the `RepTodayTests` target - that is the default run, and everything except the XCUITests lives in it.

```bash
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`RepTodayUITests` is a second scheme on purpose: it installs and launches the app in a booted Simulator and drives it out of process, so folding it into `RepToday` would make every unit run wait on an app launch and inherit its failure modes.
Run it when the touch path is what is in question - it is the only place a production control is actually pressed rather than hosted.

```bash
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepTodayUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If xcodebuild cannot resolve the destination, list installed simulators with `xcrun simctl list devices available` and pass `-destination 'id=<UDID>'`.

### The telemetry sink (`convex/`)

Only needed when working on `convex/` - the iOS app builds, runs, and tests without any of it. The app's transport to this sink exists (US-T04's `LiveAnalyticsService`), and every emission site now calls it - app entry (US-T07), the onboarding funnel (US-T08), the Ready Screen (US-T09), the session lifecycle (US-T10), the weekly rollup (US-T11's `week_active`), and the monetization funnel (US-T12's `paywall_shown`/`trial_started`/`subscribe`). Debug uses the dev sink; a Release archive uses production only when the private token injection succeeds. The other caller is US-T06's Debug-only, launch-argument-gated XCUITest probe.
Which deployment a build talks to is the per-configuration `REPTODAY_ANALYTICS_ENDPOINT` build setting in `ios/RepToday/project.yml`: Debug points at dev deployment `courteous-dogfish-560`, and Release at production deployment `sensible-spider-810`. US-T14's companion `REPTODAY_ANALYTICS_SECRET` remains empty in Release source and is injected from the captain-owned macOS Keychain by `tools/archive-release.sh`; it is sent on every POST and checked against the production deployment's `ANALYTICS_SHARED_SECRET`. This shipped value is an extractable cost-raiser, not strong authentication; the per-install/per-IP limiter remains the authoritative abuse bound. Missing endpoint or token stays inert and nonfatal. Provisioning, rotation, rollback, and secret-free validation evidence live in `artifacts/reports/production-telemetry/validation.md`.
Whether it talks at all is the user's call: US-T06's opt-out flag is read fresh on every emission, so a launch carrying `-AppState.analyticsEnabled NO` posts nothing to any deployment - the one mechanism that reaches an app the test process launched but never built.
Read that as one of two guards rather than as passed by every launch: `OnboardingImperialUITests` passes it always, and `TelemetryOptOutUITests` passes it only where being opted out is the assertion, holding its opted-in legs off the wire by interception instead - the probe harness swaps the transport's `URLSession` for an in-process counting `URLProtocol`, which is what lets those legs run with the gate genuinely open.
So every launch in that suite carries consent-off **or** the probe, and neither is not representable: the postures are a `TelemetryPosture` enum with no case meaning neither, and every launch goes through `TestApp` (`RepTodayUITests/TestApp.swift`), the bundle's sole `XCUIApplication`, whose only launch entry point takes a posture by value - so a test cannot hold a raw launchable app.
`XCUIApplication` is a framework type any file can still construct, so the guarantee is "cannot ship a bypass" rather than "cannot type one": `UITestLaunchGuardTests` (`RepTodayTests/UITestLaunchGuardTests.swift`, in the unit bundle so it runs on the routinely-run `-scheme RepToday test` gate) scans every `RepTodayUITests` source and fails that run if `XCUIApplication(` is constructed anywhere but `TestApp.swift`.
That build guard replaced the retired runtime detector, which only detected a bypass after the fact and had a verified blind spot - a standalone bare `app.launch()` as a test's only launch; a source scan has no launch orderings to miss.
See `docs/test-coverage.md` for which leg carries which guard, why each of those details is there rather than obvious, and the coverage the guard honestly has.
It needs **Node.js 20+** and npm (vitest ^4 requires Node 20+, which is what CI pins); the npm project is at the repo root rather than inside `convex/`, because Convex bundles every file under the functions directory.

```bash
npm install
npm run typecheck         # tsc --noEmit over convex/ - the deploy config and the test one
npm test                  # vitest + convex-test: the POST boundary and reconciliation suites, in process
npx convex dev --once     # deploy the schema + functions to your own dev deployment
npx convex env set ANALYTICS_SHARED_SECRET <secret>   # US-T14: without it the route fails closed (500)
npx convex data events    # read rows back
```

`convex/_generated/` is committed, so `npm run typecheck` and `npm test` both work in a fresh clone with no deployment configured (the two `npx convex` commands do need one).
US-T04 added the behavioural boundary suite (`convex/http.test.ts`), and the US-T13 harness now also tests its indexed internal read (`convex/reconcile.query.test.ts`) and pure tabulator (`convex/reconcile/tabulate.test.ts`). All run in process against no deployment; `.github/workflows/ci.yml` runs them (with `npm run typecheck`) on every PR into `main`. Production operators use `tools/validate-production-telemetry.sh` for the authenticated sink boundary and `tools/validate-release-telemetry-client.sh` for the real Release client; prerequisites and sanitized results are in `artifacts/reports/production-telemetry/validation.md`.

### Continuous integration

`.github/workflows/ci.yml` gates every PR into `main` (and pushes to it) on both toolchains in parallel jobs: `sink` (ubuntu: `npm ci` + `npm run typecheck` + `npm run test`) and `ios` (macos-15, Xcode 16.4, iPhone 16 / iOS 18.5 simulator - `xcodegen generate`, then build and **run** the `RepToday` unit suite as the gate plus a **build-for-testing-only** compile of the `RepTodayUITests` scheme, since XCUITests launch the app out of process and are slow/flaky on a hosted runner). It needs no secrets: the app's CloudKit/HealthKit/Sign in with Apple entitlements make a fully unsigned build crash the app-hosted test runner, so CI uses cert-less ad-hoc signing (`CODE_SIGN_IDENTITY=-`, team/profile cleared) which loads entitlements on the simulator without any certificate. The local `no-mistakes` pipeline is unchanged.

---

## Design System

Rep Today uses a consistent design token system via `Theme.*` (`Theme.Colors`, `Theme.Typography`, `Theme.Spacing`) - always use these, never hardcode colors, fonts, or spacing.

| Token | Value |
|-------|-------|
| **Button Height** | 56pt |
| **Card Corner Radius** | 16pt |
| **Min Touch Target** | 44pt (60pt on active workout screens) |
| **Typography** | SF Pro (system, rounded) with a semantic scale; Dynamic Type out of the box |

Colors resolve from the asset catalog where a named color exists and fall back to a sensible system color otherwise, so the app always renders.

---

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **MVP** | Discipline-Phase loop: deterministic engine, Consistency Score, PhaseEvaluator, onboarding, CoreData/CloudKit | In Progress |
| **Phase 2** | Language-only LLM features (template-free summaries, weekly narratives), full Strength-Phase catalog, equipment variants | Planned |

The MVP never calls an LLM (summaries are template-based) and ships no gamification, social features, or equipment-based exercises.
See the PRD's Non-Goals section for the full list.

---

## License

All rights reserved. This is a private project.
