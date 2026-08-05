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
- **Smart movement selection** - balances the stalest pillar and movement pattern, filters by phase, injuries, difficulty cap, and recent skips, and never repeats yesterday's primary pattern.
- **Adaptive Overload** - prescribes capacity-relative reps/sets/holds (never a fixed heroic number); an asymmetric ramp adjusts within one cycle - a `too_hard` or a skip backs off fast, `too_easy` climbs slow.
- **A start matched to your level** - the first sessions open at the difficulty band and volume seeded from the fitness level you reported at onboarding, rather than at the library's absolute beginner tier; a `too_hard` rating walks both the tier and the volume back down within one session, and the seeding retires on its own once there is real history to steer by.
- **In-session swap** - substitutes deterministically within the same pillar, pattern, difficulty band, and time budget.

### Active Session Experience

- Large touch targets (60pt minimum on active workout screens).
- Set-by-set tracking with a rest timer between sets - skippable, extendable, and paused correctly when the app is backgrounded.
- No running clock during the session - a total ticking up in the corner turns a five-minute session into something to get through, so the time you took is revealed once, on the completion summary.
- A hold timer only where a clock actually helps - a timed movement offers "Start hold", counts the prescribed seconds down, and records the set itself at zero with the same haptic/audio cue the rest timer uses. A per-side hold is counted one side at a time (the cue at the end of the first leg marks the switch, and the second starts when you're ready), so a plank is never logged at half the work the session was planned around. Rep-based movements stay timer-free, and a hold can always be banked by hand instead - including part-way through a countdown - so being interrupted never costs you the sets you already did.
- Per-side movements say so in the prescription itself - "3 × 0:30 per side" on screen, "3 sets of 30 second holds per side" read aloud - because the session is planned around the work on both sides, so a user who works one side never does half the session by accident.
- Haptic feedback (and an audio alternative) when a rest ends, so you can start the next set without watching the clock.
- In-session swap - replace the current movement with a same-pillar/pattern peer in one tap, or an honest "no alternative" notice when none is safe and in budget, so one movement you can't or won't do never derails the session.
- Background and resume - an in-progress session is persisted and survives backgrounding and a full relaunch; an abandoned session can be resumed at the exact place you left off, or discarded, from the Ready Screen - identity-framed, never guilt-framed.
- Post-session celebration and summary - finishing writes the durable workout log automatically (fire-and-forget, so quitting on the celebration screen never loses the record) and shows an identity-framed wrap-up ("You showed up. That's the whole game.") with the session's actual duration and honest muscle/mobility coverage - a skipped movement is never counted.
- Optional one-tap perceived-difficulty rating ("Too easy / Just right / Too hard") on the completion screen - it never gates Done, skipping it leaves the session unrated, and the answer tunes the next session's targets within one cycle via the asymmetric ramp.
- Accessibility throughout: VoiceOver, Dynamic Type, and a static demo fallback for Reduce Motion. The spoken prescription reads as a sentence that agrees with its own counts - a single-set warm-up or cooldown is "1 set of a 45 second hold", never "1 sets of 45 second holds" - and the Ready Screen's lineup speaks it exactly as the player does rather than reading the "×" glyph aloud.

### Consistency, Not Gamification

There is no XP, no levels, and no badges in the MVP.

- **Consistency Score** - a rolling, weighted measure of showing up; a 5-minute session counts as a full show-up, and recent weeks weigh more.
- **Longest chain** - tracked and surfaced as an earned point of pride, never as a threat.
- **Progress tab** - the reflection surface: a calendar marking every completed day, a Consistency Score trend chart (each point the real forgiving score sampled at an earlier week's vantage, so the chart's right edge always equals the headline number), the longest chain surfaced as pride, and a legibility layer (pillar balance, progression-chain position, personal bests) with deeper analytics gated behind premium - all reading real workout history.
- **Identity-framed copy** - "you're someone who moves," never loss-framed.

### Privacy

- **Anonymous usage data, disclosed and optional** - the first onboarding screen says in one sentence what is collected and where the off switch is, and Profile -> Settings -> Privacy carries a "Share anonymous usage data" toggle that takes effect on the next event rather than the next launch. It is on by default (opt-out, not opt-in), counted against a random per-install number that is never a name, an email, or a device identifier, and turning it off leaves that number untouched rather than minting a new one.
- **Nothing to opt out of yet** - the pipeline is complete, consented, and gated, but no screen emits into it: the call sites are still ahead, so a build today sends nothing either way.

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
| **Backend** | None behind the core loop; `convex/` is the anonymous-telemetry sink only (US-T03), reached by a plain `URLSession` POST (US-T04) that the user's opt-out flag gates (US-T06) |
| **Bundle ID** | `com.reptoday.app` |

AI/LLM features are deferred to Phase 2 and, when they arrive, do language only (summaries, weekly narratives) - they never generate or adapt a workout.

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
**Step 0 overrides** run ahead of it and are no-ops in the steady state: a cold start seeds the first sessions from the reported fitness level (a difficulty band and a volume seed, both eased by a `too_hard` rating and retired once there is enough history) and forces first-week pillar contrast, and a Return after a gap serves a deliberately easy session.

1. **Session shape** - 5-10 min single-focus; 11-20 min blend (light); 21-40 min blend (full); 41-60 min blend (extended).
2. **Pillar balance** - choose the stalest pillar by days-since-worked; bias short sessions toward mobility when the user sits 6+ hours.
3. **Movement-pattern focus** - rank patterns by staleness; never repeat yesterday's primary pattern.
4. **Filter pool** - drop by phase, injuries, difficulty cap, and recent skips; everything is bodyweight (Zero-Equipment Floor).
5. **Progression-chain selection** - pick the current chain position; offer the next when advancement criteria are met; avoid the last few sessions (a policy-tunable `varietyWindow`, default 3).
6. **Adaptive Overload** - prescribe capacity-relative reps/sets/holds; feedback (or a skip) adjusts within one cycle via an asymmetric ramp (back off fast, climb slow), the advancing bump paced by the policy's `progressionRate`.
7. **Assemble + fit timing** - always open with a warm-up, add a cooldown over 10 min, and land within ±1 min of the requested time. A set is priced as a fixed setup cost plus the per-unit work of the target actually prescribed (a per-side hold costing both sides), so a grown or seeded target is planned as the longer session it really is.

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget, or returns a clear "no alternative" when no safe peer fits.
The substitute is sized by the same levers the session was generated with (the policy's `progressionRate`, the cold-start seed, and any Return / re-entry ease), and it keeps the slot's set count whenever a peer fits at it - re-picking a count within the assembler's rails only when leaving the slot alone would push the session out of its stated minutes, and never on the single-set warm-up or cooldown.

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
│   │   └── ActiveSession/   # In-progress session persistence seam (ActiveSessionStore protocol + InMemoryActiveSessionStore) so an abandoned session survives backgrounding/relaunch and can be resumed or discarded (US-K04); the post-session recorder (SessionCompletionService + protocol) that writes the WorkoutLog and does the completion bookkeeping - Consistency Score refresh + cold-start handoff (US-L01) plus the minimal, cold-start-safe in-place rating update recordPerceivedDifficulty (US-L02) - and the pure SessionSummary behind the celebration screen's muscle/mobility coverage (US-L01)
│   ├── DI/                  # ServiceContainer + environment injection
│   ├── ViewModels/          # @Observable view models
│   ├── Views/               # SwiftUI screens (Onboarding, Home, Active session, Post-session, Progress, Settings)
│   ├── Utilities/           # AppState (routing, the anonymous per-install telemetry identity from US-T05, and the telemetry opt-out flag from US-T06), LegalLinks (the one privacy-policy / Terms URL every surface links to), and shared helpers
│   └── Resources/           # Exercises.json, Assets.xcassets, RepToday.storekit (no demo animation ships yet - see docs/asset-attribution.md)
├── convex/                  # Anonymous-telemetry sink only (append-only events table); no backend behind the core loop
├── package.json             # npm root for the Convex functions - standard Convex layout puts it here, not in convex/ (see convex/README.md)
├── proxy/                   # Thin, stateless key-holding Cloudflare Worker for the deferred Variety Language LLM slice (US-N05); not wired into the shipping MVP
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
| `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` | A second, in-progress PRD - anonymous product telemetry for the 90-day PMF test, as `US-T##` stories. The analytics seam (US-T02), the Convex sink (US-T03), the anonymous per-install identity on `AppState` (US-T05), the live fire-and-forget transport between them (US-T04), and the opt-out consent flag with its Settings toggle and onboarding disclosure (US-T06) have landed; the emission call sites that would trigger it are still ahead, so a build today carries a working, consented pipeline that nothing calls. |
| `CLAUDE.md` | Repo conventions and architecture for contributors and AI assistants - kept deliberately short, with the detail split into `docs/`. It is a symlink to `AGENTS.md`, which is the file to edit. |
| `convex/README.md` | The telemetry sink's own reference: the `events` table, the `logEvent` contract, `POST /logEvent`, its boundary suite, the deliberate non-goals, and the residual it still carries. |
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

Only needed when working on `convex/` - the iOS app builds, runs, and tests without any of it. The app's transport to this sink exists (US-T04's `LiveAnalyticsService`), but nothing calls it yet: the emission sites are US-T07 through US-T12.
Which deployment a build talks to is the per-configuration `REPTODAY_ANALYTICS_ENDPOINT` build setting in `ios/RepToday/project.yml`: Debug points at a dev deployment, and Release points at nothing and stays inert, because no production deployment has been chosen yet.
Whether it talks at all is the user's call once the emission sites land: US-T06's opt-out flag is read fresh on every emission, so a launch carrying `-AppState.analyticsEnabled NO` posts nothing to any deployment - the one mechanism that reaches an app the test process launched but never built.
Read that as one of two guards rather than as passed by every launch: `OnboardingImperialUITests` passes it always, and `TelemetryOptOutUITests` passes it only where being opted out is the assertion, holding its opted-in legs off the wire by interception instead - the probe harness swaps the transport's `URLSession` for an in-process counting `URLProtocol`, which is what lets those legs run with the gate genuinely open.
So every launch in that suite carries consent-off **or** the probe, and neither is not representable: the postures are a `TelemetryPosture` enum behind one sanctioned launch helper, with a runtime check for a launch that bypasses it - see `docs/test-coverage.md` for which leg carries which guard.
It needs **Node.js 18+** and npm; the npm project is at the repo root rather than inside `convex/`, because Convex bundles every file under the functions directory.

```bash
npm install
npm run typecheck         # tsc --noEmit over convex/ - the deploy config and the test one
npm test                  # vitest + convex-test: the POST /logEvent boundary suite, in process
npx convex dev --once     # deploy the schema + functions to your own dev deployment
npx convex data events    # read rows back
```

`convex/_generated/` is committed, so `npm run typecheck` and `npm test` both work in a fresh clone with no deployment configured (the two `npx convex` commands do need one).
US-T04 added the behavioural suite (`convex/http.test.ts`), which drives the real functions in process against no deployment; this repo still has no CI, so it only runs when someone runs it - see `convex/README.md` and `docs/test-coverage.md` for what it covers and the one residual it cannot.

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
