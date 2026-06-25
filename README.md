# FitSnack - Discipline-First Micro-Workout App

**Open the app. Tell it how many minutes you have. Press play.**

FitSnack is an iOS app for busy, desk-bound adults who can give exercise 5-30 minutes a day.
It exists to build one thing: the discipline of showing up.
The user says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session that blends bodyweight strength and mobility.
No browsing, no choosing, no thinking.

> **Status:** clean rebuild in progress.
> The previous app (XP/badges/streaks, AI services, SwiftData) was removed and lives only in git history as reference.
> Work proceeds story-by-story against the PRD; today only the US-A01 scaffold exists.

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
| **Persistence** | CoreData backed by `NSPersistentCloudKitContainer` (entities `CDUser`, `CDWorkoutLog`) |
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
│   │   └── Mock/            # Mock implementations wired in ServiceContainer
│   ├── DI/                  # ServiceContainer + environment injection
│   ├── ViewModels/          # @Observable view models
│   ├── Views/               # SwiftUI screens (Onboarding, Home, Active session, Post-session, Progress)
│   ├── Utilities/           # AppState and shared helpers
│   └── Resources/           # Exercises.json, Assets.xcassets, animations
├── convex/                  # Empty placeholder; the MVP has no custom backend
├── .claude/agent/tasks/     # Strategic plan + implementation PRD (source of truth)
└── CLAUDE.md                # Repo guidance and architecture reference
```

As of the current clean rebuild, only the US-A01 scaffold exists (App, DesignSystem, RootView, Assets, empty folders).
The rest lands story-by-story per the PRD.

---

## Source of Truth

| Document | Purpose |
|----------|---------|
| `.claude/agent/tasks/FitSnack-PRD-v5.md` | Strategic plan - the discipline-first vision, domain concepts, engine design, and phase model. |
| `.claude/agent/tasks/prd-fitsnack-mvp_0626.md` | Implementation PRD and live progress tracker - 30 user stories (US-A01 … US-J04) with acceptance criteria. |
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
