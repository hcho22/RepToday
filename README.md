# FitSnack - Discipline-First Micro-Workout App

**Open the app. Tell it how many minutes you have. Press play.**

FitSnack is an iOS app for busy, desk-bound adults who have 5-30 minutes a day to move.
A deterministic, on-device engine generates a complete zero-equipment session the moment you pick a duration - no browsing, no choosing, no thinking.
The goal is not intensity; it is the habit of showing up.

---

## Why FitSnack?

Most fitness apps assume you have an hour to spare and the mental bandwidth to pick a routine.
FitSnack assumes the opposite:

- **Discipline first** - the entry promise is consistency, not strength. Strength is earned over time, never sold up front.
- **Zero-decision workouts** - the engine builds a complete warmup-to-cooldown session instantly when you choose a duration.
- **Zero-equipment floor** - every movement is bodyweight, so a session works anywhere with no gear.
- **Time-flexible by design** - every session is 5-30 minutes and assembled to land within ±1 minute of the time you asked for.
- **Forgiving by design** - a single miss dents your Consistency Score but never zeroes it; a 5-minute session counts as a full show-up.

---

## Target Audience

**Primary:** Busy, desk-bound adults who want to move but lack the time and mental bandwidth to plan workouts.
They do not need another catalog of exercises to browse - they need a session handed to them.

**Secondary:** People returning to movement after a lapse, who are discouraged by streak-based apps that punish a single missed day.

---

## Discipline Phase and Strength Phase

Every user starts in the **Discipline Phase**, where consistency is the only goal.
The **Strength Phase** is earned - never user-selectable - by sustaining the habit and progressing through the foundational movement chains.

At launch no user has earned the Strength Phase, so the MVP ships the Discipline-Phase experience with the deterministic `PhaseEvaluator` already in place.
The evaluator promotes a user only when both consistency (a sustained Consistency Score over a rolling window) and competence (clearing the entry tiers of the foundational chains) hold.

### Consistency, not gamification

There is no XP, no levels, and no badges.
The fragile streak is replaced by a forgiving **Consistency Score** - a rolling, weighted measure of showing up, with recent weeks weighted more heavily.
`longestChain` is tracked and surfaced as an earned point of pride, never as a threat, and all copy is identity-framed ("you're someone who moves") rather than loss-framed.

---

## The Deterministic Engine

The session generator is pure Swift, runs entirely on-device with no network and no LLM, and targets sub-100ms latency.
The pipeline runs in seven steps:

1. **Session shape** - 5-10 min single-focus; 15 min light blend; 20-30 min full blend.
2. **Pillar balance** - choose the stalest pillar by days-since-worked; bias short sessions toward mobility for users who sit 6+ hours.
3. **Movement-pattern focus** - rank patterns by staleness and never repeat yesterday's primary pattern.
4. **Filter pool** - drop exercises by phase, injuries, difficulty cap, and recent skips; everything is bodyweight.
5. **Progression-chain selection** - pick the user's current chain position and offer the next when advancement criteria are met.
6. **Adaptive Overload** - prescribe capacity-relative reps, sets, and holds; in-session feedback adjusts within one cycle.
7. **Assemble and fit timing** - always open with a warmup, add a cooldown over 10 min, and land within ±1 min of the requested time.

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget.
No step ever calls a model or a server.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Platform** | iOS 17.0+, Swift 5.9, Xcode 16.3 |
| **UI Framework** | SwiftUI with the Observation framework (`@Observable`) |
| **Architecture** | MVVM + protocol-based service injection |
| **Persistence** | CoreData backed by `NSPersistentCloudKitContainer` (`CDUser`, `CDWorkoutLog`) |
| **Identity** | Sign in with Apple |
| **Sync** | CloudKit private database |
| **Health** | HealthKit (on-device workout writes) |
| **Subscriptions** | StoreKit 2 |
| **Backend** | None - the MVP is fully Apple-native with no custom server |
| **Bundle ID** | `com.fitsnack.app` |

The core loop works fully offline and with no iCloud account; CloudKit handles sync and backup when available.
There is no hosting cost - an Apple Developer account is the only requirement.

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
│  Auth, Exercise, User, Workout, Health, etc.    │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Implementations                                │
│  Mock (MVP) → real implementations later        │
│  Swap one line in ServiceContainer.swift        │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Protocol-based services** - all services are protocol-defined with mock implementations. To swap a mock for a real implementation, change one line in `ServiceContainer` - views and viewmodels remain untouched.
- **CoreData with domain separation** - CoreData entities (`CDUser`, `CDWorkoutLog`) handle persistence; domain models are plain `Codable` structs. Conversion happens via `toUser()`/`update(from:)`-style methods, with complex nested fields stored as JSON-encoded `Data`.
- **Deterministic on-device generation** - the session engine runs entirely on-device with no network or LLM call: shape the session, balance pillars and patterns, filter the pool, select progression chains, apply Adaptive Overload, then assemble and fit the timing.
- **Environment-based DI** - `ServiceContainer` holds all service instances, injected at the app root via a custom `EnvironmentKey`.

---

## Project Structure

```
FitSnack/
├── ios/FitSnack/                       # The SwiftUI app (the entire MVP)
│   ├── project.yml                     # XcodeGen project definition
│   └── FitSnack/
│       ├── App/                        # App entry point (FitSnackApp.swift)
│       ├── DesignSystem/               # Theme tokens (Theme.swift)
│       ├── Models/                     # Domain enums and Codable structs
│       ├── Persistence/                # CoreData stack (NSPersistentCloudKitContainer) + conversions
│       ├── Services/
│       │   ├── Protocols/              # Service protocol definitions
│       │   └── Mock/                   # Mock implementations wired in ServiceContainer
│       ├── DI/                         # ServiceContainer + environment injection
│       ├── ViewModels/                 # @Observable view models
│       ├── Views/                      # Onboarding, Home, Active session, Post-session, Progress
│       ├── Utilities/                  # AppState and shared helpers
│       └── Resources/                  # Exercises.json, Assets.xcassets, animations
├── proxy/                              # Cloudflare/Wrangler API-key proxy for deferred Phase 2 LLM (not used in MVP)
├── convex/                             # Empty placeholder; the MVP has no custom backend
├── artifacts/                          # Reports, specs, and learning logs
├── CLAUDE.md                           # Repository guidance and conventions
└── .claude/agent/tasks/                # Strategic plan + implementation PRD (source of truth)
```

> **Status: clean rebuild in progress.**
> The previous Phase 2 app (XP/badges/streaks, AI services, SwiftData) was removed and lives only in git history (commit `23fd56f`) as reference.
> Work proceeds story-by-story against the PRD, so most folders above are scaffolded and fill in as their owning story lands.
> As of the current rebuild, only the US-A01 scaffold exists: the app shell, the `Theme` design tokens, and a placeholder `RootView`.

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

# Build for simulator
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

# Or open in Xcode
open ios/FitSnack/FitSnack.xcodeproj
```

### Run Tests

The single `FitSnack` scheme builds the app and runs the `FitSnackTests` target:

```bash
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If xcodebuild cannot resolve the destination, list available simulators with `xcrun simctl list devices available` and pass `-destination 'id=<UDID>'`.

---

## Design System

Every view pulls colors, fonts, and spacing from `Theme.*` - never hardcoded literals - so changing a token updates the whole app.

| Token | Value |
|-------|-------|
| **Accent** | `Theme.Colors.accent` (asset-catalog `AccentColor`) |
| **Button Height** | 56pt |
| **Card Corner Radius** | 16pt |
| **Min Touch Target** | 44pt (60pt on active workout screens) |
| **Typography** | System fonts (`.rounded`) on a semantic scale, so Dynamic Type works out of the box |

Color tokens resolve from the asset catalog where a named color exists and fall back to a sensible system color otherwise, so the app always renders - even before the full palette is designed.
Accessibility is a first-class concern throughout: VoiceOver, Dynamic Type, Reduce Motion (static demo fallback), and haptics with an audio alternative.

---

## Navigation

`AppState` (`@Observable`, persisted to UserDefaults) controls onboarding versus the main app and the selected tab.
The real routing replaces the placeholder `RootView` as the onboarding and main screens land story-by-story.

---

## Exercise Library

The exercise library is roughly 38 bodyweight movements in `Resources/Exercises.json`, every one with `equipment == []` (the Zero-Equipment Floor).
It is loaded and integrity-checked by `MockExerciseService`.
The library lands with its owning story during the rebuild.

---

## Subscriptions

The full core loop is free and unlimited - generating sessions is never gated.
Premium (via StoreKit 2) unlocks added depth on top of that free core.
See the PRD for the current monetization detail.

---

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **MVP (Discipline Phase)** | Deterministic engine, Consistency Score, onboarding, CoreData/CloudKit persistence | In progress (clean rebuild) |
| **Strength Phase** | Earned per-user via the `PhaseEvaluator`; full Strength catalog | Foundation in place, catalog deferred |
| **Phase 2 (AI language layer)** | Template-free LLM summaries and weekly narratives - language only, never workout generation | Deferred (proxy scaffolded in `proxy/`) |

When the AI layer arrives it does language only (summaries, weekly narratives) and never generates or adapts a workout; the deterministic engine remains the sole source of sessions.

---

## Source of Truth

- **Strategic plan:** `.claude/agent/tasks/FitSnack-PRD-v5.md` - the discipline-first vision, domain concepts, engine design, and phase model.
- **Implementation PRD / progress tracker:** `.claude/agent/tasks/prd-fitsnack-mvp_0626.md` - 30 user stories (US-A01 … US-J04) with acceptance criteria and validation tests, flipped to `[x]` as each story completes.
- **Repository guidance:** `CLAUDE.md` - build commands, architecture, and conventions.

The root `FitSnack_PRD_v1.md`, `FitSnack_PRD_v2.md`, and `FitSnack_Phase1_Plan.md` are earlier, version-stamped product specs kept for history; the two PRDs above are authoritative.

---

## License

All rights reserved. This is a private project.
