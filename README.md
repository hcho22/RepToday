# FitSnack — AI-Powered Micro-Workout App

**Open the app. Tell it how many minutes you have. Press play.**

FitSnack is an iOS app that generates personalized AI-powered workouts in seconds, designed for busy parents and professionals who have 5-30 minutes a day to exercise. No browsing, no choosing, no thinking — just workouts that fit your life.

---

## Why FitSnack?

Most fitness apps assume you have an hour to spare and the mental bandwidth to pick a routine. FitSnack assumes the opposite:

- **Zero-decision workouts** — AI generates a complete, personalized workout the moment you select a duration
- **Time-flexible by design** — Every workout is 5-30 minutes, dynamically generated — not pre-recorded videos cut to length
- **Progressive and intelligent** — Tracks your history, manages muscle group fatigue, and ensures progressive overload even in short sessions
- **Built for consistency, not intensity** — Rewards showing up for 5 minutes over grinding through hour-long sessions

---

## Target Audience

**Primary:** Working parents (ages 28-45) who previously exercised regularly but lost their routine. They don't lack motivation — they lack time and mental bandwidth.

**Secondary:** Busy professionals (ages 25-40) who travel frequently or work unpredictable hours and can't commit to a fixed gym schedule.

---

## Features

### Core Workout Loop

- **AI Workout Generation** — Select a duration (5-30 min), and the engine builds a structured workout with warmup, main blocks, and cooldown
- **Smart Exercise Selection** — Filters by available equipment, fitness level, injuries, and muscle group fatigue from recent workouts
- **MET-Based Calorie Calculation** — Accurate calorie estimates using Metabolic Equivalent values per exercise
- **Exercise Swapping** — Swap any exercise mid-workout with an AI-selected replacement matching the same muscle group and time budget

### Active Workout Experience

- Large, sweat-proof touch targets (60pt minimum on workout screens)
- Set-by-set tracking with haptic feedback on completion
- Automatic rest timer between sets
- Real-time progress bar and elapsed time display
- Exercise form tips displayed contextually

### Gamification & Streaks

- **Weekly Streak System** — Consecutive weeks where you hit your workout goal (default: 3/week)
- **XP & Leveling** — Earn XP for workouts, ratings, streaks, and personal records (6 level tiers from "Couch Explorer" to "Living Legend")
- **10 Unlockable Badges** — "First Rep," "Early Bird," "Speed Demon," "Century," and more
- **Streak Saver** — A 2-3 minute micro-workout offered on Sundays when you're one workout short of your goal

### Progress Tracking

- Calendar heat map (GitHub-style) showing workout days
- Workout history with detailed exercise logs
- Monthly stats: workouts completed, total minutes, calories burned

### Subscription Model

| | Free | Premium ($7.99/mo or $59.99/yr) |
|---|---|---|
| AI workouts | 3/week | Unlimited |
| Workout history | Last 7 days | Full history with analytics |
| Streak tracking | Yes | Yes + unlimited freezes |
| AI insights & summaries | - | Yes |
| Shareable workout cards | - | Premium designs |

14-day free trial included on first install.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Platform** | iOS 17.0+, Swift 5.9, Xcode 16.3 |
| **UI Framework** | SwiftUI with Observation framework (`@Observable`) |
| **Architecture** | MVVM + Protocol-based service injection |
| **Persistence** | SwiftData (`SDUserProfile`, `SDWorkout`) |
| **Backend** | Convex (planned post-MVP, placeholder in `convex/`) |
| **Subscriptions** | StoreKit 2 |
| **Health** | HealthKit (read/write workout data) |
| **Bundle ID** | `com.fitsnack.app` |

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
│  AuthService, WorkoutService, UserService, etc. │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Implementations                                │
│  Mock (Phase 1) → Convex (Post-MVP)             │
│  Swap one line in ServiceContainer.swift        │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Protocol-based services** — All services are protocol-defined with mock implementations. To swap a mock for a real backend, change one line in `ServiceContainer` — views and viewmodels remain untouched.
- **SwiftData with domain separation** — SwiftData models (`SD*`) handle persistence; domain models are plain `Codable` structs. Conversion happens via `toUserProfile()`/`update(from:)` methods.
- **Pure Swift workout generation** — `WorkoutGenerationEngine` runs entirely on-device with no network calls: filter exercises → allocate time → balance muscle groups → fit sets/reps.
- **Environment-based DI** — `ServiceContainer` holds all service instances, injected at the app root via a custom `EnvironmentKey`.

---

## Project Structure

```
FitSnack/
├── ios/FitSnack/
│   ├── FitSnackApp.swift              # App entry point, ModelContainer + DI setup
│   ├── DI/
│   │   └── ServiceContainer.swift     # All service protocols composed
│   ├── Models/                        # Domain models + enums (Codable structs)
│   ├── Views/
│   │   ├── Onboarding/               # 8-screen onboarding flow
│   │   ├── Home/                      # Today's workout, quick start, AI insights
│   │   ├── Workout/                   # Active workout, rest timer, exercise swap
│   │   ├── Progress/                  # History, calendar heat map
│   │   ├── Challenges/                # Badges, leaderboard placeholder
│   │   ├── Profile/                   # User profile tab
│   │   ├── Settings/                  # Preferences, subscription, equipment
│   │   └── Paywall/                   # Premium upgrade screen
│   ├── ViewModels/                    # @Observable view models
│   ├── Services/
│   │   ├── Protocols/                 # Service interfaces
│   │   ├── Mock/                      # Mock implementations (Phase 1)
│   │   ├── WorkoutGenerationEngine.swift
│   │   └── CalorieCalculator.swift
│   ├── Components/                    # Reusable UI components
│   ├── DesignSystem/                  # Theme, colors, typography, spacing
│   ├── Persistence/                   # SwiftData models + ModelContainer
│   ├── Utilities/                     # Constants, AppState
│   ├── Resources/
│   │   └── Exercises.json             # 30-exercise database with full metadata
│   └── FitSnackTests/                 # Unit tests
├── convex/                            # Backend placeholder (post-MVP)
├── FitSnack_PRD_v1.md                 # Full product requirements document
├── FitSnack_Phase1_Plan.md            # Phase 1 implementation plan
└── CLAUDE.md                          # AI assistant instructions
```

---

## Getting Started

### Prerequisites

- **Xcode 16.3+**
- **iOS 17.0+ Simulator or device**
- **XcodeGen** (for project generation from `project.yml`)

```bash
brew install xcodegen
```

### Build & Run

```bash
# Generate Xcode project
cd ios/FitSnack && xcodegen generate

# Build for simulator
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj \
  -scheme FitSnack \
  -sdk iphonesimulator \
  -configuration Debug build

# Or open in Xcode
open ios/FitSnack/FitSnack.xcodeproj
```

### Run Tests

```bash
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj \
  -scheme FitSnackTests \
  -sdk iphonesimulator \
  -configuration Debug test
```

---

## Design System

FitSnack uses a consistent design token system via `Theme.*`:

| Token | Value |
|-------|-------|
| **Brand Color** | `#4F46E5` (Indigo) |
| **Success** | `#10B981` (Green) |
| **Fire/Streaks** | `#F97316` (Orange) |
| **Danger** | `#EF4444` (Red) |
| **Button Height** | 56pt |
| **Card Corner Radius** | 16pt |
| **Min Touch Target** | 44pt (60pt on workout screens) |
| **Typography** | SF Pro (system) with semantic scale |

Dark mode is supported via asset catalog color variants.

---

## Navigation

```
Tab Bar (4 tabs)
├── Home        — Today's workout, quick start, AI insight
├── Progress    — History, calendar heat map, stats
├── Challenges  — Badges grid, leaderboard placeholder
└── Profile     — Settings, subscription, preferences
```

`AppState` (`@Observable`) manages onboarding vs. main tab navigation, persisted to UserDefaults.

---

## Workout Generation Engine

The on-device `WorkoutGenerationEngine` follows this pipeline:

1. **Filter** — Select exercises matching user's equipment, fitness level, and injury constraints
2. **Time Allocation** — Divide requested duration into warmup, main blocks, and cooldown
3. **Muscle Balancing** — Avoid muscle groups worked in recent sessions, distribute load across the week
4. **Set/Rep Fitting** — Calculate sets, reps, and rest periods to fill the time budget precisely

Calorie estimation uses the MET formula:

```
Calories = MET_value x weight_kg x duration_hours
```

---

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **Phase 1** (MVP) | Core workout loop, streaks, onboarding, subscriptions | In Progress |
| **Phase 2** (Engagement) | XP system, badges, AI summaries, progress charts, streak freezes | Planned |
| **Phase 3** (Growth) | Friends, leaderboards, challenges, widgets, Dynamic Island | Planned |
| **Phase 4** (Advanced AI) | Voice coaching, form checking (Vision), Apple Watch, calendar integration | Future |

---

## Key Metrics

| Metric | Month 3 Target | Month 6 Target |
|--------|----------------|----------------|
| Day 7 Retention | 20% | 25% |
| Onboarding to 1st Workout | 60% | 70% |
| Free to Paid Conversion | 5% | 8% |
| Avg Workouts/Week (active) | 2.5 | 3.0 |
| App Store Rating | 4.5+ | 4.7+ |

**North Star Metric:** Weekly Active Exercisers (WAE) — users completing at least 1 workout per week.

---

## Convex Backend Integration

Post-MVP, the backend migrates to [Convex](https://convex.dev):

1. Define TypeScript schema in `convex/` mirroring SwiftData models
2. Write query/mutation/action functions
3. Create `Convex*Service` implementations of existing protocols
4. Swap implementations in `ServiceContainer.swift`

Zero changes to views or view models required.

---

## License

All rights reserved. This is a private project.
