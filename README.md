# FitSnack - Discipline-First Micro-Workout App

**Open the app. Tell it how many minutes you have. Press play.**

FitSnack is an iOS app for busy, desk-bound adults who can give exercise 5-30 minutes a day.
It exists to build one thing: the discipline of showing up.
The user says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session that blends bodyweight strength and mobility.
No browsing, no choosing, no thinking.

> **Status:** clean rebuild in progress.
> The previous app (XP/badges/streaks, AI services, SwiftData) was removed and lives only in git history as reference.
> Work proceeds story-by-story against the PRD; today the US-A01 scaffold, US-A02 domain enums, US-A03 domain models, the US-A04 CoreData stack, the US-A05 app shell (service container and app state), the US-B01 bundled exercise library, the US-B02 exercise service (loads, validates, and queries the library), the US-C01 engine Step 1 (session-shape selection from requested minutes), the US-C02 engine Step 2 (pillar balance by staleness), the US-C03 engine Step 3 (movement-pattern focus by staleness, never repeating yesterday's lead pattern), the US-C04 engine Step 4 (exercise-pool filtering by phase, injuries, difficulty cap, and recent skips, with a safe bodyweight fallback when a needed pattern empties), the US-C05 engine Step 5 (progression-chain selection: pick the user's current chain position, offer the next tier only when its advancement criteria are met, and avoid the last 3 sessions for variety), the US-C06 engine Step 6 (Adaptive Overload: prescribe capacity-relative rep/set/hold targets from the user's demonstrated capacity, easing or intensifying within one cycle from the last session's perceived difficulty, never a fixed heroic number), the US-C07 engine Step 7 (session assembly and timing fit: chain Steps 1-6 into a fully-formed, playable session that opens with a warm-up, adds a cooldown over 10 min, and lands within ±1 min of the requested time), the US-C08 deterministic swap (an in-session substitute for one prescribed slot within the same pillar, pattern, and difficulty band that fits the same time budget, or a clear "no alternative" result when no safe peer fits), and the v6 Epic D data foundation - US-D01 (the `User` model's `why`/`duration`/`coldStart` fields) and US-D02 (the `WorkoutLog` model's `requestedMinutes`/`wasReturn` fields), both additive and backward-compatible so pre-v6 records still load, plus US-D03 (the always-valid `SessionPolicy` and its neutral `SessionPolicy.default`, persisted as `CDSessionPolicy`) - exist.

---

## Why FitSnack?

Most fitness apps assume you have an hour to spare and the mental bandwidth to pick a routine.
FitSnack assumes the opposite:

- **Zero-decision workouts** - a deterministic on-device engine builds a complete session the moment you select a duration.
- **Time-flexible by design** - every session is 5-30 minutes, generated to land within ±1 minute of the time you asked for.
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

### Core Workout Loop

- **Deterministic session generation** - select a duration (5-30 min) and the engine assembles a structured session (warm-up, main work, cooldown over 10 min) on-device, with no network and no LLM.
- **Smart movement selection** - balances the stalest pillar and movement pattern, filters by phase, injuries, difficulty cap, and recent skips, and never repeats yesterday's primary pattern.
- **Adaptive Overload** - prescribes capacity-relative reps/sets/holds (never a fixed heroic number); `too_easy`/`too_hard` feedback adjusts within one cycle.
- **In-session swap** - substitutes deterministically within the same pillar, pattern, difficulty band, and time budget.

### Active Session Experience

- Large touch targets (60pt minimum on active workout screens).
- Set-by-set tracking with haptic feedback (and an audio alternative).
- Accessibility throughout: VoiceOver, Dynamic Type, and a static demo fallback for Reduce Motion.

### Consistency, Not Gamification

There is no XP, no levels, and no badges in the MVP.

- **Consistency Score** - a rolling, weighted measure of showing up; a 5-minute session counts as a full show-up, and recent weeks weigh more.
- **Longest chain** - tracked and surfaced as an earned point of pride, never as a threat.
- **Identity-framed copy** - "you're someone who moves," never loss-framed.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Platform** | iOS 17.0+, Swift 5.9, Xcode 16.3 |
| **UI Framework** | SwiftUI with the Observation framework (`@Observable`) |
| **Architecture** | MVVM + protocol-based service injection |
| **Persistence** | CoreData backed by `NSPersistentCloudKitContainer` (entities `CDUser`, `CDWorkoutLog`, `CDSessionPolicy`) |
| **Engine** | Pure Swift, on-device, deterministic (no network, no LLM, <100ms) |
| **Apple integrations** | Sign in with Apple, CloudKit (private DB sync), HealthKit, StoreKit 2 |
| **Backend** | None in the MVP (`convex/` is an empty placeholder) |
| **Bundle ID** | `com.fitsnack.app` |

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
│  All methods async throws; mock implementations │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  ServiceContainer (DI/)                          │
│  Holds all services, injected at the app root    │
│  Swap one line to replace a mock with the real   │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Protocol-based services** - all services are protocol-defined with mock implementations. To swap a mock for a real implementation, change one line in `ServiceContainer`; views and viewmodels remain untouched.
- **CoreData with domain separation** - domain models are plain `Codable` structs; CoreData entities convert via `toUser()`/`update(from:)`-style methods, with complex nested fields stored as JSON-encoded `Data`. The core loop works fully offline; CloudKit handles sync and backup when available.
- **Deterministic engine** - the workout engine runs entirely on-device with no network or LLM calls (see below).
- **Environment-based DI** - `ServiceContainer` holds all service instances, injected at the app root via a custom `EnvironmentKey`.

---

## The Deterministic Engine

The on-device engine runs this pipeline (one step per Epic C story in the PRD):

1. **Session shape** - 5-10 min single-focus; 15 min blend (light); 20-30 min blend (full).
2. **Pillar balance** - choose the stalest pillar by days-since-worked; bias short sessions toward mobility when the user sits 6+ hours.
3. **Movement-pattern focus** - rank patterns by staleness; never repeat yesterday's primary pattern.
4. **Filter pool** - drop by phase, injuries, difficulty cap, and recent skips; everything is bodyweight (Zero-Equipment Floor).
5. **Progression-chain selection** - pick the current chain position; offer the next when advancement criteria are met; avoid the last 3 sessions.
6. **Adaptive Overload** - prescribe capacity-relative reps/sets/holds; feedback adjusts within one cycle.
7. **Assemble + fit timing** - always open with a warm-up, add a cooldown over 10 min, and land within ±1 min of the requested time.

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget, or returns a clear "no alternative" when no safe peer fits.

---

## Project Structure

```
FitSnack/
├── ios/FitSnack/FitSnack/
│   ├── App/                 # App entry point (FitSnackApp.swift)
│   ├── DesignSystem/        # Theme tokens (Theme.swift)
│   ├── Models/              # Domain enums and Codable structs
│   ├── Persistence/         # CoreData stack (NSPersistentCloudKitContainer) + conversions
│   ├── Services/
│   │   ├── Protocols/       # Service protocol definitions
│   │   ├── Mock/            # Mock implementations wired in ServiceContainer
│   │   └── Engine/          # Deterministic workout-engine pipeline steps (pure, on-device)
│   ├── DI/                  # ServiceContainer + environment injection
│   ├── ViewModels/          # @Observable view models
│   ├── Views/               # SwiftUI screens (Onboarding, Home, Active session, Post-session, Progress)
│   ├── Utilities/           # AppState and shared helpers
│   └── Resources/           # Exercises.json, Assets.xcassets, animations
├── convex/                  # Empty placeholder; the MVP has no custom backend
├── .claude/agent/tasks/     # Strategic plan + implementation PRD (source of truth)
└── CLAUDE.md                # Repo guidance and architecture reference
```

As of the current clean rebuild, the US-A01 scaffold (App, DesignSystem, RootView, Assets), the US-A02 canonical domain enums (`Models/Enums.swift`), the US-A03 domain model structs (`Models/Exercise.swift`, `User.swift`, `Workout.swift`, `WorkoutLog.swift`), the US-A04 CoreData stack (`Persistence/`: `FitSnack.xcdatamodeld`, `PersistenceController`, `CDUser`/`CDWorkoutLog` + conversions, `MockPersistence`), the US-A05 app shell (service protocols and mocks, `ServiceContainer`, `AppState`, and onboarding-vs-main-tabs routing in `RootView`), the US-B01 bundled exercise library (`Resources/Exercises.json`, 42 zero-equipment movements with valid progression chains), the US-B02 exercise service (`Services/Mock/MockExerciseService.swift`: loads/caches/validates the library, throws `ExerciseLibraryError`, and answers the by-pillar/pattern/phase/difficulty-range and next-in-chain queries), the US-C01 engine Step 1 (`Services/Engine/SessionShapeSelection.swift`: the pure `SessionShapeTemplate.select(requestedMinutes:)` that maps minutes to single-focus / blend-light / blend-full and resolves back to the canonical `SessionShape`), the US-C02 engine Step 2 (`Services/Engine/PillarBalance.swift`: `PillarStaleness` computes days-since-worked per pillar from the logs, and `PillarPlan.select` picks the stalest pillar for single-focus - with a desk-worker mobility lean - or staleness-weighted time shares for a blend), and the US-C03 engine Step 3 (`Services/Engine/MovementPatternFocus.swift`: `PatternStaleness` computes days-since-worked per movement pattern, and `PatternFocus.rank`/`select` rank the chosen pillar's candidate patterns stalest-first and pick the lead pattern - holding back the most recent session's lead pattern so it is never repeated back-to-back, while honoring an explicit request), and the US-C04 engine Step 4 (`Services/Engine/ExercisePoolFilter.swift`: `InjuryContraindication` maps onboarding injury tags to contraindicated movement patterns, and `ExercisePoolFilter.eligiblePool` removes phase-gated / injury-unsafe / over-cap / repeatedly-skipped movements while enforcing the Zero-Equipment Floor, with `pool(forPattern:)` falling back to the safest bodyweight option - or reporting `.noSafeOption` - when filtering empties a needed pattern), the US-C05 engine Step 5 (`Services/Engine/ProgressionChainSelection.swift`: `AdvancementCriteria` parses an exercise's free-text `advancementCriteria` and checks it against logged performance, `ProgressionChainSelection.selectInChain` finds the user's frontier tier - the highest-order tier worked - and offers the next tier only when its criteria are cleared and that tier is still eligible, never leaping past an un-cleared or gated tier and defaulting a no-history user to the chain entry, and `select(pattern:)` integrates every chain for a pattern with the no-repeat-last-3 variety rule and an active-chain preference), and the US-C06 engine Step 6 (`Services/Engine/AdaptiveOverload.swift`: `AdaptiveOverload.target` reads the user's demonstrated capacity for the selected exercise from the most recent usable log - the worked set count and the rounded average per-set reps/hold-seconds - and prescribes a capacity-relative `OverloadTarget`, applying that session's `perceivedDifficulty` within one cycle (`tooHard` eases below capacity, `tooEasy` pushes above, `justRight`/unrated nudges progressively up, with the per-cycle bump curve as tunable constants), clamping the per-set target and set count to safety rails so a target is never a fixed heroic number, and falling back to the exercise's own `defaultReps`/`defaultDurationSeconds` when there is no usable history), and the US-C07 engine Step 7 (`Services/Engine/SessionAssembly.swift`: `SessionAssembly.assemble` chains Steps 1-6 over the eligible pool and assembles a fully-formed, playable `Workout` - always opening with a `.warmup` block, closing sessions over 10 min with a `.cooldown`, and structuring training blocks per the Step 1 shape - then a deterministic best-fit `fit` pass adds/drops whole exercises or individual sets, never the capacity-relative per-set target, until the planned `Σ(sets × est) + rests + transitions` wall-clock lands within ±1 min of the request; `MockWorkoutEngine` now drives this assembler with the validated library from the exercise service), and the US-C08 deterministic swap (`Services/Engine/ExerciseSwap.swift`: `ExerciseSwap.swap` returns a `SwapOutcome` - either an equivalent substitute drawn from the eligible pool (same pillar and pattern, within a ±1 `difficultyBandWidth`, inside the `slotToleranceSeconds` time budget, never duplicating a movement already in the session, carrying a fresh capacity-relative per-set target while preserving the original slot's set count and rest) or `.noAlternative` when no safe in-budget peer exists - exposed through `WorkoutEngineProtocol.swapExercise` and wired in `MockWorkoutEngine`) exist; with the Epic C engine pipeline (Steps 1-7 + swap) complete, only `ViewModels/` is still empty.
The v6 Epic D data foundation has begun: US-D01 (`Models/User.swift`) adds the nested `User.Why` (`statement` + optional `openingBias` pillar), `User.Duration` (`defaultMinutes`/`onboardingSeedMinutes`/`completedDurationEWMA`, with a `seeded(minutes:)` factory so `defaultMinutes == onboardingSeedMinutes`), and `User.ColdStart` (`sessionsLogged`/`active`, with a `.fresh` default) value types as three new top-level `User` fields - `primaryGoal` and the `UserProfile` shape are unchanged - each persisted as its own JSON-encoded `Data` column on `CDUser` (`whyData`/`durationData`/`coldStartData`) that decodes to documented defaults (empty `why`, duration seeded from `profile.typicalAvailableMinutes`, a fresh cold-start) when absent, so a pre-v6 record still loads.
US-D02 (`Models/WorkoutLog.swift`) adds `requestedMinutes: Int` (what the Ready Screen offered or the user set) and `wasReturn: Bool` (defaulting to `false`) as two new top-level `WorkoutLog` fields, and documents the existing `durationMinutes` as the actually-completed duration that feeds `duration.completedDurationEWMA` - the requested-vs-completed gap is the input Default Duration learning and the Disengagement signal read, and `wasReturn` marks a post-gap Return for the Re-entry Ramp; both persist as additive optional `NSNumber?` columns on `CDWorkoutLog` (`requestedMinutes`/`wasReturn`) that decode to documented defaults (`requestedMinutes == durationMinutes`, `wasReturn == false`) when absent, so a pre-v6 log still loads.
US-D03 (`Models/SessionPolicy.swift`) defines the always-valid `SessionPolicy` - `version`/`updatedAt`/`updatedBy` (`default`/`deterministic`/`llm`)/`progressionRate`/`pillarWeighting: [Pillar: Double]`/`varietyWindow` plus optional `coldStartContract`, `reentry`, and `note` - the single seam the AI Programmer (Epic F) writes and the deterministic engine (Epic E) reads; `SessionPolicy.default` is a deterministic, neutral starting policy (progression 1.0, equal weighting across all three pillars, variety window 3, no situational overrides) that reproduces pre-policy engine behavior exactly and persists whole (JSON-encoded) as `CDSessionPolicy`, keyed by `userId` and overwritten in place so the last-written policy survives relaunch and offline use.
The app root (`FitSnackApp`) injects the CoreData view context, the `ServiceContainer` (via `\.services`), and `AppState`; the CoreData stack is local-only until CloudKit sync lands in US-J02.
The rest lands story-by-story per the PRD.

---

## Source of Truth

| Document | Purpose |
|----------|---------|
| `.claude/agent/tasks/FitSnack-PRD-v6_070226.md` | Strategic plan (v6.0) - the discipline-first vision plus the v6 wedge (a daily-adaptive AI Programmer that writes a per-user Session Policy the deterministic engine runs on). Supersedes `FitSnack-PRD-v5.md` (kept for reference). |
| `.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md` | Implementation PRD and live progress tracker - the v6 MVP as ~51 user stories (US-A01 … US-N05) with acceptance criteria. Supersedes `prd-fitsnack-mvp_0626.md` (v5, kept for reference). |
| `CLAUDE.md` | Repo conventions and architecture for contributors and AI assistants. |

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
cd ios/FitSnack && xcodegen generate

# Build for the simulator
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

# Or open in Xcode
open ios/FitSnack/FitSnack.xcodeproj
```

### Run Tests

There is a single scheme, `FitSnack`, which builds the app and runs the `FitSnackTests` target.

```bash
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If xcodebuild cannot resolve the destination, list installed simulators with `xcrun simctl list devices available` and pass `-destination 'id=<UDID>'`.

---

## Design System

FitSnack uses a consistent design token system via `Theme.*` (`Theme.Colors`, `Theme.Typography`, `Theme.Spacing`) - always use these, never hardcode colors, fonts, or spacing.

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
